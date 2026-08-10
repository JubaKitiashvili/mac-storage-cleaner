#!/bin/bash
# Shared definitions for mac-storage-cleaner. Sourced by survey.sh and clean-safe.sh.
# bash 3.2 compatible (macOS ships bash 3.2). No side effects on source.

# --- SAFE tier ------------------------------------------------------------
# Pure caches. Deleting one can ONLY make the next build/install/run slower;
# it can never lose data an app or the user cannot regenerate on its own.
# Globs are allowed. $HOME is expanded here (double-quoted), glob chars are not.
SAFE_PATHS=(
  # Apple / Xcode
  "$HOME/Library/Developer/Xcode/DerivedData"
  "$HOME/Library/Developer/Xcode/iOS DeviceSupport"
  "$HOME/Library/Developer/Xcode/watchOS DeviceSupport"
  "$HOME/Library/Developer/Xcode/tvOS DeviceSupport"
  "$HOME/Library/Developer/CoreSimulator/Caches"
  "$HOME/Library/Caches/org.swift.swiftpm"
  "$HOME/Library/Caches/com.apple.dt.Xcode"
  "$HOME/Library/Caches/CocoaPods"
  # JS / Node
  "$HOME/.npm"
  "$HOME/.bun/install/cache"
  "$HOME/Library/Caches/Yarn"
  "$HOME/Library/Caches/node-gyp"
  "$HOME/Library/Caches/typescript"
  "$HOME/Library/Caches/electron"
  "$HOME/Library/Caches/electron-builder"
  # Python
  "$HOME/.cache/uv"
  "$HOME/Library/Caches/uv"
  "$HOME/.cache/pip"
  "$HOME/Library/Caches/pip"
  # JVM / Android build artifacts (see notes: caches/ only, never all of ~/.gradle)
  "$HOME/.gradle/caches"
  # Other
  "$HOME/Library/Caches/Homebrew"
  "$HOME/Library/Caches/go-build"
  # Namespaced RN/Metro temp caches only — NOT bare "react-*", which would match
  # a user's own /private/tmp/react-native-fork clone or scratch dir and rm it.
  "/private/tmp/metro-*"
  "/private/tmp/haste-map-*"
  "/private/tmp/react-native-packager-cache-*"
  "/private/tmp/react-packager-cache-*"
)

# --- ASK tier -------------------------------------------------------------
# Large but either not a pure cache, or expensive to restore (multi-GB
# re-download / long rebuild), or a directory that mixes cache with content
# the user may want. Report with sizes; NEVER delete without an explicit yes.
ASK_PATHS=(
  "$HOME/Library/Containers/com.docker.docker"      # VM disk + images, not cache
  "$HOME/.cache/huggingface"                          # ML models, multi-GB redownload
  "$HOME/.ollama/models"                              # local LLM weights
  "$HOME/Library/Developer/CoreSimulator/Devices"     # simulator state + installed apps
  "$HOME/Library/Developer/Xcode/Archives"            # ships dSYMs for crash symbolication
  "$HOME/Library/pnpm/store"                           # pnpm content store (all projects re-fetch)
  "$HOME/.pnpm-store"
  "$HOME/go/pkg/mod"                                   # read-only; use: go clean -modcache
  "$HOME/.cargo/registry"                              # re-download/re-extract crates
  "$HOME/.gradle/wrapper/dists"                        # downloaded Gradle distributions
  "$HOME/Library/Caches/JetBrains"                     # IDE indexes; forces reindex
  "$HOME/Library/Caches/ms-playwright"                 # test browsers, redownload
  "$HOME/Library/Caches/ms-playwright-go"
  "$HOME/.cache/puppeteer"
  "$HOME/Library/Caches/Cypress"
  "$HOME/Library/Caches/deno"                          # modules from arbitrary URLs; a source can 404 permanently
  "$HOME/.cache/deno"
)

# --- NEVER tier -----------------------------------------------------------
# NOT caches. User data / state that does not come back. Only reported so the
# user is warned when something big sits here; the scripts never touch these.
NEVER_PATHS=(
  "$HOME/Library/Application Support/MobileSync/Backup"  # local iPhone/iPad backups
  "$HOME/.Trash"                                          # emptying is the user's call
)

