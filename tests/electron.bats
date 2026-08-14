#!/usr/bin/env bats
# A4: guarded Electron/Chromium Application Support cache auto-clean.
load test_helper

setup ()    { setup_fake_home; make_stub brew 1; make_stub xcode-select 1; make_stub ps 0 "/sbin/launchd"; }
teardown () { teardown_fake_home; }

@test "Electron-style app cache is removed when the app is not running" {
  mkdir -p "$HOME/Library/Application Support/FakeApp/Cache/junk"
  run bash "$SCRIPTS/clean-safe.sh" --apply
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/Library/Application Support/FakeApp/Cache" ]
}

@test "Electron-style app cache is skipped while the app is running (fail closed)" {
  mkdir -p "$HOME/Library/Application Support/FakeApp/Cache/junk"
  make_stub ps 0 "1234 /Applications/FakeApp.app/Contents/MacOS/FakeApp"   # process snapshot shows it running
  run bash "$SCRIPTS/clean-safe.sh" --apply
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
  run bash "$SCRIPTS/clean-safe.sh" --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped (whitelisted)"* ]] || false
  [ -d "$HOME/Library/Application Support/FakeApp/Cache/junk" ]
}

# R1(a): pgrep -f treats its pattern as an ERE, so an app dir literally named
# "FakeApp (Beta)" would build a regex whose parens are GROUPING — the
# literal process name then never matches its own process (fail-open, the
# bug this rewrite fixes). A literal `ps` snapshot + `grep -F` must still
# catch it and block deletion.
@test "Electron guard: literal parens in app name match via ps+grep -F (metachar-proof, not regex) (R1a)" {
  mkdir -p "$HOME/Library/Application Support/FakeApp (Beta)/Cache/junk"
  make_stub ps 0 "1234 /Applications/FakeApp (Beta).app/Contents/MacOS/FakeApp (Beta)"
  run bash "$SCRIPTS/clean-safe.sh" --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped (app running"* ]] || false
  [ -d "$HOME/Library/Application Support/FakeApp (Beta)/Cache/junk" ]
}

# R1(b): a clean ps snapshot containing only unrelated processes is genuine
# idle evidence — deletion proceeds.
@test "Electron guard: ps snapshot with only unrelated lines counts as idle — cache removed (R1b)" {
  mkdir -p "$HOME/Library/Application Support/FakeApp (Beta)/Cache/junk"
  make_stub ps 0 "5678 /usr/sbin/some-other-daemon --flag"
  run bash "$SCRIPTS/clean-safe.sh" --apply
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/Library/Application Support/FakeApp (Beta)/Cache" ]
}

# R1(c): a failed/empty ps snapshot is unknown state, not idle — fail closed.
@test "Electron guard: ps snapshot failure (rc<>0 / empty) is unknown — skipped, not removed (R1c)" {
  mkdir -p "$HOME/Library/Application Support/FakeApp (Beta)/Cache/junk"
  make_stub ps 1
  run bash "$SCRIPTS/clean-safe.sh" --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped (app running"* ]] || false
  [ -d "$HOME/Library/Application Support/FakeApp (Beta)/Cache/junk" ]
}
