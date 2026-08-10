#!/bin/bash
# mac-storage-cleaner CLEAN — removes ONLY the vetted safe tier (pure caches).
# Never touches the ask/never tiers, browser/app data, models, VMs, or backups.
# Handles read-only files (chmod) and reports anything blocked by macOS App
# Management/TCC instead of failing. Run survey.sh first and show the user.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"
load_whitelist

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1
[ "${MSC_DRY_RUN:-0}" = "1" ] && DRY=1
export MSC_DRY_RUN="$DRY"
[ "$DRY" = 1 ] && echo "=== DRY RUN — nothing will be deleted ==="

total_kb=0
skipped=0
[ "$DRY" = 1 ] || log_writable || echo "⚠ Cannot write the audit log ($LOG_DIR/operations.log) — cleanup will proceed, but this run will NOT be recorded."
echo "Clearing safe caches (pure caches only)..."
collect "${SAFE_PATHS[@]}"
# bash 3.2 (macOS default) throws "unbound variable" on "${FOUND[@]}" when the
# array is empty under `set -u` — which happens on a fresh Mac with no dev
# caches. Guard the loop so a clean machine reports "nothing to do" instead of crashing.
[ "${#FOUND[@]}" -gt 0 ] && for p in "${FOUND[@]}"; do
  if is_whitelisted "$p"; then
    echo "  skipped (whitelisted): $p"
    log_op skipped-whitelisted "-" "$p"
    skipped=$((skipped + 1))
    continue
  fi
  if reason=$(guard_reason_for_path "$p"); then
    echo "  skipped ($reason): $p"
    log_op skipped-in-use "-" "$p"
    skipped=$((skipped + 1))
    continue
  fi
  kb=$(size_kb "$p")
  if [ "$DRY" = 1 ]; then
    echo "  would remove $(human_kb "${kb:-0}")  $p"
    total_kb=$((total_kb + ${kb:-0}))
    continue
  fi
  if ! rm -rf "$p" 2>/dev/null; then
    chmod -R u+w "$p" 2>/dev/null   # read-only files (e.g. Go/SwiftPM caches)
    rm -rf "$p" 2>/dev/null
  fi
  if [ -e "$p" ]; then
    echo "  skipped (macOS App Management/TCC-protected or in use): $p"
    log_op skipped "$(human_kb "${kb:-0}")" "$p"
    skipped=$((skipped + 1))
  else
    echo "  removed $(human_kb "${kb:-0}")  $p"
    log_op removed "$(human_kb "${kb:-0}")" "$p"
    total_kb=$((total_kb + ${kb:-0}))
  fi
done

# Keep-N retention: DeviceSupport regenerates per-version on device connect, so
# keep the newest MSC_DEVICE_SUPPORT_KEEP (default 2) and clear older versions.
KEEPN="${MSC_DEVICE_SUPPORT_KEEP:-2}"
case "$KEEPN" in ''|*[!0-9]*) KEEPN=2 ;; esac
for base in "${KEEP_N_PATHS[@]}"; do
  [ -d "$base" ] || continue
  if is_whitelisted "$base"; then
    echo "  skipped (whitelisted): $base"; log_op skipped-whitelisted "-" "$base"; skipped=$((skipped+1)); continue
  fi
  if reason=$(guard_reason_for_path "$base"); then
    echo "  skipped ($reason): $base"; log_op skipped-in-use "-" "$base"; skipped=$((skipped+1)); continue
  fi
  removed_any=0
  while IFS= read -r child; do
    # Empty child would collapse "$base/$child" to $base itself — never delete that.
    [ -n "$child" ] || continue
    p="$base/$child"
    [ -e "$p" ] || continue
    kb=$(size_kb "$p")
    if [ "$DRY" = 1 ]; then
      echo "  would remove $(human_kb "${kb:-0}")  $p"
      total_kb=$((total_kb + ${kb:-0})); removed_any=1; continue
    fi
    rm -rf "$p" 2>/dev/null
    if [ -e "$p" ]; then
      echo "  skipped (protected or in use): $p"; log_op skipped "$(human_kb "${kb:-0}")" "$p"; skipped=$((skipped+1))
    else
      echo "  removed $(human_kb "${kb:-0}")  $p"; log_op removed "$(human_kb "${kb:-0}")" "$p"
      total_kb=$((total_kb + ${kb:-0})); removed_any=1
    fi
  done <<EOF
$(keep_newest_n_children "$base" "$KEEPN")
EOF
  [ "$removed_any" = 1 ] && echo "  (kept $KEEPN newest in $(basename "$base"))"
done

