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

# C2: the -mmin +60 top-level age gate only looks at the CANDIDATE dir's own
# mtime — a directory's mtime doesn't necessarily bump every time a file
# inside it is written, so an old-looking dir can still be mid-transfer.
@test "Handoff pasteboard: a dir with an old dir-mtime but one fresh file inside survives (content-aware age gate, C2)" {
  PB="$HOME/Library/Group Containers/group.com.apple.coreservices.useractivityd/shared-pasteboard"
  mkdir -p "$PB/mixed-item"
  touch "$PB/mixed-item/fresh-file"    # default mtime: just now (< 60min)
  touch -t "$(date -v-2H +%Y%m%d%H%M)" "$PB/mixed-item"   # dir itself looks old
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [ -d "$PB/mixed-item" ]
  [ -e "$PB/mixed-item/fresh-file" ]
}

@test "Handoff pasteboard: a fully-old dir (no fresh descendants) is still removed (C2 regression)" {
  PB="$HOME/Library/Group Containers/group.com.apple.coreservices.useractivityd/shared-pasteboard"
  mkdir -p "$PB/fully-old-item"
  touch -t "$(date -v-2H +%Y%m%d%H%M)" "$PB/fully-old-item/inner-file"
  touch -t "$(date -v-2H +%Y%m%d%H%M)" "$PB/fully-old-item"
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$PB/fully-old-item" ]
}

@test "Handoff pasteboard: an unreadable descendant makes the freshness scan fail closed — buffer survives (R3)" {
  # An unreadable subdir makes `find`'s traversal fail (rc<>0) without
  # necessarily finding a fresh file — that's an inconclusive scan, not
  # proof of idleness, so the candidate must be skipped just like an
  # actually-fresh descendant would skip it.
  PB="$HOME/Library/Group Containers/group.com.apple.coreservices.useractivityd/shared-pasteboard"
  mkdir -p "$PB/locked-item/unreadable-sub"
  touch -t "$(date -v-2H +%Y%m%d%H%M)" "$PB/locked-item/unreadable-sub" "$PB/locked-item"
  chmod 000 "$PB/locked-item/unreadable-sub"
  run bash "$SCRIPTS/clean-safe.sh"
  chmod 755 "$PB/locked-item/unreadable-sub"   # restore before teardown rm -rf
  [ "$status" -eq 0 ]
  [ -d "$PB/locked-item" ]
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

@test "wave-2 safe paths: android cache and pypoetry cache are cleared (A1)" {
  mkdir -p "$HOME/.android/cache/x" "$HOME/Library/Caches/pypoetry/x"
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.android/cache" ]
  [ ! -e "$HOME/Library/Caches/pypoetry" ]
}

@test "DiagnosticReports: crash reports older than 30 days are removed, fresh ones survive; dry-run previews only (A3)" {
  DR="$HOME/Library/Logs/DiagnosticReports"
  mkdir -p "$DR"
  touch "$DR/fresh.crash"
  touch -t "$(date -v-40d +%Y%m%d%H%M)" "$DR/old.crash"

  run bash "$SCRIPTS/clean-safe.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would remove"*"old.crash"*"crash report >30d"* ]] || false
  [ -e "$DR/old.crash" ]
  [ -e "$DR/fresh.crash" ]

  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$DR/old.crash" ]
  [ -e "$DR/fresh.crash" ]
}

@test "DiagnosticReports: only report artifacts are swept — an old non-report file/dir survives (R4)" {
  DR="$HOME/Library/Logs/DiagnosticReports"
  mkdir -p "$DR" "$DR/notes"
  touch "$DR/foo.ips"
  touch "$DR/README.txt"
  touch -t "$(date -v-40d +%Y%m%d%H%M)" "$DR/foo.ips" "$DR/README.txt" "$DR/notes"
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$DR/foo.ips" ]     # a real report artifact, old — removed
  [ -e "$DR/README.txt" ]   # not a report artifact — survives even though old
  [ -d "$DR/notes" ]        # not "Retired" — survives even though old
}

@test "DiagnosticReports/Retired: old report inside is removed, the Retired dir itself survives" {
  DR="$HOME/Library/Logs/DiagnosticReports"
  mkdir -p "$DR/Retired"
  touch "$DR/Retired/old.crash"
  touch -t "$(date -v-40d +%Y%m%d%H%M)" "$DR/Retired/old.crash"
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed"*"old.crash"*"crash report >30d"* ]] || false
  [ ! -e "$DR/Retired/old.crash" ]
  [ -d "$DR/Retired" ]        # the Retired dir itself is never rm -rf'd
}

@test "DiagnosticReports/Retired: a fresh report inside survives even when Retired itself is old" {
  DR="$HOME/Library/Logs/DiagnosticReports"
  mkdir -p "$DR/Retired"
  touch "$DR/Retired/fresh.crash"          # mtime now
  touch -t "$(date -v-40d +%Y%m%d%H%M)" "$DR/Retired"   # dir's own mtime is old
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [ -e "$DR/Retired/fresh.crash" ]         # child mtime, not the dir's, governs
  [ -d "$DR/Retired" ]
}

@test "DiagnosticReports/Retired: a whitelisted child survives and is reported skipped" {
  DR="$HOME/Library/Logs/DiagnosticReports"
  mkdir -p "$DR/Retired"
  touch "$DR/Retired/keep.crash"
  touch -t "$(date -v-40d +%Y%m%d%H%M)" "$DR/Retired/keep.crash"
  printf '%s\n' "$DR/Retired/keep.crash" > "$MSC_WHITELIST_FILE"
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped (whitelisted): $DR/Retired/keep.crash"* ]] || false
  [ -e "$DR/Retired/keep.crash" ]
  [ -d "$DR/Retired" ]
}

@test "deferred-skip rollup summarizes in-use and whitelisted skips (A5)" {
  mkdir -p "$HOME/.npm/junk" "$HOME/.gradle/caches/junk"
  printf '~/.npm\n' > "$MSC_WHITELIST_FILE"
  make_stub pgrep 0   # gradle daemon "running" -> in-use skip
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipped:"* ]] || false
  [[ "$output" == *"1 in-use"* ]] || false
  [[ "$output" == *"1 whitelisted"* ]] || false
}
