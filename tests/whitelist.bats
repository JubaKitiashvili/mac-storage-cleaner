#!/usr/bin/env bats
load test_helper

setup ()    { setup_fake_home; }
teardown () { teardown_fake_home; }

write_wl () { printf '%s\n' "$@" > "$MSC_WHITELIST_FILE"; }

@test "whitelist protects exact entries, children, tilde and globs; comments ignored" {
  write_wl '# keep my gradle' '~/.gradle/caches' "$HOME/Library/Caches/pip" '~/Library/Caches/electron*'
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; load_whitelist
    is_whitelisted '$HOME/.gradle/caches'              && echo A
    is_whitelisted '$HOME/.gradle/caches/modules-2'    && echo B
    is_whitelisted '$HOME/Library/Caches/pip'          && echo C
    is_whitelisted '$HOME/Library/Caches/electron-builder' && echo D
    is_whitelisted '$HOME/.npm'                        || echo E"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'A\nB\nC\nD\nE')" ]
}

@test "missing whitelist file means nothing is protected" {
  rm -f "$MSC_WHITELIST_FILE"
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; load_whitelist; is_whitelisted '$HOME/.npm' || echo unprotected"
  [ "$output" = "unprotected" ]
}

@test "clean-safe skips a whitelisted cache and reports it" {
  mkdir -p "$HOME/.npm/junk" "$HOME/.cache/pip/junk"
  write_wl '~/.npm'
  make_stub brew 1; make_stub xcode-select 1
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped (whitelisted): $HOME/.npm"* ]] || false
  [ -d "$HOME/.npm/junk" ]          # untouched
  [ ! -e "$HOME/.cache/pip" ]       # non-whitelisted still cleaned
}

@test "trailing slash on a whitelist entry still protects itself and its children" {
  write_wl '~/.npm/'
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; load_whitelist
    is_whitelisted '$HOME/.npm'       && echo A
    is_whitelisted '$HOME/.npm/junk' && echo B"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'A\nB')" ]
}

@test "a whitelist file of only slash lines protects nothing and does not crash" {
  write_wl '/' '//'
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; load_whitelist
    is_whitelisted '$HOME/.npm' || echo unprotected
    is_whitelisted '/'          || echo root-unprotected"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'unprotected\nroot-unprotected')" ]
}

@test "whitelist matching is case-insensitive, like APFS default volumes (F6)" {
  write_wl '~/Library/Caches/Pip' '~/Library/Caches/Electron*'
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; load_whitelist
    is_whitelisted '$HOME/library/caches/pip'             && echo A
    is_whitelisted '$HOME/Library/Caches/pip'              && echo B
    is_whitelisted '$HOME/Library/Caches/electron-builder' && echo C
    is_whitelisted '$HOME/LIBRARY/CACHES/ELECTRON-BUILDER' && echo D"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'A\nB\nC\nD')" ]
}

@test "whitelist '#' handling: literal # in a path survives; trailing/full-line comments still parse (F7)" {
  mkdir -p "$HOME/Downloads"
  write_wl '~/Downloads/report#2' '~/.npm  # keep this' '# full line comment'
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; load_whitelist
    is_whitelisted '$HOME/Downloads/report#2' && echo A
    is_whitelisted '$HOME/.npm'                && echo B
    [ \"\${#WHITELIST[@]}\" -eq 2 ]             && echo C"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'A\nB\nC')" ]
}

@test "survey excludes whitelisted safe-tier caches from the reclaimable total (F11)" {
  mkdir -p "$HOME/.npm/junk" "$HOME/.cache/pip/junk"
  dd if=/dev/zero of="$HOME/.npm/junk/blob" bs=1024 count=100 2>/dev/null
  dd if=/dev/zero of="$HOME/.cache/pip/junk/blob" bs=1024 count=50 2>/dev/null
  write_wl '~/.npm'
  run bash "$SCRIPTS/survey.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.npm (whitelisted — excluded from total)"* ]] || false
  pip_total=$(du -sh "$HOME/.cache/pip" 2>/dev/null | awk '{print $1}')
  [[ "$output" == *"reclaimable in safe tier: $pip_total"* ]] || false
}