# collect PATTERNS... -> fills global array FOUND with existing matches.
# Handles globs (word-split, no spaces in our glob patterns) and plain paths
# with spaces (quoted -e test). Resets FOUND on each call.
collect () {
  FOUND=()
  local pat m
  for pat in "$@"; do
    case "$pat" in
      *'*'*|*'?'*|*'['*)
        for m in $pat; do [ -e "$m" ] && FOUND+=("$m"); done ;;
      *)
        [ -e "$pat" ] && FOUND+=("$pat") ;;
    esac
  done
}

# du -sk of a path in kilobytes (0 if missing), for arithmetic.
size_kb () { du -sk "$1" 2>/dev/null | awk '{print $1}'; }

# Pretty-print a kilobyte total as human units.
human_kb () {
  awk -v k="$1" 'BEGIN{
    split("K M G T",u); s=k; i=1;
    while (s>=1024 && i<4){ s/=1024; i++ }
    printf("%.1f%s", s, u[i]);
  }'
}

# --- Operation log --------------------------------------------------------
# Every destructive action appends here, so a run is auditable and the user can
# see exactly what was removed (mirrors what the trustworthy CLIs do).
LOG_DIR="$HOME/Library/Logs/mac-storage-cleaner"
log_op () {  # log_op <action> <size> <path> — best-effort; suppresses its own errors
  mkdir -p "$LOG_DIR" 2>/dev/null
  printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" "$3" >> "$LOG_DIR/operations.log" 2>/dev/null
}
# True only if the audit log can actually be written. Callers warn the user when
# it can't, so a run is never silently unlogged while we claim to log every deletion.
log_writable () {
  mkdir -p "$LOG_DIR" 2>/dev/null && : >> "$LOG_DIR/operations.log" 2>/dev/null
}

# --- Trash-target validation ----------------------------------------------
# trash-items.sh accepts arbitrary user-approved argv paths, so refuse the ones
# that are NEVER right to trash: system roots, the home dir and its top-level
# folders, other users' homes. Deny-only (mole's model): symlink resolution can
# only REVOKE permission, never grant it. APFS is case-insensitive by default,
# so all comparisons are lowercased. rc 0 = OK, rc 1 = refused.
validate_target_path () {
  local p="$1"
  [ -n "$p" ] || return 1
  case "$p" in /*) ;; *) return 1 ;; esac          # absolute only
  # Control chars / newline only — locale-independent. Force C so an ambient
  # non-UTF-8-aware locale doesn't misclassify legitimate multibyte UTF-8
  # filenames (café.txt, Georgian names, ...) as non-printable and refuse
  # them; [:cntrl:] under C is 0x00-0x1F/0x7F in every locale, so real control
  # characters (newline, tab, ...) are still caught while UTF-8 high bytes
  # pass through untouched. Scoped to this function via bash's dynamic `local`.
  local LC_ALL=C
  case "$p" in *[[:cntrl:]]*) return 1 ;; esac
  case "/$p/" in */../*) return 1 ;; esac          # no .. traversal
  # Normalize // and /./ spellings, strip trailing / and /.
  local norm
  norm=$(printf '%s' "$p" | sed -e 's#//*#/#g' -e 's#/\./#/#g' -e 's#/\.$##' -e 's#\(.\)/$#\1#')
  [ -n "$norm" ] || norm="/"
  _vtp_denied "$norm" && return 1
  # Ancestor-symlink defense: re-run the deny check on the physically resolved
  # ancestor (cd -P). A link like ~/rootlink -> / would otherwise smuggle
  # "~/rootlink/System" past the string checks. Walk up from the immediate
  # parent to the nearest EXISTING ancestor before resolving: a path component
  # that does not exist yet (e.g. an orphaned container nobody created) cannot
  # hide a symlink, so it must not trip fail-closed on its own. A genuinely
  # unresolvable existing ancestor (permissions, or "/" itself failing) still
  # refuses.
  local parent suffix phys
  parent=$(dirname "$norm")
  suffix=""
  while [ "$parent" != "/" ] && [ ! -e "$parent" ] && [ ! -L "$parent" ]; do
    suffix="/$(basename "$parent")$suffix"
    parent=$(dirname "$parent")
  done
  phys=$(cd -P "$parent" 2>/dev/null && pwd -P) || return 1
  [ "$phys" = "/" ] && phys=""   # avoid a doubled leading slash below
  _vtp_denied "$phys$suffix/$(basename "$norm")" && return 1
  return 0
}

# Case-insensitive membership test against the deny roots. rc 0 = denied.
_vtp_denied () {
  local lower home_lower r
  lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  home_lower=$(printf '%s' "$HOME" | tr '[:upper:]' '[:lower:]')
  for r in / /system /library /applications /usr /usr/local /bin /sbin /etc \
           /var /private /opt /opt/homebrew /users /volumes /dev /tmp \
           "$home_lower" "$home_lower/library" "$home_lower/desktop" \
           "$home_lower/documents" "$home_lower/downloads" "$home_lower/pictures" \
           "$home_lower/movies" "$home_lower/music" "$home_lower/.trash" \
           "$home_lower/.ssh" "$home_lower/.aws"; do
    [ "$lower" = "$r" ] && return 0
  done
  case "$lower" in
    /applications/*.app) return 0 ;;   # installed app bundles: use an uninstaller
    /users/*)
      # Deny the ENTIRE subtree of every other user's home, not just the bare
      # /Users/<name> entry — otherwise a literal path (or a symlink resolved
      # by the ancestor check below) can reach inside one. Two carve-outs:
      # the current user's own home (its top-level dirs are already denied
      # individually above; everything else under it is a legitimate trash
      # target) and /Users/Shared/<child> (a shared, not personal, location —
      # stale installers etc. are legitimate targets; /Users/Shared itself
      # stays denied, same as today).
      local rest name
      rest="${lower#/users/}"
      name="${rest%%/*}"
      case "$home_lower" in
        "/users/$name"|"/users/$name/"*) return 1 ;;
      esac
      [ "$name" = "shared" ] && [ "$rest" != "shared" ] && return 1
      return 0
      ;;
  esac
  return 1
}

# --- Reversible delete ----------------------------------------------------
# Move a path to the Trash via Finder instead of rm, so the user can restore it.
# Used for anything riskier than a pure cache (ask-tier items, app leftovers,
# big files). Returns non-zero if it could not be trashed.
# NOTE: trashed items still occupy disk until the Trash is emptied — for pure
# caches we prefer a direct rm (see clean-safe.sh) so space is freed immediately.
trash_path () {
  local p="$1"
  [ -e "$p" ] || return 0
  # Pass the path as an argv value, NOT interpolated into the script text — a
  # filename containing " or \ would otherwise break (or, pathologically, inject)
  # the AppleScript. argv is data, so any legal filename trashes correctly.
  osascript - "$p" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
  tell application "Finder" to delete (POSIX file (item 1 of argv) as alias)
end run
APPLESCRIPT
}

# --- Installed apps -> bundle identifiers ---------------------------------
# Fast prefilter for orphan detection. Not authoritative on its own (apps can
# live outside these dirs), so container_is_orphan double-checks with Spotlight.
installed_bundle_ids () {
  local base app id
  for base in /Applications "$HOME/Applications" /System/Applications /System/Applications/Utilities; do
    [ -d "$base" ] || continue
    for app in "$base"/*.app "$base"/*/*.app; do
      [ -d "$app" ] || continue
      id=$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null)
      [ -n "$id" ] && printf '%s\n' "$id"
    done
  done
}

