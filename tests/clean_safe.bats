#!/usr/bin/env bats
load test_helper

setup ()    { setup_fake_home; make_stub brew 1; make_stub xcode-select 1; make_stub pgrep 1; }
teardown () { teardown_fake_home; }

@test "--dry-run previews removals, deletes nothing, writes no log" {
  mkdir -p "$HOME/.npm/junk" "$HOME/.gradle/caches/junk"
  run bash "$SCRIPTS/clean-safe.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN"* ]]
  [[ "$output" == *"would remove"*".npm"* ]]
  [[ "$output" == *"would remove"*".gradle/caches"* ]]
  [ -d "$HOME/.npm/junk" ]
  [ -d "$HOME/.gradle/caches/junk" ]
  [ ! -e "$HOME/Library/Logs/mac-storage-cleaner/operations.log" ]
}

@test "dry-run preview respects the whitelist (preview == reality)" {
  mkdir -p "$HOME/.npm/junk"
  printf '~/.npm\n' > "$MSC_WHITELIST_FILE"
  run bash "$SCRIPTS/clean-safe.sh" --dry-run
  [[ "$output" == *"skipped (whitelisted): $HOME/.npm"* ]]
  [[ "$output" != *"would remove"*".npm"* ]]
}

@test "real run still deletes (regression)" {
  mkdir -p "$HOME/.npm/junk"
  run bash "$SCRIPTS/clean-safe.sh"
  [ ! -e "$HOME/.npm" ]
  grep -q "removed" "$HOME/Library/Logs/mac-storage-cleaner/operations.log"
}

@test "gradle caches are skipped while a Gradle daemon runs" {
  mkdir -p "$HOME/.gradle/caches/junk"
  make_stub pgrep 0            # every probe reports "running"
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped (in use"*".gradle/caches"* ]]
  [ -d "$HOME/.gradle/caches/junk" ]
}

@test "unknown process state fails closed (pgrep errors => skip)" {
  mkdir -p "$HOME/Library/Developer/Xcode/DerivedData/junk"
  make_stub pgrep 2            # rc 2 = probe error, not "no match"
  run bash "$SCRIPTS/clean-safe.sh"
  [[ "$output" == *"skipped (process state unknown"*"DerivedData"* ]]
  [ -d "$HOME/Library/Developer/Xcode/DerivedData/junk" ]
}

@test "idle processes let deletion proceed" {
  mkdir -p "$HOME/.gradle/caches/junk"
  make_stub pgrep 1            # rc 1 = no matching process
  run bash "$SCRIPTS/clean-safe.sh"
  [ ! -e "$HOME/.gradle/caches" ]
}

@test "guard runs before the dry-run gate (preview == reality)" {
  mkdir -p "$HOME/.gradle/caches/junk"
  make_stub pgrep 0
  run bash "$SCRIPTS/clean-safe.sh" --dry-run
  [[ "$output" == *"skipped (in use"* ]]
  [[ "$output" != *"would remove"*".gradle/caches"* ]]
}

@test "composer and gem caches are cleared" {
  mkdir -p "$HOME/Library/Caches/composer/files" "$HOME/.composer/cache/repo" \
           "$HOME/.gem/ruby/3.3.0/cache"
  touch "$HOME/.gem/ruby/3.3.0/cache/foo-1.0.gem"
  run bash "$SCRIPTS/clean-safe.sh"
  [ ! -e "$HOME/Library/Caches/composer" ]
  [ ! -e "$HOME/.composer/cache" ]
  [ ! -e "$HOME/.gem/ruby/3.3.0/cache" ]
}

@test "Handoff pasteboard: only items older than 60 minutes go" {
  PB="$HOME/Library/Group Containers/group.com.apple.coreservices.useractivityd/shared-pasteboard"
  mkdir -p "$PB/old-item" "$PB/fresh-item"
  touch -t "$(date -v-2H +%Y%m%d%H%M)" "$PB/old-item"
  run bash "$SCRIPTS/clean-safe.sh"
  [ ! -e "$PB/old-item" ]
  [ -d "$PB/fresh-item" ]
}

@test "conda cleanup runs the owner command, never rm" {
  make_stub conda 0
  mkdir -p "$HOME/miniconda3/pkgs/somepkg"
  run bash "$SCRIPTS/clean-safe.sh"
  # bash 3.2: a bare `[[ ]]` failure does not trigger errexit unless it is the
  # final statement, so `|| false` forces the failure to actually abort the
  # test (otherwise the trailing `[ -d ]` below — true regardless of whether
  # conda ever ran — would mask a missing "conda clean" in $output).
  [[ "$output" == *"conda clean"* ]] || false
  [ -d "$HOME/miniconda3/pkgs/somepkg" ]   # rm never touches pkgs
}
