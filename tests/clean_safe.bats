#!/usr/bin/env bats
load test_helper

setup ()    { setup_fake_home; make_stub brew 1; make_stub xcode-select 1; make_stub pgrep 1; }
teardown () { teardown_fake_home; }

@test "--dry-run previews removals, deletes nothing, writes no log" {
  mkdir -p "$HOME/.npm/junk" "$HOME/.gradle/caches/junk"
  run bash "$SCRIPTS/clean-safe.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN"* ]] || false
  [[ "$output" == *"would remove"*".npm"* ]] || false
  [[ "$output" == *"would remove"*".gradle/caches"* ]] || false
  [ -d "$HOME/.npm/junk" ]
  [ -d "$HOME/.gradle/caches/junk" ]
  [ ! -e "$HOME/Library/Logs/mac-storage-cleaner/operations.log" ]
}

@test "dry-run preview respects the whitelist (preview == reality)" {
  mkdir -p "$HOME/.npm/junk"
  printf '~/.npm\n' > "$MSC_WHITELIST_FILE"
  run bash "$SCRIPTS/clean-safe.sh" --dry-run
  [[ "$output" == *"skipped (whitelisted): $HOME/.npm"* ]] || false
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
  [[ "$output" == *"skipped (in use"*".gradle/caches"* ]] || false
  [ -d "$HOME/.gradle/caches/junk" ]
}

@test "unknown process state fails closed (pgrep errors => skip)" {
  mkdir -p "$HOME/Library/Developer/Xcode/DerivedData/junk"
  make_stub pgrep 2            # rc 2 = probe error, not "no match"
  run bash "$SCRIPTS/clean-safe.sh"
  [[ "$output" == *"skipped (process state unknown"*"DerivedData"* ]] || false
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
  [[ "$output" == *"skipped (in use"* ]] || false
  [[ "$output" != *"would remove"*".gradle/caches"* ]]
}

@test "unknown argument fails closed (exit 2), no deletion (I4)" {
  mkdir -p "$HOME/.npm/junk"
  run bash "$SCRIPTS/clean-safe.sh" --dryrun
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument"* ]] || false
  [ -d "$HOME/.npm/junk" ]
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

@test "Handoff pasteboard: a blocked removal is reported/logged as skipped, not silently dropped" {
  # Portable failure simulation: dropping write permission on the PARENT dir
  # (not the item itself) makes rm -rf fail to unlink the child while `find`
  # can still list it (read+execute survive) — exercises the same failure
  # shape as a real TCC/App-Management block. Root bypasses permission checks
  # entirely, so this can't be forced portably there; skip rather than flake.
  [ "$(id -u)" -eq 0 ] && skip "cannot simulate a permission-denied rm as root"
  PB="$HOME/Library/Group Containers/group.com.apple.coreservices.useractivityd/shared-pasteboard"
  mkdir -p "$PB/stuck-item"
  touch -t "$(date -v-2H +%Y%m%d%H%M)" "$PB/stuck-item"
  chmod 555 "$PB"
  run bash "$SCRIPTS/clean-safe.sh"
  chmod 755 "$PB"   # restore so bats' teardown can rm -rf the fake HOME
  # `|| false` for the same bash-3.2 errexit-masking reason as the conda test
  # above: without it, the trailing `[ -d ]` (true regardless of whether the
  # skip message ever printed) would silently swallow a failed `[[ ]]`.
  [[ "$output" == *"skipped (protected or in use): $PB/stuck-item"* ]] || false
  [ -d "$PB/stuck-item" ]
  grep -q "skipped" "$HOME/Library/Logs/mac-storage-cleaner/operations.log"
}

@test "whitelisting one Handoff pasteboard item protects it while others still clear (I5)" {
  PB="$HOME/Library/Group Containers/group.com.apple.coreservices.useractivityd/shared-pasteboard"
  mkdir -p "$PB/old-item" "$PB/other-old-item"
  touch -t "$(date -v-2H +%Y%m%d%H%M)" "$PB/old-item" "$PB/other-old-item"
  printf '%s\n' "$PB/old-item" > "$MSC_WHITELIST_FILE"
  run bash "$SCRIPTS/clean-safe.sh"
  [[ "$output" == *"skipped (whitelisted): $PB/old-item"* ]] || false
  [ -d "$PB/old-item" ]
  [ ! -e "$PB/other-old-item" ]
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

@test "unlogged deletions are refused by default (exit 3), cache survives (F8)" {
  mkdir -p "$HOME/.npm/junk" "$HOME/Library"
  : > "$HOME/Library/Logs"   # a FILE where a dir is needed -> log_writable fails
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 3 ]
  [[ "$output" == *"Refusing to delete unlogged"* ]] || false
  [ -d "$HOME/.npm/junk" ]
}

@test "MSC_ALLOW_UNLOGGED=1 overrides the abort-if-unlogged refusal (F8)" {
  mkdir -p "$HOME/.npm/junk" "$HOME/Library"
  : > "$HOME/Library/Logs"
  MSC_ALLOW_UNLOGGED=1 run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"will NOT be recorded"* ]] || false
  [ ! -e "$HOME/.npm" ]
}
