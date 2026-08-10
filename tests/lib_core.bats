#!/usr/bin/env bats
load test_helper

setup ()    { setup_fake_home; }
teardown () { teardown_fake_home; }

@test "lib.sh sources cleanly under set -u with a bare fake HOME" {
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; echo OK"
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]]
}

@test "collect returns empty FOUND on a machine with no caches" {
  # SAFE_PATHS includes a few absolute globs against the real shared
  # /private/tmp (metro-*, haste-map-*, ...) that the fake-HOME sandbox
  # cannot isolate — if Metro/RN happens to be running on the host, those
  # would legitimately populate FOUND and make a raw "${#FOUND[@]}" == 0
  # assertion flake. Restrict the assertion to entries under the fake
  # $HOME, which setup_fake_home guarantees is cache-free, while still
  # exercising collect over the full SAFE_PATHS array.
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; collect \"\${SAFE_PATHS[@]}\"; if [ \"\${#FOUND[@]}\" -gt 0 ]; then for f in \"\${FOUND[@]}\"; do case \"\$f\" in \"\$HOME\"/*) echo \"\$f\" ;; esac; done; fi"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "clean-safe.sh runs to completion on an empty fake HOME" {
  make_stub brew 1
  make_stub xcode-select 1
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Approx. reclaimed"* ]]
}
