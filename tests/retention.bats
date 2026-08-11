#!/usr/bin/env bats
load test_helper

setup ()    { setup_fake_home; make_stub brew 1; make_stub xcode-select 1; make_stub pgrep 1; }
teardown () { teardown_fake_home; }

mk_ds () {   # four version dirs. mtimes are DELIBERATELY inverted from
  # version order (G2): "16.0" — the LOWEST version — gets the NEWEST mtime
  # (1 hour ago), while "18.5" — the HIGHEST version — has an OLD mtime (1
  # day ago). Retention must still keep the 2 HIGHEST VERSIONS (17.5, 18.5)
  # and remove the 2 lowest (16.0, 17.0), proving version-ordering beats
  # mtime — a naive mtime-based scan would instead keep 16.0 (newest mtime)
  # and 18.5, removing 17.0 and 17.5, which the assertions below would catch.
  DS="$HOME/Library/Developer/Xcode/iOS DeviceSupport"
  mkdir -p "$DS/16.0 (20A362)" "$DS/17.0 (21A326)" "$DS/17.5 (21F79)" "$DS/18.5 (22F76)"
  touch -t "$(date -v-1H +%Y%m%d%H%M)" "$DS/16.0 (20A362)"
  touch -t "$(date -v-3d +%Y%m%d%H%M)" "$DS/17.0 (21A326)"
  touch -t "$(date -v-2d +%Y%m%d%H%M)" "$DS/17.5 (21F79)"
  touch -t "$(date -v-1d +%Y%m%d%H%M)" "$DS/18.5 (22F76)"
}

@test "keep_newest_n_children lists everything beyond the N newest" {
  mk_ds
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; keep_newest_n_children \"$DS\" 2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"16.0 (20A362)"* ]] || false
  [[ "$output" == *"17.0 (21A326)"* ]] || false
  [[ "$output" != *"18.5"* ]] || false
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
  [[ "$output" == *"would remove"*"18.5 (22F76)"* ]] || false
  [ -d "$DS/18.5 (22F76)" ]
}

@test "whitelisting one DeviceSupport version dir protects it while keep-N still applies to the rest (I5)" {
  mk_ds
  printf '%s\n' "$DS/16.0 (20A362)" > "$MSC_WHITELIST_FILE"
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped (whitelisted): $DS/16.0 (20A362)"* ]] || false
  [ -d "$DS/16.0 (20A362)" ]      # whitelisted old version survives
  [ ! -e "$DS/17.0 (21A326)" ]   # other old version still removed
  [ -d "$DS/17.5 (21F79)" ]      # kept (2 newest)
  [ -d "$DS/18.5 (22F76)" ]      # kept (2 newest)
}

@test "stray non-directory child does not consume a DeviceSupport keep-N slot (I6)" {
  # NOTE: a literal ".DS_Store" would NOT reproduce this — `ls -1t` (no -a)
  # hides dotfiles by default, so it never reaches keep_newest_n_children's
  # candidate stream regardless of the dir-only fix below. Use a non-hidden
  # stray file (Xcode/Finder can drop plenty of these) to actually exercise
  # the code path the fix protects.
  mk_ds
  touch -t "$(date -v-1H +%Y%m%d%H%M)" "$DS/leftover.plist"   # newer mtime than all 4 version dirs
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [ -d "$DS/18.5 (22F76)" ]        # 2 newest real dirs still kept
  [ -d "$DS/17.5 (21F79)" ]
  [ ! -e "$DS/16.0 (20A362)" ]     # 2 oldest still removed
  [ ! -e "$DS/17.0 (21A326)" ]
  [ -e "$DS/leftover.plist" ]      # stray file never touched (not counted, not deleted)
}

