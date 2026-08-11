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

# G1: an exact-name mismatch (folder name != real process name) must not fail
# OPEN. Stub pgrep so the exact-name probe (-qix) always misses, but the
# substring/command-line probe (-qif) hits — that alone must still count as
# "running" and block the delete (over-matching is the safe direction).
@test "Electron guard: exact-name miss but command-line substring hit still counts as running (name mismatch fails closed, not open) (G1)" {
  mkdir -p "$HOME/Library/Application Support/FakeApp/Cache/junk"
  PGREP_STUB_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-stub-g1.XXXXXX")"
  cat > "$PGREP_STUB_DIR/pgrep" <<'PGSTUB'
#!/bin/bash
case "$*" in
  *-qif*) exit 0 ;;
  *) exit 1 ;;
esac
PGSTUB
  chmod +x "$PGREP_STUB_DIR/pgrep"
  export PATH="$PGREP_STUB_DIR:$PATH"
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped (app running"* ]] || false
  [ -d "$HOME/Library/Application Support/FakeApp/Cache/junk" ]
}

# G1: a clean double miss (both the exact-name AND the substring probe report
# no match) is the ONLY case that counts as idle and lets deletion proceed.
@test "Electron guard: a clean double miss on both probes still removes the cache (G1)" {
  mkdir -p "$HOME/Library/Application Support/FakeApp/Cache/junk"
  PGREP_STUB_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-stub-g1b.XXXXXX")"
  cat > "$PGREP_STUB_DIR/pgrep" <<'PGSTUB'
#!/bin/bash
exit 1
PGSTUB
  chmod +x "$PGREP_STUB_DIR/pgrep"
  export PATH="$PGREP_STUB_DIR:$PATH"
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/Library/Application Support/FakeApp/Cache" ]
}

# G1: assert the exact-name probe is now case-insensitive (-i somewhere in
# its args), not just a bare `pgrep -x`.
@test "Electron guard passes case-insensitive (-i) flags on the exact-name probe (G1)" {
  mkdir -p "$HOME/Library/Application Support/FakeApp/Cache/junk"
  PGREP_STUB_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-stub-g1c.XXXXXX")"
  LOGF="$PGREP_STUB_DIR/pgrep.args.log"
  cat > "$PGREP_STUB_DIR/pgrep" <<PGSTUB
#!/bin/bash
printf '%s\n' "\$*" >> "$LOGF"
exit 1
PGSTUB
  chmod +x "$PGREP_STUB_DIR/pgrep"
  export PATH="$PGREP_STUB_DIR:$PATH"
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  grep -q -- '-qix' "$LOGF"
}
