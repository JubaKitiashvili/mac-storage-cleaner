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
  [[ "$output" == *"method=trash-cli"* ]]
  [ -d "$HOME/.Trash/target-dir" ]
}

@test "trash_path falls back to same-volume mv when binary and Finder both fail" {
  mkdir -p "$HOME/fallback-dir"; touch "$HOME/fallback-dir/f"
  make_stub osascript 1
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; MSC_TRASH_BIN=/nonexistent trash_path '$HOME/fallback-dir' && echo method=\$TRASH_METHOD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"method=mv"* ]]
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