# Decide whether a sandbox-container bundle id belongs to NO installed app.
# Conservative on purpose: a false "orphan" that deletes a live app's data would
# wreck trust, so we clear a container as live on ANY of:
#   - exact match to an installed id
#   - it is an extension of an installed app  (id.SomeExtension)
#   - an installed id is an extension of it   (rare, helper bundles)
#   - Spotlight finds an app bundle anywhere carrying this id or its 3-part root
# $IDS (newline list from installed_bundle_ids) must be set by the caller.
# Returns 0 if the container looks orphaned, 1 if it belongs to a live app.
container_is_orphan () {
  local n="$1" id root
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    case "$n" in "$id"|"$id".*) return 1 ;; esac
    case "$id" in "$n".*) return 1 ;; esac
  done <<EOF
${IDS:-}
EOF
  # A quote in the name would break the mdfind query string; real bundle IDs
  # never contain one, so treat such a name as inconclusive (not orphan).
  case "$n" in *\'*|*\"*) return 1 ;; esac
  if mdfind "kMDItemContentTypeTree == 'com.apple.application-bundle' && kMDItemCFBundleIdentifier == '$n'" 2>/dev/null | grep -q .; then
    return 1
  fi
  root=$(printf '%s' "$n" | awk -F. 'NF>=3{printf "%s.%s.%s",$1,$2,$3; next} {print}')
  if [ "$root" != "$n" ] && \
     mdfind "kMDItemContentTypeTree == 'com.apple.application-bundle' && kMDItemCFBundleIdentifier == '$root'" 2>/dev/null | grep -q .; then
    return 1
  fi
  return 0
}
