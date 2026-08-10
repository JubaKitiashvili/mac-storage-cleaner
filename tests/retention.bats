#!/usr/bin/env bats
load test_helper

setup ()    { setup_fake_home; make_stub brew 1; make_stub xcode-select 1; make_stub pgrep 1; }
teardown () { teardown_fake_home; }

mk_ds () {   # four version dirs, mtimes 4d..1d old; "18.5 (22F76)" newest
  DS="$HOME/Library/Developer/Xcode/iOS DeviceSupport"
  mkdir -p "$DS/16.0 (20A362)" "$DS/17.0 (21A326)" "$DS/17.5 (21F79)" "$DS/18.5 (22F76)"
  touch -t "$(date -v-4d +%Y%m%d%H%M)" "$DS/16.0 (20A362)"
  touch -t "$(date -v-3d +%Y%m%d%H%M)" "$DS/17.0 (21A326)"
  touch -t "$(date -v-2d +%Y%m%d%H%M)" "$DS/17.5 (21F79)"
  touch -t "$(date -v-1d +%Y%m%d%H%M)" "$DS/18.5 (22F76)"
}

@test "keep_newest_n_children lists everything beyond the N newest" {
  mk_ds
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; keep_newest_n_children \"$DS\" 2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"16.0 (20A362)"* ]]
  [[ "$output" == *"17.0 (21A326)"* ]]
  [[ "$output" != *"18.5"* ]]
  [[ "$output" != *"17.5"* ]]
}

@test "clean-safe keeps the 2 newest DeviceSupport versions, removes the rest" {
  mk_ds
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [ -d "$DS/18.5 (22F76)" ]
  [ -d "$DS/17.5 (21F79)" ]
  [ ! -e "$DS/16.0 (20A362)" ]
  [ ! -e "$DS/17.0 (21A326)" ]
  [[ "$output" == *"kept 2 newest"* ]]
}

@test "MSC_DEVICE_SUPPORT_KEEP=0 clears all versions; dry-run previews only" {
  mk_ds
  MSC_DEVICE_SUPPORT_KEEP=0 run bash "$SCRIPTS/clean-safe.sh" --dry-run
  [[ "$output" == *"would remove"*"18.5 (22F76)"* ]]
  [ -d "$DS/18.5 (22F76)" ]
}

@test "survey shows the actual MSC_DEVICE_SUPPORT_KEEP value, not a hardcoded 2 (preview == reality)" {
  mk_ds
  MSC_DEVICE_SUPPORT_KEEP=5 run bash "$SCRIPTS/survey.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(keeps 5 newest versions)"* ]]
  [[ "$output" != *"(keeps 2 newest versions)"* ]]

  run bash "$SCRIPTS/survey.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(keeps 2 newest versions)"* ]]
}
