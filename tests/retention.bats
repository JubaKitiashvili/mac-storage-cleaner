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

mk_claude () {
  VR="$HOME/.local/share/claude/versions"
  mkdir -p "$VR/1.0.10" "$VR/1.0.11" "$VR/1.0.12" "$HOME/.local/bin"
  touch -t "$(date -v-3d +%Y%m%d%H%M)" "$VR/1.0.10"
  touch -t "$(date -v-2d +%Y%m%d%H%M)" "$VR/1.0.11"
  touch -t "$(date -v-1d +%Y%m%d%H%M)" "$VR/1.0.12"
}

@test "resolve_active_version_dir follows the launcher symlink" {
  mk_claude
  ln -s "$VR/1.0.11/bin/claude" "$HOME/.local/bin/claude"
  mkdir -p "$VR/1.0.11/bin"
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; resolve_active_version_dir \"$VR\" \"$HOME/.local/bin/claude\""
  [ "$status" -eq 0 ]
  [ "$output" = "1.0.11" ]
}

@test "clean-safe keeps active (via symlink) + 1 newest other; removes the rest" {
  mk_claude
  mkdir -p "$VR/1.0.11/bin"
  ln -s "$VR/1.0.11/bin/claude" "$HOME/.local/bin/claude"
  run bash "$SCRIPTS/clean-safe.sh"
  [ -d "$VR/1.0.11" ]      # active — even though not newest
  [ -d "$VR/1.0.12" ]      # 1 newest non-active kept
  [ ! -e "$VR/1.0.10" ]    # removed
}

@test "broken active symlink fails closed: agent versions untouched" {
  mk_claude
  ln -s "$VR/9.9.9/bin/claude" "$HOME/.local/bin/claude"   # dangling
  run bash "$SCRIPTS/clean-safe.sh"
  [ -d "$VR/1.0.10" ]; [ -d "$VR/1.0.11" ]; [ -d "$VR/1.0.12" ]
  [[ "$output" == *"skipped (active version unknown): Claude Code"* ]]
}

@test "missing symlink fails closed too" {
  mk_claude
  run bash "$SCRIPTS/clean-safe.sh"
  [ -d "$VR/1.0.10" ]
}
