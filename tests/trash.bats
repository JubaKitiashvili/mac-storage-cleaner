#!/usr/bin/env bats
load test_helper

setup ()    { setup_fake_home; }
teardown () { teardown_fake_home; }

@test "trash_path uses MSC_TRASH_BIN when executable" {
  mkdir -p "$HOME/target-dir"
  cat > "$HOME/fake-trash" <<EOF
#!/bin/bash
mv "\$1" "\$HOME/.Trash/"
EOF
  chmod +x "$HOME/fake-trash"
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; MSC_TRASH_BIN='$HOME/fake-trash' trash_path '$HOME/target-dir' && echo method=\$TRASH_METHOD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"method=trash-cli"* ]] || false
  [ -d "$HOME/.Trash/target-dir" ]
}

@test "trash_path falls back to same-volume mv when binary and Finder both fail" {
  mkdir -p "$HOME/fallback-dir"; touch "$HOME/fallback-dir/f"
  make_stub osascript 1
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; MSC_TRASH_BIN=/nonexistent trash_path '$HOME/fallback-dir' && echo method=\$TRASH_METHOD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"method=mv"* ]] || false
  [ ! -e "$HOME/fallback-dir" ]
  [ -d "$HOME/.Trash/fallback-dir" ]
}

@test "mv fallback uniquifies when the Trash already holds that name" {
  mkdir -p "$HOME/dup" "$HOME/.Trash/dup"
  make_stub osascript 1
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; MSC_TRASH_BIN=/nonexistent trash_path '$HOME/dup'"
  [ "$status" -eq 0 ]
  [ -d "$HOME/.Trash/dup" ]                       # original Trash item untouched
  [ "$(find "$HOME/.Trash" -maxdepth 1 -name 'dup*' | wc -l | tr -d ' ')" -eq 2 ]
}

@test "trash_path returns 2 (refused) on a protected path without touching it" {
  make_stub osascript 1
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; MSC_TRASH_BIN=/nonexistent trash_path '$HOME/Library'"
  [ "$status" -eq 2 ]
}

@test "MSC_DRY_RUN=1 previews trash-items.sh: item survives, no log file (C2)" {
  mkdir -p "$HOME/Downloads/old-stuff"
  MSC_DRY_RUN=1 run bash "$SCRIPTS/trash-items.sh" "$HOME/Downloads/old-stuff"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN"* ]] || false
  [[ "$output" == *"would trash"*"old-stuff"* ]] || false
  [ -d "$HOME/Downloads/old-stuff" ]
  [ ! -e "$HOME/Library/Logs/mac-storage-cleaner/operations.log" ]
}

@test "trash-items.sh real mode still trashes and logs (C2 regression, keep green)" {
  mkdir -p "$HOME/Downloads/old-stuff"
  make_stub osascript 1
  run bash "$SCRIPTS/trash-items.sh" "$HOME/Downloads/old-stuff"
  [ "$status" -eq 0 ]
  [[ "$output" == *"trashed"*"old-stuff"* ]] || false
  [ ! -e "$HOME/Downloads/old-stuff" ]
  grep -q "trashed" "$HOME/Library/Logs/mac-storage-cleaner/operations.log"
}

@test "clean-safe.sh skips a symlinked safe-tier path instead of deleting through it (F4a)" {
  mkdir -p "$HOME/real-cache/data"
  ln -s "$HOME/real-cache" "$HOME/.npm"
  make_stub brew 1; make_stub xcode-select 1
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped (symlink"* ]] || false
  [ -d "$HOME/real-cache/data" ]
  [ -L "$HOME/.npm" ]
}

@test "trash_path on a symlink skips Finder entirely and uses mv, moving only the link (F4b)" {
  mkdir -p "$HOME/real-target"
  ln -s "$HOME/real-target" "$HOME/link-to-target"
  make_stub osascript 0   # a stub that would "succeed" if Finder were ever invoked
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; MSC_TRASH_BIN=/nonexistent trash_path '$HOME/link-to-target' && echo method=\$TRASH_METHOD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"method=mv"* ]] || false
  [ -L "$HOME/.Trash/link-to-target" ]
  [ -d "$HOME/real-target" ]
}
