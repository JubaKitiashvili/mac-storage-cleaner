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
  [[ "$output" == *"skipped (whitelisted): $HOME/.npm"* ]]
  [ -d "$HOME/.npm/junk" ]          # untouched
  [ ! -e "$HOME/.cache/pip" ]       # non-whitelisted still cleaned
}
