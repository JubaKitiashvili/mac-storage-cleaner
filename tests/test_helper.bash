# Shared bats helpers. Every test runs against a throwaway fake $HOME —
# a test that touches the real HOME is a bug (mole's fake-HOME discipline).

SCRIPTS="$BATS_TEST_DIRNAME/../skills/mac-storage-cleaner/scripts"

# I3: pin every `bash <script>` / `bash -c "..."` invocation in this suite to
# /bin/bash (macOS's shipped bash 3.2), regardless of what "bash" resolves to
# on $PATH. This suite specifically exists to catch bash-3.2 compatibility
# regressions (unbound-variable guards under `set -u`, no associative arrays,
# `[[ ]]` errexit quirks, ...); a Homebrew-installed bash 4/5 sitting ahead of
# /bin/bash on PATH would silently execute the scripts under a shell that
# doesn't reproduce that surface at all. `export -f` (supported since bash
# 3.2) so the override also reaches `run bash -c "..."` invocations, which
# spawn their own bash process rather than running inline.
bash () { /bin/bash "$@"; }
export -f bash

setup_fake_home () {
  FAKE_HOME="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-home.XXXXXX")"
  export HOME="$FAKE_HOME"
  case "$HOME" in
    /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) ;;
    *) echo "FATAL: HOME is not a test temp dir: $HOME" >&2; exit 1 ;;
  esac
  mkdir -p "$HOME/.Trash" "$HOME/.config/mac-storage-cleaner"
  export MSC_WHITELIST_FILE="$HOME/.config/mac-storage-cleaner/whitelist"
  # trash_path defaults to the REAL /usr/bin/trash when MSC_TRASH_BIN is
  # unset, and that binary talks to the actual Finder/Trash subsystem — it
  # does NOT respect our fake $HOME, so an un-stubbed test can move real
  # items into the real user's ~/.Trash. Default it to a path that can never
  # exist so trash_path always falls through to the (stubbed-or-refused)
  # Finder/mv stages unless a test deliberately overrides it.
  export MSC_TRASH_BIN=/nonexistent-msc-trash
  # lib.sh expands SAFE_PATHS from $HOME at source time — always source AFTER this.
}

teardown_fake_home () {
  [ -n "${FAKE_HOME:-}" ] && rm -rf "$FAKE_HOME"
}

# make_stub <name> <exit-code> [stdout] — executable stub, PATH-first.
make_stub () {
  STUB_DIR="${STUB_DIR:-$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-stub.XXXXXX")}"
  printf '#!/bin/bash\n%s\nexit %s\n' \
    "${3:+printf '%s\\n' \"$3\"}" "$2" > "$STUB_DIR/$1"
  chmod +x "$STUB_DIR/$1"
  export PATH="$STUB_DIR:$PATH"
}
