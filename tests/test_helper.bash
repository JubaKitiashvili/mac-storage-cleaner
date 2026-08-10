# Shared bats helpers. Every test runs against a throwaway fake $HOME —
# a test that touches the real HOME is a bug (mole's fake-HOME discipline).

SCRIPTS="$BATS_TEST_DIRNAME/../skills/mac-storage-cleaner/scripts"

setup_fake_home () {
  FAKE_HOME="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-home.XXXXXX")"
  export HOME="$FAKE_HOME"
  case "$HOME" in
    /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) ;;
    *) echo "FATAL: HOME is not a test temp dir: $HOME" >&2; exit 1 ;;
  esac
  mkdir -p "$HOME/.Trash" "$HOME/.config/mac-storage-cleaner"
  export MSC_WHITELIST_FILE="$HOME/.config/mac-storage-cleaner/whitelist"
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