# AI CLI old versions: keep the active one (symlink-pinned) + N newest others.
AIKEEP="${MSC_AI_AGENTS_KEEP:-1}"
case "$AIKEEP" in ''|*[!0-9]*) AIKEEP=1 ;; esac
for spec in "${AI_AGENT_SPECS[@]}"; do
  root="${spec%%|*}"; rest="${spec#*|}"; label="${rest%%|*}"; link="${rest#*|}"
  [ -d "$root" ] || continue
  if is_whitelisted "$root"; then
    echo "  skipped (whitelisted): $root"; log_op skipped-whitelisted "-" "$root"; skipped=$((skipped+1)); continue
  fi
  if ! active=$(resolve_active_version_dir "$root" "$link"); then
    echo "  skipped (active version unknown): $label"
    continue
  fi
  kept_others=0
  while IFS= read -r child; do
    [ -n "$child" ] || continue
    [ "$child" = "$active" ] && continue
    if [ "$kept_others" -lt "$AIKEEP" ]; then kept_others=$((kept_others+1)); continue; fi
    p="$root/$child"
    [ -e "$p" ] || continue
    kb=$(size_kb "$p")
    if [ "$DRY" = 1 ]; then
      echo "  would remove $(human_kb "${kb:-0}")  $p ($label old version)"
      total_kb=$((total_kb + ${kb:-0})); continue
    fi
    rm -rf "$p" 2>/dev/null
    if [ -e "$p" ]; then
      echo "  skipped: $p"; log_op skipped "$(human_kb "${kb:-0}")" "$p"; skipped=$((skipped+1))
    else
      echo "  removed $(human_kb "${kb:-0}")  $p ($label old version)"
      log_op removed "$(human_kb "${kb:-0}")" "$p"; total_kb=$((total_kb + ${kb:-0}))
    fi
  done <<EOF
$(ls -1t "$root" 2>/dev/null)
EOF
done

# Handoff / Universal Clipboard staging: useractivityd is supposed to prune
# these transfer buffers itself but can leave many GB behind (mole #1178).
# Only items UNTOUCHED FOR 60+ MINUTES go — never cut an in-flight sync.
PB="$HOME/Library/Group Containers/group.com.apple.coreservices.useractivityd/shared-pasteboard"
if [ -d "$PB" ] && [ ! -L "$PB" ] && ! is_whitelisted "$PB"; then
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -e "$p" ] || continue
    [ -L "$p" ] && continue
    kb=$(size_kb "$p")
    if [ "$DRY" = 1 ]; then
      echo "  would remove $(human_kb "${kb:-0}")  $p (Handoff clipboard buffer)"
      total_kb=$((total_kb + ${kb:-0})); continue
    fi
    rm -rf "$p" 2>/dev/null
    if [ ! -e "$p" ]; then
      echo "  removed $(human_kb "${kb:-0}")  $p (Handoff clipboard buffer)"
      log_op removed "$(human_kb "${kb:-0}")" "$p"; total_kb=$((total_kb + ${kb:-0}))
    fi
  done <<EOF
$(find "$PB" -mindepth 1 -maxdepth 1 -mmin +60 2>/dev/null)
EOF
fi

# Tool-native cleanups that are unambiguously safe (freed space is separate from
# the rm total above; both are logged for the audit trail).
if command -v brew >/dev/null 2>&1; then
  if [ "$DRY" = 1 ]; then
    echo "  would run: brew cleanup -s --prune=all"
  else
    echo "  brew cleanup (brew cleanup -s --prune=all)..."
    if brew cleanup -s --prune=all >/dev/null 2>&1; then
      echo "  done: brew cleanup"; log_op cleaned "brew cache" "brew cleanup -s --prune=all"
    else
      echo "  (brew cleanup didn't complete — skipped)"
    fi
  fi
fi
# conda: owner command only — pkgs/ is hardlinked into live envs, raw rm breaks them.
if command -v conda >/dev/null 2>&1; then
  if [ "$DRY" = 1 ]; then echo "  would run: conda clean -y --tarballs --index-cache --logfiles"
  elif conda clean -y --tarballs --index-cache --logfiles >/dev/null 2>&1; then
    echo "  done: conda clean"; log_op cleaned "conda caches" "conda clean -y --tarballs --index-cache --logfiles"
  fi
fi
# Gate simctl on a REAL developer install. /usr/bin/xcrun is a stub present on
# every Mac, so `command -v xcrun` passes even with no Xcode/CLT — and calling it
# then pops the macOS "install command line developer tools" dialog, which would
# ambush a non-developer just trying to free space. xcode-select -p only succeeds
# when a toolchain is actually selected.
if xcode-select -p >/dev/null 2>&1 && command -v xcrun >/dev/null 2>&1; then
  if [ "$DRY" = 1 ]; then
    echo "  would run: xcrun simctl delete unavailable"
  else
    if xcrun simctl delete unavailable >/dev/null 2>&1; then
      echo "  done: removed unavailable simulators"; log_op cleaned "unavailable simulators" "simctl delete unavailable"
    else
      echo "  (no unavailable simulators to remove, or simctl unavailable)"
    fi
  fi
fi

echo
if [ "$DRY" = 1 ]; then
  echo "Would reclaim from cache deletions: $(human_kb "$total_kb") — run without --dry-run to apply."
else
  echo "Approx. reclaimed from cache deletions: $(human_kb "$total_kb") (brew/simulator cleanup above frees more, not counted here)"
fi
[ "$skipped" -gt 0 ] && echo "($skipped path(s) skipped — delete via Finder if you need them gone.)"
echo
echo "Free space now:"
if [ -d /System/Volumes/Data ]; then df -h /System/Volumes/Data 2>/dev/null | sed -n '1p;$p'; else df -h /; fi
echo "(APFS may report freed space as 'purgeable'; df 'Avail' can lag behind.)"
echo "Log: $LOG_DIR/operations.log"
