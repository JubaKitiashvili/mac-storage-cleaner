#!/usr/bin/env bats
load test_helper

setup ()    { setup_fake_home; }
teardown () { teardown_fake_home; }

@test "lib.sh sources cleanly under set -u with a bare fake HOME" {
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; echo OK"
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "the suite's bash override (test_helper.bash) pins script invocations to /bin/bash (I3)" {
  # Don't hardcode "3.2" — that would break the day this machine's /bin/bash
  # changes. Instead confirm the override actually reaches the real binary:
  # a version string from `bash -c` (our function override) must match a
  # version string from invoking /bin/bash directly. If a PATH-shadowed bash
  # were being used instead, BASH_VERSION would differ (or the two calls
  # would otherwise diverge) and this assertion would catch it.
  run bash -c 'echo "$BASH_VERSION"'
  [ "$status" -eq 0 ]
  real="$(/bin/bash -c 'echo "$BASH_VERSION"')"
  [ -n "$real" ]
  [ "$output" = "$real" ] || false
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

@test "collect() does not word-split a glob match when \$HOME contains a space (F3)" {
  local FAKE2
  FAKE2="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc home.XXXXXX")"
  mkdir -p "$FAKE2/.gem/ruby/3.0/cache"
  run env HOME="$FAKE2" bash -c ". '$SCRIPTS/lib.sh'; collect \"\${SAFE_PATHS[@]}\"; printf '%s\n' \"\${FOUND[@]}\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"$FAKE2/.gem/ruby/3.0/cache"* ]] || false
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
      "$FAKE2"/*) ;;
      /private/tmp/*) ;;
      *) echo "split fragment leaked into FOUND: $f"; false ;;
    esac
  done <<< "$output"
  rm -rf "$FAKE2"
}

@test "clean-safe.sh runs to completion on an empty fake HOME" {
  make_stub brew 1
  make_stub xcode-select 1
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Approx. reclaimed"* ]]
}

@test "validate_target_path refuses every corpus entry (property test)" {
  # Corpus floor: deleting corpus lines must itself fail the suite (mole's rule).
  local n
  n=$(grep -cv '^#' "$BATS_TEST_DIRNAME/fixtures/dangerous_paths.txt")
  [ "$n" -ge 35 ]
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    line="${line//__HOME__/$HOME}"
    run bash -c "set -u; . '$SCRIPTS/lib.sh'; validate_target_path \"\$1\"" _ "$line"
    [ "$status" -ne 0 ] || { echo "ACCEPTED dangerous path: $line"; false; }
  done < "$BATS_TEST_DIRNAME/fixtures/dangerous_paths.txt"
}

@test "validate_target_path never denies a SAFE/KEEP-N/AI-agent allowlisted path (F2 anti-drift property)" {
  # The allowlist (what clean-safe.sh is willing to delete) must never
  # intersect the deny list (what validate_target_path refuses) — otherwise
  # a legitimate cache silently stops being cleanable. Glob entries are
  # checked via a synthesized concrete instance (each "*" -> "probe").
  local script
  script="$(mktemp "${BATS_TMPDIR:-/tmp}/msc-f2-check.XXXXXX")"
  cat > "$script" <<'EOF'
set -u
fail=0
check () {
  if ! validate_target_path "$1"; then
    echo "REFUSED allowlisted path: $1"
    fail=1
  fi
}
for entry in "${SAFE_PATHS[@]}" "${KEEP_N_PATHS[@]}"; do
  case "$entry" in
    *'*'*|*'?'*|*'['*)
      probe=$(printf '%s' "$entry" | sed 's/\*/probe/g')
      check "$probe"
      ;;
    *)
      check "$entry"
      check "$entry/x"
      ;;
  esac
done
for spec in "${AI_AGENT_SPECS[@]}"; do
  root="${spec%%|*}"
  check "$root"
  check "$root/x"
done
exit "$fail"
EOF
  run bash -c ". '$SCRIPTS/lib.sh'; . '$script'"
  rm -f "$script"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "trailing slash on \$HOME does not disable home-relative deny rules (C1)" {
  # A $HOME with a trailing slash (some login-shell/launchd setups export one)
  # must not turn every "$home_lower/..." deny entry into a doubled-slash
  # string that never matches. Set HOME *inside* the sourced-lib bash -c
  # invocation (plain assignment, not `env`) so it's visible to lib.sh in the
  # same process without depending on export/subshell propagation quirks.
  local ts="${HOME}/"
  for p in "$HOME" "$HOME/Documents" "$HOME/.ssh"; do
    run bash -c "HOME='$ts'; set -u; . '$SCRIPTS/lib.sh'; validate_target_path \"\$1\"" _ "$p"
    [ "$status" -ne 0 ] || { echo "ACCEPTED dangerous path under trailing-slash HOME: $p"; false; }
  done
}

@test "dangerous-path corpus still refused under trailing-slash \$HOME (C1 property test)" {
  local ts="${HOME}/"
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    line="${line//__HOME__/$HOME}"
    run bash -c "HOME='$ts'; set -u; . '$SCRIPTS/lib.sh'; validate_target_path \"\$1\"" _ "$line"
    [ "$status" -ne 0 ] || { echo "ACCEPTED dangerous path (trailing-slash HOME): $line"; false; }
  done < "$BATS_TEST_DIRNAME/fixtures/dangerous_paths.txt"
}

@test "validate_target_path refuses control characters and empty" {
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; validate_target_path ''"
  [ "$status" -ne 0 ]
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; validate_target_path \"\$(printf '/tmp/a\\nb')\""
  [ "$status" -ne 0 ]
}

@test "validate_target_path accepts normal user files and dirs" {
  mkdir -p "$HOME/Downloads/old-stuff"
  touch "$HOME/Downloads/movie.mkv"
  # NOTE: $HOME/.ssh/old_key_backup used to be in this list, but .ssh is now
  # subtree-denied (F1) — that's the whole point, so it moved to the
  # never-tier subtree-denial test below instead of staying here.
  for p in "$HOME/Downloads/old-stuff" "$HOME/Downloads/movie.mkv" \
           "$HOME/Library/Containers/com.example.gone" "$HOME/Downloads/keys-notes.txt"; do
    run bash -c "set -u; . '$SCRIPTS/lib.sh'; validate_target_path \"\$1\"" _ "$p"
    [ "$status" -eq 0 ] || { echo "REFUSED legitimate path: $p"; false; }
  done
}

@test "validate_target_path refuses a path whose ancestor symlinks into a protected root" {
  ln -s / "$HOME/rootlink"
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; validate_target_path \"\$1\"" _ "$HOME/rootlink/System"
  [ "$status" -ne 0 ]
}

@test "validate_target_path subtree-denies never-tier locations, not just their bare roots (F1)" {
  for p in "$HOME/Library/Application Support/MobileSync/Backup/ABC123" \
           "$HOME/Library/Keychains/login.keychain-db" \
           "$HOME/Library/Mail/V10/foo" \
           "$HOME/Library/Messages/chat.db" \
           "$HOME/.ssh/id_ed25519" \
           "$HOME/.aws/credentials" \
           "$HOME/Pictures/Photos Library.photoslibrary" \
           "$HOME/Pictures/Photos Library.photoslibrary/database/Photos.sqlite"; do
    run bash -c "set -u; . '$SCRIPTS/lib.sh'; validate_target_path \"\$1\"" _ "$p"
    [ "$status" -ne 0 ] || { echo "ACCEPTED never-tier subtree path: $p"; false; }
  done
}

@test "trash-items.sh refuses a protected path and logs it" {
  run bash "$SCRIPTS/trash-items.sh" "$HOME/Library"
  [ "$status" -eq 2 ]
  [[ "$output" == *"REFUSED"* ]] || false
  grep -q "refused" "$HOME/Library/Logs/mac-storage-cleaner/operations.log"
}

@test "validate_target_path refuses another user's home subtree (not just the bare name)" {
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; validate_target_path \"\$1\"" _ "/Users/someoneelse/Documents/file"
  [ "$status" -ne 0 ]
}

@test "validate_target_path accepts /Users/Shared children (not personal; own home stays accepted too)" {
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; validate_target_path \"\$1\"" _ "/Users/Shared/OldInstaller.dmg"
  [ "$status" -eq 0 ] || { echo "REFUSED /Users/Shared child"; false; }
}

@test "validate_target_path accepts unicode filenames under LC_ALL=C and still refuses control chars in both locales" {
  mkdir -p "$HOME/Downloads"
  run env LC_ALL=C bash -c "set -u; . '$SCRIPTS/lib.sh'; validate_target_path \"\$1\"" _ "$HOME/Downloads/café.txt"
  [ "$status" -eq 0 ] || { echo "REFUSED unicode path under LC_ALL=C"; false; }

  run bash -c "set -u; . '$SCRIPTS/lib.sh'; validate_target_path \"\$(printf '/tmp/a\\nb')\""
  [ "$status" -ne 0 ]
  run env LC_ALL=C bash -c "set -u; . '$SCRIPTS/lib.sh'; validate_target_path \"\$(printf '/tmp/a\\nb')\""
  [ "$status" -ne 0 ]
}
