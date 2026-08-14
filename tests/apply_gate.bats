#!/usr/bin/env bats
load test_helper

setup () {
  setup_fake_home
  # brew/xcode-select/pgrep match the existing suite's stubs; conda and ps are
  # additional here because this file is the first to run clean-safe.sh with
  # --apply, which reaches the tool-native section — an unstubbed `conda` would
  # run the developer's real `conda clean`.
  make_stub brew 1
  make_stub xcode-select 1
  make_stub pgrep 1
  make_stub conda 1
  make_stub ps 1
  mkdir -p "$HOME/.npm/junk"
}
teardown () { teardown_fake_home; }

@test "no argument previews and deletes nothing" {
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PREVIEW"* ]] || false
  [[ "$output" == *"would remove"* ]] || false
  [ -d "$HOME/.npm/junk" ] || { echo "no-arg run deleted files"; false; }
  [ ! -e "$HOME/Library/Logs/mac-storage-cleaner/operations.log" ] || false
}

@test "--apply deletes and records the consent mode" {
  run bash "$SCRIPTS/clean-safe.sh" --apply
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.npm" ] || { echo "--apply did not delete"; false; }
  grep -q "consent" "$HOME/Library/Logs/mac-storage-cleaner/operations.log"
  grep -q "removed" "$HOME/Library/Logs/mac-storage-cleaner/operations.log"
}

@test "--dry-run still previews (back-compat alias)" {
  run bash "$SCRIPTS/clean-safe.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"PREVIEW"* ]] || false
  [ -d "$HOME/.npm/junk" ] || false
}

@test "MSC_DRY_RUN=1 overrides --apply — the env var can only make a run safer" {
  MSC_DRY_RUN=1 run bash "$SCRIPTS/clean-safe.sh" --apply
  [ "$status" -eq 0 ]
  [ -d "$HOME/.npm/junk" ] || { echo "MSC_DRY_RUN=1 did not override --apply"; false; }
}

@test "an unknown argument still exits 2 and deletes nothing" {
  run bash "$SCRIPTS/clean-safe.sh" --aply
  [ "$status" -eq 2 ]
  [ -d "$HOME/.npm/junk" ] || false
}

@test "--apply --dry-run (extra argument) exits 2 and deletes nothing, instead of applying (M10)" {
  run bash "$SCRIPTS/clean-safe.sh" --apply --dry-run
  [ "$status" -eq 2 ]
  [ -d "$HOME/.npm/junk" ] || { echo "extra-argument invocation deleted files"; false; }
  [ ! -e "$HOME/Library/Logs/mac-storage-cleaner/operations.log" ] || false
}

@test "the preview summary tells the user how to actually apply" {
  run bash "$SCRIPTS/clean-safe.sh"
  [[ "$output" == *"--apply"* ]] || false
}
