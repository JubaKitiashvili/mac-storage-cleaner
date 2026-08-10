#!/usr/bin/env bats
load test_helper

setup ()    { setup_fake_home; make_stub brew 1; make_stub xcode-select 1; }
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
