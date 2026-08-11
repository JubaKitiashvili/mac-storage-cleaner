#!/usr/bin/env bats
# A4: guarded Electron/Chromium Application Support cache auto-clean.
load test_helper

setup ()    { setup_fake_home; make_stub brew 1; make_stub xcode-select 1; make_stub pgrep 1; }
teardown () { teardown_fake_home; }

@test "Electron-style app cache is removed when the app is not running" {
  mkdir -p "$HOME/Library/Application Support/FakeApp/Cache/junk"
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/Library/Application Support/FakeApp/Cache" ]
}

@test "Electron-style app cache is skipped while the app is running (fail closed)" {
  mkdir -p "$HOME/Library/Application Support/FakeApp/Cache/junk"
  make_stub pgrep 0   # every probe reports "running"
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped (app running"* ]] || false
  [ -d "$HOME/Library/Application Support/FakeApp/Cache/junk" ]
}

@test "Electron-style app cache dry-run previews without deleting" {
  mkdir -p "$HOME/Library/Application Support/FakeApp/Cache/junk"
  run bash "$SCRIPTS/clean-safe.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would remove"*"FakeApp/Cache"* ]] || false
  [ -d "$HOME/Library/Application Support/FakeApp/Cache/junk" ]
}

@test "whitelisting the app's Application Support dir protects its cache" {
  mkdir -p "$HOME/Library/Application Support/FakeApp/Cache/junk"
  printf '~/Library/Application Support/FakeApp\n' > "$MSC_WHITELIST_FILE"
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped (whitelisted)"* ]] || false
  [ -d "$HOME/Library/Application Support/FakeApp/Cache/junk" ]
}