@test "partial removal is reported honestly when part of a to-delete DeviceSupport version can't be removed (F9)" {
  # NOTE: this exercises the keep-N per-child loop rather than the safe-tier
  # FOUND loop — the safe-tier loop retries rm after `chmod -R u+w`, which
  # would restore write access to a chmod-555 fixture and undo a "partial"
  # scenario before the honesty check ever gets to see it. The keep-N loop
  # shares the identical partial-detection code path with no such retry, so
  # it's a reliable place to exercise it.
  [ "$(id -u)" -eq 0 ] && skip "cannot simulate a permission-denied rm as root"
  DS="$HOME/Library/Developer/Xcode/iOS DeviceSupport"
  mkdir -p "$DS/16.0 (oldest)" "$DS/17.0 (mid)" "$DS/18.0 (newest)"
  mkdir -p "$DS/16.0 (oldest)/protected"
  dd if=/dev/zero of="$DS/16.0 (oldest)/removable-file" bs=1024 count=200 2>/dev/null
  dd if=/dev/zero of="$DS/16.0 (oldest)/protected/blob" bs=1024 count=50 2>/dev/null
  chmod 555 "$DS/16.0 (oldest)/protected"
  # Set mtimes LAST: the mkdir/dd calls above bump "16.0 (oldest)"'s own
  # mtime as a side effect of adding directory entries, so touching it
  # earlier (before its content exists) would get silently overwritten.
  touch -t "$(date -v-3d +%Y%m%d%H%M)" "$DS/16.0 (oldest)"
  touch -t "$(date -v-2d +%Y%m%d%H%M)" "$DS/17.0 (mid)"
  touch -t "$(date -v-1d +%Y%m%d%H%M)" "$DS/18.0 (newest)"
  run bash "$SCRIPTS/clean-safe.sh"
  chmod 755 "$DS/16.0 (oldest)/protected"   # restore before teardown rm -rf
  [ "$status" -eq 0 ]
  [[ "$output" == *"partially removed"* ]] || false
  grep -q "$(printf '\tpartial\t')" "$HOME/Library/Logs/mac-storage-cleaner/operations.log"
  [ -d "$DS/16.0 (oldest)/protected" ]        # blocked content survives
  [ ! -e "$DS/16.0 (oldest)/removable-file" ] # unblocked content still freed
  [ -d "$DS/17.0 (mid)" ]; [ -d "$DS/18.0 (newest)" ]   # 2 newest still kept
}

# C1: [ -d "$base" ] alone FOLLOWS a symlink, so a symlinked retention root
# must be refused explicitly — otherwise the loop would enumerate and delete
# the TARGET's version children right through the link.
@test "symlinked DeviceSupport base is skipped entirely — nothing under the target is touched (C1)" {
  REAL="$HOME/real-device-support"
  mkdir -p "$REAL/16.0 (20A362)" "$REAL/17.0 (21A326)" "$REAL/17.5 (21F79)" "$REAL/18.5 (22F76)"
  DS="$HOME/Library/Developer/Xcode/iOS DeviceSupport"
  mkdir -p "$(dirname "$DS")"
  ln -s "$REAL" "$DS"
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped (symlink base)"* ]] || false
  [ -d "$REAL/16.0 (20A362)" ]
  [ -d "$REAL/17.0 (21A326)" ]
  [ -d "$REAL/17.5 (21F79)" ]
  [ -d "$REAL/18.5 (22F76)" ]
  [ -L "$DS" ]
}

@test "survey shows the actual MSC_DEVICE_SUPPORT_KEEP value, not a hardcoded 2 (preview == reality)" {
  mk_ds
  MSC_DEVICE_SUPPORT_KEEP=5 run bash "$SCRIPTS/survey.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(keeps 5 newest versions)"* ]] || false
  [[ "$output" != *"(keeps 2 newest versions)"* ]] || false

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

@test "stray non-directory child does not consume an AI-agent keep slot (I6)" {
  # Same note as the DeviceSupport I6 test: a literal ".DS_Store" is hidden
  # from `ls -1t` by default and would never reach this loop either way —
  # use a non-hidden stray file to actually exercise the fix.
  mk_claude
  mkdir -p "$VR/1.0.11/bin"
  ln -s "$VR/1.0.11/bin/claude" "$HOME/.local/bin/claude"
  touch -t "$(date -v-1H +%Y%m%d%H%M)" "$VR/leftover.plist"   # newer mtime, but not a version dir
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [ -d "$VR/1.0.11" ]      # active
  [ -d "$VR/1.0.12" ]      # 1 newest non-active kept — must survive even though
                            # a naive scan would have "spent" that slot on leftover.plist
  [ ! -e "$VR/1.0.10" ]    # removed
  [ -e "$VR/leftover.plist" ]   # stray file never touched
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
