#!/usr/bin/env bats
load test_helper

setup ()    { setup_fake_home; make_stub osascript 1; mkdir -p "$HOME/junk"; }
teardown () { teardown_fake_home; }

@test "a batch over the item cap is refused with exit 4 and moves nothing" {
  local i paths=()
  for i in $(seq 1 101); do
    : > "$HOME/junk/f$i"
    paths+=("$HOME/junk/f$i")
  done
  run bash "$SCRIPTS/trash-items.sh" "${paths[@]}"
  [ "$status" -eq 4 ]
  [[ "$output" == *"Refusing a bulk operation"* ]] || false
  [[ "$output" == *"--force"* ]] || false
  [ -f "$HOME/junk/f1" ] || { echo "items were trashed despite the refusal"; false; }
  grep -q "refused-blast-radius" "$HOME/Library/Logs/mac-storage-cleaner/operations.log"
}

@test "--force proceeds past the item cap" {
  local i paths=()
  for i in $(seq 1 101); do
    : > "$HOME/junk/f$i"
    paths+=("$HOME/junk/f$i")
  done
  run bash "$SCRIPTS/trash-items.sh" --force "${paths[@]}"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/junk/f1" ] || { echo "--force did not trash"; false; }
}

@test "--force logs a consent marker (I6)" {
  : > "$HOME/junk/one"
  run bash "$SCRIPTS/trash-items.sh" --force "$HOME/junk/one"
  [ "$status" -eq 0 ]
  grep -qE $'consent\t-\t--force' "$HOME/Library/Logs/mac-storage-cleaner/operations.log"
}

@test "a normal (non --force) run logs no consent marker (I6)" {
  : > "$HOME/junk/two"
  run bash "$SCRIPTS/trash-items.sh" "$HOME/junk/two"
  [ "$status" -eq 0 ]
  ! grep -qE $'consent\t-\t--force' "$HOME/Library/Logs/mac-storage-cleaner/operations.log"
}

@test "--force --dry-run does not log a consent marker (preview only) (I6)" {
  : > "$HOME/junk/one"
  run bash "$SCRIPTS/trash-items.sh" --force --dry-run "$HOME/junk/one"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/Library/Logs/mac-storage-cleaner/operations.log" ]
}

@test "a batch under both caps is unaffected" {
  : > "$HOME/junk/one"
  run bash "$SCRIPTS/trash-items.sh" "$HOME/junk/one"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/junk/one" ] || false
}

@test "the size cap refuses a batch that is small in count but large on disk" {
  mkdir -p "$HOME/big"
  # 6 GB apparent size via a sparse file — du -sk reports the allocated blocks,
  # so write a real 6 MB and lower the cap instead of burning disk.
  dd if=/dev/zero of="$HOME/big/blob" bs=1m count=6 2>/dev/null
  MSC_MAX_TRASH_GB=0 run bash "$SCRIPTS/trash-items.sh" "$HOME/big/blob"
  [ "$status" -eq 4 ]
  [[ "$output" == *"Refusing a bulk operation"* ]] || false
  [ -f "$HOME/big/blob" ] || false
}

@test "protected and missing paths do not count toward the cap" {
  local i paths=()
  # $HOME/Library must EXIST for validate_target_path to be the thing that
  # rejects it — setup_fake_home creates only .Trash and .config, and a
  # non-existent path is skipped as "missing" long before validation runs,
  # which would make this test prove nothing about protected paths.
  mkdir -p "$HOME/Library"
  for i in $(seq 1 99); do
    : > "$HOME/junk/g$i"
    paths+=("$HOME/junk/g$i")
  done
  # 99 eligible + one refused root + one missing path = under the cap of 100.
  run bash "$SCRIPTS/trash-items.sh" "${paths[@]}" "$HOME/Library" "$HOME/nope"
  [ "$status" -ne 4 ] || { echo "ineligible paths were counted toward the cap"; false; }
  [[ "$output" == *"REFUSED"* ]] || { echo "the protected root was not refused"; false; }
  [[ "$output" == *"not found"* ]] || { echo "the missing path was not reported"; false; }
}

@test "a preview is never refused by the cap — the user must be able to review" {
  local i paths=()
  for i in $(seq 1 101); do
    : > "$HOME/junk/h$i"
    paths+=("$HOME/junk/h$i")
  done
  MSC_DRY_RUN=1 run bash "$SCRIPTS/trash-items.sh" "${paths[@]}"
  [ "$status" -eq 0 ] || { echo "preview was refused with status $status"; false; }
  [[ "$output" == *"would trash"* ]] || false
  [ -f "$HOME/junk/h1" ] || false
}

@test "an unreadable path makes the size guard skip with an honest warning, not a fake zero" {
  mkdir -p "$HOME/blocked"
  : > "$HOME/blocked/secret"
  chmod 000 "$HOME/blocked"
  run bash "$SCRIPTS/trash-items.sh" "$HOME/blocked"
  # Restore permissions before teardown regardless of where the item ended up
  # (trashed into $HOME/.Trash, or left in place) — otherwise fake-HOME
  # cleanup (rm -rf) cannot descend into the still-000 directory.
  chmod -R 755 "$HOME/blocked" 2>/dev/null
  chmod -R 755 "$HOME/.Trash" 2>/dev/null
  [ "$status" -ne 4 ] || { echo "an unreadable path was refused instead of warned about: $output"; false; }
  [[ "$output" == *"NOT enforced"* ]] || { echo "no honest unmeasurable-size warning was printed: $output"; false; }
  grep -q "size-unmeasurable" "$HOME/Library/Logs/mac-storage-cleaner/operations.log"
}

@test "a refused over-item-cap batch with an unmeasurable size reports size?, not a fake 0.0K (M9)" {
  mkdir -p "$HOME/junk/blocked"
  : > "$HOME/junk/blocked/secret"
  chmod 000 "$HOME/junk/blocked"
  local i paths=("$HOME/junk/blocked")
  for i in $(seq 1 100); do
    : > "$HOME/junk/m$i"
    paths+=("$HOME/junk/m$i")
  done
  run bash "$SCRIPTS/trash-items.sh" "${paths[@]}"
  chmod -R 755 "$HOME/junk/blocked" 2>/dev/null
  [ "$status" -eq 4 ]
  [[ "$output" == *"Refusing a bulk operation"* ]] || false
  [[ "$output" == *"Refusing a bulk operation: 101 item(s), size?"* ]] || { echo "$output"; false; }
  [[ "$output" != *"0.0K"* ]] || { echo "printed a fake 0.0K instead of size?"; false; }
}

@test "a measurable over-limit batch still exits 4 (the unmeasurable-size flag must not short-circuit a real refusal)" {
  mkdir -p "$HOME/big2"
  dd if=/dev/zero of="$HOME/big2/blob" bs=1m count=6 2>/dev/null
  MSC_MAX_TRASH_GB=0 run bash "$SCRIPTS/trash-items.sh" "$HOME/big2/blob"
  [ "$status" -eq 4 ]
  [[ "$output" == *"Refusing a bulk operation"* ]] || false
  [ -f "$HOME/big2/blob" ] || false
}
