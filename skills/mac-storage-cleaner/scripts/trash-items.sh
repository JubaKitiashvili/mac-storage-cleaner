#!/bin/bash
# mac-storage-cleaner TRASH — move given paths to the Trash (reversible), not rm.
# Use for anything riskier than a pure cache: ask-tier items, app leftovers,
# big/old files. The user can restore from Trash until it's emptied. Every
# action is logged. Usage: trash-items.sh <path> [<path> ...]
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"

[ "$#" -eq 0 ] && { echo "usage: trash-items.sh <path> [<path> ...]"; exit 1; }

log_writable || echo "⚠ Cannot write the audit log ($LOG_DIR/operations.log) — items will still be trashed, but this run will NOT be recorded."
moved=0
for p in "$@"; do
  if [ ! -e "$p" ] && [ ! -L "$p" ]; then
    echo "  not found: $p"
    continue
  fi
  # Refuse BEFORE the size scan: du -sk on a protected root ($HOME, /Users,
  # ...) can walk gigabytes of data just to print a number nobody asked for
  # once we're about to say REFUSED anyway. trash_path still re-validates
  # internally (rc 2) as defense in depth for callers that invoke it
  # directly, but refusal here must stay O(1).
  if ! validate_target_path "$p"; then
    echo "  REFUSED (protected system/user root — never trashed by this tool): $p"
    log_op refused "-" "$p"
    continue
  fi
  sz=$(human_kb "$(size_kb "$p")")
  rc=0; trash_path "$p" || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  trashed ($TRASH_METHOD) $sz  $p"
    log_op "trashed($TRASH_METHOD)" "$sz" "$p"
    moved=$((moved + 1))
  elif [ "$rc" -eq 2 ]; then
    echo "  REFUSED (protected system/user root — never trashed by this tool): $p"
    log_op refused "-" "$p"
  else
    echo "  could NOT trash (permissions/TCC?): $p"
    log_op trash-failed "$sz" "$p"
  fi
done

echo
echo "$moved item(s) moved to Trash — restorable until you empty it."
echo "Space is reclaimed when the Trash is emptied (Finder > Empty Trash)."
echo "Log: $LOG_DIR/operations.log"
