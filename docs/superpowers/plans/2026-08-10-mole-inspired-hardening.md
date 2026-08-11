# Mole-Inspired Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adopt the seven highest-value safety and coverage mechanisms from tw93/mole into mac-storage-cleaner while preserving its allowlist-only architecture: a test harness with a dangerous-path corpus, target validation, a three-stage Trash fallback chain, a user whitelist, `--dry-run`, fail-closed process guards, DeviceSupport keep-N retention, AI-CLI version retention, and new safe-tier coverage.

**Architecture:** All new logic lives in `scripts/lib.sh` (single shared lib, sourced by every script — existing pattern). `clean-safe.sh`'s deletion loop gains, in order: whitelist check → process guard → dry-run gate → rm. Order matters: guards run BEFORE the dry-run return so preview and reality can never diverge (mole's invariant). Deny-list validation applies only to `trash-items.sh` (which takes arbitrary argv paths); the safe tier stays allowlist-only.

**Tech Stack:** bash 3.2 (macOS stock), bats-core for tests, no new runtime dependencies.

## Global Constraints

- **bash 3.2 compatible** — no `declare -A`, no extglob, no `readarray`, no `${var,,}`. Under `set -u`, expanding an EMPTY array with `"${arr[@]}"` crashes bash 3.2 — always guard with `[ "${#arr[@]}" -gt 0 ]` first (existing pattern, clean-safe.sh:15-18).
- **`set -u` in every executable script**; `lib.sh` must stay side-effect-free on source.
- **Source of truth:** `~/Desktop/Projects/mac-storage-cleaner/skills/mac-storage-cleaner/` (git repo). The installed copy `~/.claude/skills/mac-storage-cleaner/` is synced in the final task.
- **Env-var prefix `MSC_`**: `MSC_DRY_RUN`, `MSC_WHITELIST_FILE`, `MSC_TRASH_BIN`, `MSC_DEVICE_SUPPORT_KEEP`, `MSC_AI_AGENTS_KEEP`.
- **Every destructive action still logs via `log_op`** — except in dry-run, where `log_op` becomes a no-op (nothing happened, nothing to record).
- **Fail closed:** wherever a check cannot determine state (pgrep missing, symlink unresolvable, broken active-version link), the answer is "skip", never "proceed".
- **Tests never touch the real HOME.** Every bats file's setup exits FATAL unless `$HOME` is a temp dir (mole's discipline).
- Commit after each task: `git -C ~/Desktop/Projects/mac-storage-cleaner add -A && git commit`.

## File Structure

```
repo root (~/Desktop/Projects/mac-storage-cleaner/)
├── skills/mac-storage-cleaner/
│   ├── SKILL.md                      # Modify (Task 10)
│   ├── references/cache-catalog.md   # Modify (Tasks 7, 9)
│   └── scripts/
│       ├── lib.sh                    # Modify (Tasks 2,3,4,6,7,8) — all new shared logic
│       ├── clean-safe.sh             # Modify (Tasks 4,5,6,7,8,9)
│       ├── survey.sh                 # Modify (Tasks 4,7)
│       ├── find-extras.sh            # Modify (Task 9)
│       └── trash-items.sh            # Modify (Tasks 2,3)
└── tests/                            # Create (Task 1)
    ├── test_helper.bash              # fake-HOME + stub helpers
    ├── fixtures/dangerous_paths.txt  # deny corpus (Task 2)
    ├── lib_core.bats                 # Task 1 smoke + Task 2 validation
    ├── trash.bats                    # Task 3
    ├── whitelist.bats                # Task 4
    ├── clean_safe.bats               # Tasks 5,6,7
    └── retention.bats                # Tasks 7,8
```

---

### Task 1: Test harness bootstrap

**Files:**
- Create: `tests/test_helper.bash`
- Create: `tests/lib_core.bats`

**Interfaces:**
- Produces: `setup_fake_home` / `teardown_fake_home` (exported `$HOME` under mktemp, FATAL guard), `make_stub <name> <exit-code> [stdout]` (drops an executable stub into `$STUB_DIR`, prepended to PATH), `SCRIPTS` variable pointing at `skills/mac-storage-cleaner/scripts`. Every later test file consumes these.

- [ ] **Step 1: Install bats-core**

```bash
brew install bats-core
bats --version   # expect: Bats 1.x
```

- [ ] **Step 2: Write the helper**

`tests/test_helper.bash`:

```bash
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
```

- [ ] **Step 3: Write the smoke test**

`tests/lib_core.bats`:

```bash
#!/usr/bin/env bats
load test_helper

setup ()    { setup_fake_home; }
teardown () { teardown_fake_home; }

@test "lib.sh sources cleanly under set -u with a bare fake HOME" {
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; echo OK"
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]]
}

@test "collect returns empty FOUND on a machine with no caches" {
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; collect \"\${SAFE_PATHS[@]}\"; echo \${#FOUND[@]}"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "clean-safe.sh runs to completion on an empty fake HOME" {
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Approx. reclaimed"* ]]
}
```

- [ ] **Step 4: Run — all three must pass already (they test current behavior)**

```bash
cd ~/Desktop/Projects/mac-storage-cleaner && bats tests/
```
Expected: `3 tests, 0 failures`. (If the clean-safe test hits real `brew`, that's fine — brew cleanup of a real cache is safe-tier by definition; but keep CI-neutral by stubbing: add `make_stub brew 1` and `make_stub xcode-select 1` in that test's setup so tool-native steps skip.)

- [ ] **Step 5: Commit**

```bash
git add tests/ && git commit -m "test: bats harness with fake-HOME discipline + smoke tests"
```

---

### Task 2: `validate_target_path` + dangerous-path corpus, wired into trash-items.sh

**Files:**
- Modify: `skills/mac-storage-cleaner/scripts/lib.sh` (append after `log_writable`, before `trash_path`)
- Modify: `skills/mac-storage-cleaner/scripts/trash-items.sh:14-28`
- Create: `tests/fixtures/dangerous_paths.txt`
- Test: `tests/lib_core.bats` (append)

**Interfaces:**
- Produces: `validate_target_path <path>` → rc 0 = OK to trash, rc 1 = refused. Task 3's `trash_path` calls it; refusal there returns rc 2 to distinguish from mechanical failure.

- [ ] **Step 1: Write the corpus fixture**

`tests/fixtures/dangerous_paths.txt` (the literal token `__HOME__` is substituted by the test; lines starting `#` skipped):

```
/
/System
/SYSTEM
//System
/System/
/System/.
/Library
/Applications
/Applications/Safari.app
/usr
/usr/local
/bin
/sbin
/etc
/var
/private
/private/tmp/../..
/opt
/opt/homebrew
/Users
/Users/someoneelse
/Volumes
/dev
/tmp
Documents
./relative
../parent
/Users/x/../../System
__HOME__
__HOME__/Library
__HOME__/Desktop
__HOME__/Documents
__HOME__/Downloads
__HOME__/Pictures
__HOME__/Movies
__HOME__/Music
__HOME__/.Trash
__HOME__/.ssh
__HOME__/.aws
```

- [ ] **Step 2: Write the failing tests**

Append to `tests/lib_core.bats`:

```bash
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

@test "validate_target_path refuses control characters and empty" {
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; validate_target_path ''"
  [ "$status" -ne 0 ]
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; validate_target_path \"\$(printf '/tmp/a\\nb')\""
  [ "$status" -ne 0 ]
}

@test "validate_target_path accepts normal user files and dirs" {
  mkdir -p "$HOME/Downloads/old-stuff"
  touch "$HOME/Downloads/movie.mkv"
  for p in "$HOME/Downloads/old-stuff" "$HOME/Downloads/movie.mkv" \
           "$HOME/Library/Containers/com.example.gone" "$HOME/.ssh/old_key_backup"; do
    run bash -c "set -u; . '$SCRIPTS/lib.sh'; validate_target_path \"\$1\"" _ "$p"
    [ "$status" -eq 0 ] || { echo "REFUSED legitimate path: $p"; false; }
  done
}

@test "validate_target_path refuses a path whose ancestor symlinks into a protected root" {
  ln -s / "$HOME/rootlink"
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; validate_target_path \"\$1\"" _ "$HOME/rootlink/System"
  [ "$status" -ne 0 ]
}

@test "trash-items.sh refuses a protected path and logs it" {
  run bash "$SCRIPTS/trash-items.sh" "$HOME/Library"
  [[ "$output" == *"REFUSED"* ]]
  grep -q "refused" "$HOME/Library/Logs/mac-storage-cleaner/operations.log"
}
```

- [ ] **Step 3: Run to verify they fail**

```bash
bats tests/lib_core.bats
```
Expected: FAIL — `validate_target_path: command not found`.

- [ ] **Step 4: Implement in lib.sh**

Append to `lib.sh` after the `log_writable` block:

```bash
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
  case "$p" in *[![:print:]]*) return 1 ;; esac    # control chars / newline
  case "/$p/" in */../*) return 1 ;; esac          # no .. traversal
  # Normalize // and /./ spellings, strip trailing / and /.
  local norm
  norm=$(printf '%s' "$p" | sed -e 's#//*#/#g' -e 's#/\./#/#g' -e 's#/\.$##' -e 's#\(.\)/$#\1#')
  [ -n "$norm" ] || norm="/"
  _vtp_denied "$norm" && return 1
  # Ancestor-symlink defense: re-run the deny check on the physically resolved
  # parent (cd -P). A link like ~/rootlink -> / would otherwise smuggle
  # "~/rootlink/System" past the string checks. Unresolvable parent = refuse.
  local parent phys
  parent=$(dirname "$norm")
  phys=$(cd -P "$parent" 2>/dev/null && pwd -P) || return 1
  _vtp_denied "$phys/$(basename "$norm")" && return 1
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
    /users/*) case "${lower#/users/}" in */*) ;; *) return 0 ;; esac ;;  # any /Users/<name>
  esac
  return 1
}
```

- [ ] **Step 5: Wire into trash-items.sh**

In `trash-items.sh`, replace the loop body's first check (lines 15-18):

```bash
for p in "$@"; do
  if [ ! -e "$p" ] && [ ! -L "$p" ]; then
    echo "  not found: $p"
    continue
  fi
  if ! validate_target_path "$p"; then
    echo "  REFUSED (protected system/user root — never trashed by this tool): $p"
    log_op refused "-" "$p"
    continue
  fi
  sz=$(human_kb "$(size_kb "$p")")
  ...            # rest of the existing loop unchanged
```

- [ ] **Step 6: Run tests — all pass**

```bash
bats tests/lib_core.bats
```
Expected: PASS (8 tests total).

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: deny-list validation for trash targets + 38-entry dangerous-path corpus (property-tested)"
```

---

### Task 3: Three-stage Trash fallback chain

**Files:**
- Modify: `skills/mac-storage-cleaner/scripts/lib.sh` — replace `trash_path` (lines 125-136)
- Modify: `skills/mac-storage-cleaner/scripts/trash-items.sh` — report method, handle rc 2
- Test: `tests/trash.bats` (create)

**Interfaces:**
- Consumes: `validate_target_path` (Task 2).
- Produces: `trash_path <path>` → rc 0 moved (global `TRASH_METHOD` = `trash-cli`|`finder`|`mv`), rc 1 mechanical failure, rc 2 refused by validation. `MSC_TRASH_BIN` overrides the trash binary (tests point it at a stub; default `/usr/bin/trash`, present on macOS 14+).

- [ ] **Step 1: Write the failing tests**

`tests/trash.bats`:

```bash
#!/usr/bin/env bats
load test_helper

setup ()    { setup_fake_home; }
teardown () { teardown_fake_home; }

@test "trash_path uses MSC_TRASH_BIN when executable" {
  mkdir -p "$HOME/target-dir"
  cat > "$HOME/fake-trash" <<EOF
#!/bin/bash
mv "\$1" "\$HOME/.Trash/"
EOF
  chmod +x "$HOME/fake-trash"
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; MSC_TRASH_BIN='$HOME/fake-trash' trash_path '$HOME/target-dir' && echo method=\$TRASH_METHOD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"method=trash-cli"* ]]
  [ -d "$HOME/.Trash/target-dir" ]
}

@test "trash_path falls back to same-volume mv when binary and Finder both fail" {
  mkdir -p "$HOME/fallback-dir"; touch "$HOME/fallback-dir/f"
  make_stub osascript 1
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; MSC_TRASH_BIN=/nonexistent trash_path '$HOME/fallback-dir' && echo method=\$TRASH_METHOD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"method=mv"* ]]
  [ ! -e "$HOME/fallback-dir" ]
  [ -d "$HOME/.Trash/fallback-dir" ]
}

@test "mv fallback uniquifies when the Trash already holds that name" {
  mkdir -p "$HOME/dup" "$HOME/.Trash/dup"
  make_stub osascript 1
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; MSC_TRASH_BIN=/nonexistent trash_path '$HOME/dup'"
  [ "$status" -eq 0 ]
  [ -d "$HOME/.Trash/dup" ]                       # original Trash item untouched
  [ "$(find "$HOME/.Trash" -maxdepth 1 -name 'dup*' | wc -l | tr -d ' ')" -eq 2 ]
}

@test "trash_path returns 2 (refused) on a protected path without touching it" {
  make_stub osascript 1
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; MSC_TRASH_BIN=/nonexistent trash_path '$HOME/Library'"
  [ "$status" -eq 2 ]
}
```

- [ ] **Step 2: Run to verify failures**

```bash
bats tests/trash.bats
```
Expected: FAIL — current `trash_path` knows no `MSC_TRASH_BIN`, no `TRASH_METHOD`, no mv fallback, no rc 2.

- [ ] **Step 3: Replace `trash_path` in lib.sh**

```bash
# --- Reversible delete ----------------------------------------------------
# Move a path to the Trash (restorable) — never rm. Three-stage chain (mole's
# order): /usr/bin/trash by ABSOLUTE path (ships with macOS 14+, headless-safe,
# immune to PATH shadowing) -> Finder AppleScript (argv-passed, injection-safe)
# -> same-volume mv into ~/.Trash (loses "Put Back", still restorable by hand).
# rc 0 = moved (TRASH_METHOD set), rc 1 = could not move, rc 2 = refused.
# NOTE: trashed items occupy disk until the Trash is emptied — pure caches use
# direct rm in clean-safe.sh instead, so their space frees immediately.
TRASH_METHOD=""
trash_path () {
  local p="$1"
  { [ -e "$p" ] || [ -L "$p" ]; } || return 0
  validate_target_path "$p" || return 2
  local bin="${MSC_TRASH_BIN:-/usr/bin/trash}"
  if [ -x "$bin" ] && "$bin" "$p" >/dev/null 2>&1; then
    TRASH_METHOD="trash-cli"; return 0
  fi
  if osascript - "$p" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
  tell application "Finder" to delete (POSIX file (item 1 of argv) as alias)
end run
APPLESCRIPT
  then TRASH_METHOD="finder"; return 0; fi
  # Last resort. Same-device only: a cross-volume mv degrades into copy+delete
  # and can leave the only copy split across volumes on failure (mole's rule).
  local pdev tdev base dest i
  pdev=$(stat -f %d "$p" 2>/dev/null); tdev=$(stat -f %d "$HOME/.Trash" 2>/dev/null)
  [ -n "$pdev" ] && [ "$pdev" = "$tdev" ] || return 1
  base=$(basename "$p"); dest="$HOME/.Trash/$base"; i=2
  while [ -e "$dest" ] || [ -L "$dest" ]; do
    dest="$HOME/.Trash/$base $i"; i=$((i + 1))
    [ "$i" -gt 100 ] && return 1     # never overwrite an existing Trash item
  done
  mv "$p" "$dest" 2>/dev/null || return 1
  TRASH_METHOD="mv"
}
```

- [ ] **Step 4: Update trash-items.sh reporting**

Replace the `if trash_path` block (previously lines 20-27):

```bash
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
```

(The Task 2 `validate_target_path` pre-check in trash-items.sh becomes redundant — remove it; rc 2 now carries refusal. Keep the corpus test green: it asserts on output + log, both still produced here.)

- [ ] **Step 5: Run all tests**

```bash
bats tests/
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: three-stage Trash chain (/usr/bin/trash -> Finder -> same-volume mv) with method reporting"
```

---

### Task 4: User whitelist

**Files:**
- Modify: `skills/mac-storage-cleaner/scripts/lib.sh` (append section)
- Modify: `skills/mac-storage-cleaner/scripts/clean-safe.sh` (loop head)
- Modify: `skills/mac-storage-cleaner/scripts/survey.sh` (one-line annotation)
- Test: `tests/whitelist.bats` (create)

**Interfaces:**
- Produces: `load_whitelist` (fills global `WHITELIST` array from `$MSC_WHITELIST_FILE`, default `~/.config/mac-storage-cleaner/whitelist`), `is_whitelisted <path>` → rc 0 = protected. Tasks 5-9 call `is_whitelisted` inside every deletion loop.
- File format: one path or glob per line; `#` comments; leading `~/` expands to `$HOME`; an entry protects itself AND everything under it.

- [ ] **Step 1: Write the failing tests**

`tests/whitelist.bats`:

```bash
#!/usr/bin/env bats
load test_helper

setup ()    { setup_fake_home; }
teardown () { teardown_fake_home; }

write_wl () { printf '%s\n' "$@" > "$MSC_WHITELIST_FILE"; }

@test "whitelist protects exact entries, children, tilde and globs; comments ignored" {
  write_wl '# keep my gradle' '~/.gradle/caches' "$HOME/Library/Caches/pip" '~/Library/Caches/electron*'
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; load_whitelist
    is_whitelisted '$HOME/.gradle/caches'              && echo A
    is_whitelisted '$HOME/.gradle/caches/modules-2'    && echo B
    is_whitelisted '$HOME/Library/Caches/pip'          && echo C
    is_whitelisted '$HOME/Library/Caches/electron-builder' && echo D
    is_whitelisted '$HOME/.npm'                        || echo E"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'A\nB\nC\nD\nE')" ]
}

@test "missing whitelist file means nothing is protected" {
  rm -f "$MSC_WHITELIST_FILE"
  run bash -c "set -u; . '$SCRIPTS/lib.sh'; load_whitelist; is_whitelisted '$HOME/.npm' || echo unprotected"
  [ "$output" = "unprotected" ]
}

@test "clean-safe skips a whitelisted cache and reports it" {
  mkdir -p "$HOME/.npm/junk" "$HOME/.cache/pip/junk"
  write_wl '~/.npm'
  make_stub brew 1; make_stub xcode-select 1
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped (whitelisted): $HOME/.npm"* ]]
  [ -d "$HOME/.npm/junk" ]          # untouched
  [ ! -e "$HOME/.cache/pip" ]       # non-whitelisted still cleaned
}
```

- [ ] **Step 2: Run to verify failure**

```bash
bats tests/whitelist.bats
```
Expected: FAIL — `load_whitelist: command not found`.

- [ ] **Step 3: Implement in lib.sh**

Append:

```bash
# --- User whitelist -------------------------------------------------------
# Optional user-owned protection list: one path or glob per line, '#' comments,
# leading ~/ expands to $HOME. An entry protects itself and everything under it.
# clean-safe.sh consults this before every deletion, so a user who wants e.g.
# DerivedData kept doesn't have to rely on the agent remembering (mole's
# ~/.config/mole/whitelist, simplified).
MSC_WHITELIST_FILE="${MSC_WHITELIST_FILE:-$HOME/.config/mac-storage-cleaner/whitelist}"
WHITELIST=()
load_whitelist () {
  WHITELIST=()
  [ -f "$MSC_WHITELIST_FILE" ] || return 0
  local raw line
  while IFS= read -r raw || [ -n "$raw" ]; do
    line="${raw%%#*}"
    # trim surrounding whitespace (bash 3.2: no extglob)
    line=$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -z "$line" ] && continue
    case "$line" in "~") line="$HOME" ;; "~/"*) line="$HOME/${line#\~/}" ;; esac
    WHITELIST+=("$line")
  done < "$MSC_WHITELIST_FILE"
}
is_whitelisted () {   # rc 0 = protected. Entries may be globs — $e is unquoted in case.
  local p="$1" e
  [ "${#WHITELIST[@]}" -eq 0 ] && return 1
  for e in "${WHITELIST[@]}"; do
    case "$p" in $e|$e/*) return 0 ;; esac
  done
  return 1
}
```

- [ ] **Step 4: Wire into clean-safe.sh**

After `. "$DIR/lib.sh"` add `load_whitelist`. At the top of the deletion loop (before `kb=$(size_kb "$p")`):

```bash
  if is_whitelisted "$p"; then
    echo "  skipped (whitelisted): $p"
    log_op skipped-whitelisted "-" "$p"
    skipped=$((skipped + 1))
    continue
  fi
```

- [ ] **Step 5: Annotate the survey**

In `survey.sh` after the safe-tier total (line 22's `awk` line), add:

```bash
load_whitelist
[ "${#WHITELIST[@]}" -gt 0 ] && \
  echo "  (whitelist active: ${#WHITELIST[@]} protected pattern(s) — clean-safe will skip matches; edit $MSC_WHITELIST_FILE)"
```

- [ ] **Step 6: Run all tests, commit**

```bash
bats tests/ && git add -A && git commit -m "feat: user whitelist file honored by clean-safe and surfaced in survey"
```

---

### Task 5: `--dry-run` for clean-safe.sh

**Files:**
- Modify: `skills/mac-storage-cleaner/scripts/clean-safe.sh`
- Modify: `skills/mac-storage-cleaner/scripts/lib.sh` (`log_op` no-op gate)
- Test: `tests/clean_safe.bats` (create)

**Interfaces:**
- Produces: `clean-safe.sh --dry-run` (or `MSC_DRY_RUN=1`) — full preview, zero deletion, zero log writes. `DRY` variable (0/1) inside clean-safe.sh; Tasks 6-9 must place their guard checks BEFORE the dry-run `continue` and honor `DRY` in their own sections.

- [ ] **Step 1: Write the failing tests**

`tests/clean_safe.bats`:

```bash
#!/usr/bin/env bats
load test_helper

setup ()    { setup_fake_home; make_stub brew 1; make_stub xcode-select 1; }
teardown () { teardown_fake_home; }

@test "--dry-run previews removals, deletes nothing, writes no log" {
  mkdir -p "$HOME/.npm/junk" "$HOME/.gradle/caches/junk"
  run bash "$SCRIPTS/clean-safe.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN"* ]]
  [[ "$output" == *"would remove"*".npm"* ]]
  [[ "$output" == *"would remove"*".gradle/caches"* ]]
  [ -d "$HOME/.npm/junk" ]
  [ -d "$HOME/.gradle/caches/junk" ]
  [ ! -e "$HOME/Library/Logs/mac-storage-cleaner/operations.log" ]
}

@test "dry-run preview respects the whitelist (preview == reality)" {
  mkdir -p "$HOME/.npm/junk"
  printf '~/.npm\n' > "$MSC_WHITELIST_FILE"
  run bash "$SCRIPTS/clean-safe.sh" --dry-run
  [[ "$output" == *"skipped (whitelisted): $HOME/.npm"* ]]
  [[ "$output" != *"would remove"*".npm"* ]]
}

@test "real run still deletes (regression)" {
  mkdir -p "$HOME/.npm/junk"
  run bash "$SCRIPTS/clean-safe.sh"
  [ ! -e "$HOME/.npm" ]
  grep -q "removed" "$HOME/Library/Logs/mac-storage-cleaner/operations.log"
}
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL — `--dry-run` unknown, files deleted anyway.

- [ ] **Step 3: Implement**

In `lib.sh`, change `log_op` first line:

```bash
log_op () {  # log_op <action> <size> <path> — best-effort; no-op in dry-run
  [ "${MSC_DRY_RUN:-0}" = "1" ] && return 0
  mkdir -p "$LOG_DIR" 2>/dev/null
  ...
```

In `clean-safe.sh`, after sourcing lib:

```bash
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1
[ "${MSC_DRY_RUN:-0}" = "1" ] && DRY=1
export MSC_DRY_RUN="$DRY"
[ "$DRY" = 1 ] && echo "=== DRY RUN — nothing will be deleted ==="
```

In the deletion loop, AFTER the whitelist check (and after Task 6's guard check), BEFORE the `rm`:

```bash
  kb=$(size_kb "$p")
  if [ "$DRY" = 1 ]; then
    echo "  would remove $(human_kb "${kb:-0}")  $p"
    total_kb=$((total_kb + ${kb:-0}))
    continue
  fi
```

Tool-native sections gain a dry gate, e.g. brew:

```bash
if command -v brew >/dev/null 2>&1; then
  if [ "$DRY" = 1 ]; then echo "  would run: brew cleanup -s --prune=all"
  else
    ...existing block...
  fi
fi
```

Same shape for the simctl block (`would run: xcrun simctl delete unavailable`). Final summary line becomes conditional:

```bash
if [ "$DRY" = 1 ]; then
  echo "Would reclaim from cache deletions: $(human_kb "$total_kb") — run without --dry-run to apply."
else
  echo "Approx. reclaimed from cache deletions: $(human_kb "$total_kb") (brew/simulator cleanup above frees more, not counted here)"
fi
```

Also gate the `log_writable` warning: `[ "$DRY" = 1 ] || log_writable || echo "⚠ ..."`.

- [ ] **Step 4: Run all tests, commit**

```bash
bats tests/ && git add -A && git commit -m "feat: --dry-run for clean-safe.sh, honored inside the deletion loop (preview == reality)"
```

---

### Task 6: Fail-closed process guards (Xcode family, Gradle daemon)

**Files:**
- Modify: `skills/mac-storage-cleaner/scripts/lib.sh` (append)
- Modify: `skills/mac-storage-cleaner/scripts/clean-safe.sh` (loop)
- Test: `tests/clean_safe.bats` (append)

**Interfaces:**
- Consumes: `DRY` ordering from Task 5 (guard check sits BEFORE the dry-run `continue`).
- Produces: `guard_reason_for_path <path>` — echoes a human reason and rc 0 when the path must be skipped; rc 1 when free to delete. Tri-state inner helper `guard_procs_running <name>...` (0 running / 1 idle / 2 unknown; unknown ⇒ skip).
- Scope decision (locked): guard ONLY the Xcode family and the Gradle daemon. npm/bun/yarn are NOT guarded — their caches are content-addressed and a `pgrep -x node` guard would permanently block cleaning on any machine running a dev server, which is this tool's primary audience.

- [ ] **Step 1: Write the failing tests**

Append to `tests/clean_safe.bats`:

```bash
@test "gradle caches are skipped while a Gradle daemon runs" {
  mkdir -p "$HOME/.gradle/caches/junk"
  make_stub pgrep 0            # every probe reports "running"
  run bash "$SCRIPTS/clean-safe.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped (in use"*".gradle/caches"* ]]
  [ -d "$HOME/.gradle/caches/junk" ]
}

@test "unknown process state fails closed (pgrep errors => skip)" {
  mkdir -p "$HOME/Library/Developer/Xcode/DerivedData/junk"
  make_stub pgrep 2            # rc 2 = probe error, not "no match"
  run bash "$SCRIPTS/clean-safe.sh"
  [[ "$output" == *"skipped (process state unknown"*"DerivedData"* ]]
  [ -d "$HOME/Library/Developer/Xcode/DerivedData/junk" ]
}

@test "idle processes let deletion proceed" {
  mkdir -p "$HOME/.gradle/caches/junk"
  make_stub pgrep 1            # rc 1 = no matching process
  run bash "$SCRIPTS/clean-safe.sh"
  [ ! -e "$HOME/.gradle/caches" ]
}

@test "guard runs before the dry-run gate (preview == reality)" {
  mkdir -p "$HOME/.gradle/caches/junk"
  make_stub pgrep 0
  run bash "$SCRIPTS/clean-safe.sh" --dry-run
  [[ "$output" == *"skipped (in use"* ]]
  [[ "$output" != *"would remove"*".gradle/caches"* ]]
}
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL — no guard messages; `.gradle/caches` deleted even with pgrep stub at 0.

- [ ] **Step 3: Implement in lib.sh**

```bash
# --- Process guards (fail closed) -----------------------------------------
# Deleting a build cache while its owner writes to it corrupts the next build
# worse than a full cache miss. Tri-state (mole's contract): 0 = running,
# 1 = idle, 2 = unknown — and unknown DENIES deletion: an unreadable process
# table is not evidence the app is closed.
guard_procs_running () {   # guard_procs_running <exact-process-name>...
  command -v pgrep >/dev/null 2>&1 || return 2
  local n rc
  for n in "$@"; do
    if pgrep -x "$n" >/dev/null 2>&1; then return 0
    else rc=$?; [ "$rc" -eq 1 ] || return 2; fi
  done
  return 1
}

# Echo a skip reason (rc 0) when this safe-tier path's owner may be live.
# rc 1 = no guard applies or owner idle. Only Xcode-family paths and the
# Gradle daemon are guarded — npm/bun caches are content-addressed and their
# runtimes (node) run constantly on dev machines, so guarding them would
# permanently block cleaning (deliberate scope decision).
guard_reason_for_path () {
  local p="$1" st=1
  case "$p" in
    "$HOME/Library/Developer/Xcode/"*|"$HOME/Library/Developer/CoreSimulator/"*| \
    "$HOME/Library/Caches/com.apple.dt.Xcode"|"$HOME/Library/Caches/org.swift.swiftpm"| \
    "$HOME/Library/Caches/CocoaPods")
      guard_procs_running Xcode xcodebuild Simulator swift-frontend xctest; st=$? ;;
    "$HOME/.gradle/caches")
      # The daemon is a java process; -x java would over-match. -f GradleDaemon
      # matches the daemon's command line specifically.
      if command -v pgrep >/dev/null 2>&1; then
        if pgrep -f GradleDaemon >/dev/null 2>&1; then st=0
        else st=$?; [ "$st" -eq 1 ] || st=2; fi
      else st=2; fi ;;
    *) return 1 ;;
  esac
  case "$st" in
    0) printf 'in use — a guarded process is running' ; return 0 ;;
    2) printf 'process state unknown — failing closed' ; return 0 ;;
  esac
  return 1
}
```

- [ ] **Step 4: Wire into clean-safe.sh**

In the loop, AFTER the whitelist check, BEFORE the dry-run gate:

```bash
  if reason=$(guard_reason_for_path "$p"); then
    echo "  skipped ($reason): $p"
    log_op skipped-in-use "-" "$p"
    skipped=$((skipped + 1))
    continue
  fi
```

- [ ] **Step 5: Run all tests, commit**

```bash
bats tests/ && git add -A && git commit -m "feat: fail-closed tri-state process guards for Xcode family and Gradle daemon"
```

---

### Task 7: DeviceSupport keep-N retention

**Files:**
- Modify: `skills/mac-storage-cleaner/scripts/lib.sh` (move 3 paths out of `SAFE_PATHS` into `KEEP_N_PATHS`; add helper)
- Modify: `skills/mac-storage-cleaner/scripts/clean-safe.sh` (new section)
- Modify: `skills/mac-storage-cleaner/scripts/survey.sh` (show keep-N paths)
- Modify: `skills/mac-storage-cleaner/references/cache-catalog.md` (safe-tier row note)
- Test: `tests/retention.bats` (create)

**Interfaces:**
- Consumes: `is_whitelisted`, `guard_reason_for_path`, `DRY`, `log_op`.
- Produces: `KEEP_N_PATHS` array (lib.sh), `keep_newest_n_children <dir> <n>` — prints newline-separated child NAMES beyond the N most-recently-modified (deletion candidates, oldest last). `MSC_DEVICE_SUPPORT_KEEP` (default 2).

- [ ] **Step 1: Write the failing tests**

`tests/retention.bats`:

```bash
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
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL — today DeviceSupport sits in `SAFE_PATHS` and is removed whole; no `keep_newest_n_children`.

- [ ] **Step 3: Implement in lib.sh**

Remove these three lines from `SAFE_PATHS` (lib.sh lines 12-14):

```bash
  "$HOME/Library/Developer/Xcode/iOS DeviceSupport"
  "$HOME/Library/Developer/Xcode/watchOS DeviceSupport"
  "$HOME/Library/Developer/Xcode/tvOS DeviceSupport"
```

Add after the `SAFE_PATHS` block:

```bash
# --- KEEP-N tier ----------------------------------------------------------
# Device symbol caches regenerate on the next device connect — but that costs
# a multi-minute re-download per OS version. Keep the N newest (you still own
# devices on those), clear the rest (mole keeps 2; same default here).
KEEP_N_PATHS=(
  "$HOME/Library/Developer/Xcode/iOS DeviceSupport"
  "$HOME/Library/Developer/Xcode/watchOS DeviceSupport"
  "$HOME/Library/Developer/Xcode/tvOS DeviceSupport"
)

# Print child NAMES of <dir> beyond the <n> most recently modified, one per
# line (they are the deletion candidates). ls -1t = newest first; version dirs
# ("17.5 (21F79)") contain spaces but never newlines.
keep_newest_n_children () {
  local dir="$1" n="$2"
  [ -d "$dir" ] || return 0
  ls -1t "$dir" 2>/dev/null | awk -v n="$n" 'NR > n'
}
```

- [ ] **Step 4: Add the section to clean-safe.sh**

After the safe-tier loop, before the tool-native section:

```bash
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
```

Note: `kept 2 newest` in the test matches this line via `kept $KEEPN newest`.

- [ ] **Step 5: Survey shows keep-N paths again**

In `survey.sh`, inside the safe-tier section after the SAFE listing (they left `SAFE_PATHS`, so they'd vanish from the survey otherwise):

```bash
collect "${KEEP_N_PATHS[@]}"
[ "${#FOUND[@]}" -gt 0 ] && du -sh "${FOUND[@]}" 2>/dev/null | sort -rh | sed 's/$/   (keeps 2 newest versions)/'
```

- [ ] **Step 6: Catalog note**

In `references/cache-catalog.md`, update the DeviceSupport row in the safe-tier table: append to its notes — `clean-safe keeps the N newest versions (MSC_DEVICE_SUPPORT_KEEP, default 2) so your current devices' symbols survive; older versions re-download on next connect of such a device.`

- [ ] **Step 7: Run all tests, commit**

```bash
bats tests/ && git add -A && git commit -m "feat: DeviceSupport keep-N retention (default 2 newest) instead of full wipe"
```

---

### Task 8: AI CLI version retention (Claude Code, Cursor Agent, Copilot CLI)

**Files:**
- Modify: `skills/mac-storage-cleaner/scripts/lib.sh` (append)
- Modify: `skills/mac-storage-cleaner/scripts/clean-safe.sh` (new section)
- Test: `tests/retention.bats` (append)

**Interfaces:**
- Consumes: `keep_newest_n_children`, `is_whitelisted`, `DRY`, `log_op`.
- Produces: `AI_AGENT_SPECS` array (`versions_root|label|active_symlink`), `resolve_active_version_dir <versions_root> <symlink>` → echoes active version child name, rc 1 on any doubt. `MSC_AI_AGENTS_KEEP` (default 1 previous version besides active).
- Safety contract (locked, mole's lesson): the active version is pinned by resolving the launcher SYMLINK, never by newest-mtime (updaters pre-download the next version, making mtime lie). Broken/missing/out-of-root symlink ⇒ skip that agent entirely.

- [ ] **Step 1: Write the failing tests**

Append to `tests/retention.bats`:

```bash
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
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL — no such functions/section.

- [ ] **Step 3: Implement in lib.sh**

```bash
# --- AI CLI version retention ---------------------------------------------
# Auto-updating AI CLIs accumulate whole old versions (hundreds of MB each).
# The ACTIVE version is pinned by resolving the launcher symlink — never by
# newest-mtime, because updaters pre-download the next version before switching
# (mole's lesson). Any doubt about which version is active => skip entirely.
AI_AGENT_SPECS=(
  "$HOME/.local/share/claude/versions|Claude Code|$HOME/.local/bin/claude"
  "$HOME/.local/share/cursor-agent/versions|Cursor Agent|$HOME/.local/bin/cursor-agent"
  "$HOME/.copilot/pkg/universal|GitHub Copilot CLI|$HOME/.local/bin/copilot"
)

# Echo the ACTIVE version dir NAME under <versions_root>, resolved from
# <symlink>. rc 1 on missing/broken/out-of-root link (caller must skip).
resolve_active_version_dir () {
  local root="$1" link="$2" target pdir
  [ -L "$link" ] || return 1
  target=$(readlink "$link") || return 1
  case "$target" in /*) ;; *) target="$(dirname "$link")/$target" ;; esac
  [ -e "$target" ] || return 1                     # dangling link: fail closed
  pdir=$(cd -P "$(dirname "$target")" 2>/dev/null && pwd -P) || return 1
  target="$pdir/$(basename "$target")"
  case "$target" in "$root"/*) ;; *) return 1 ;; esac
  local rel="${target#$root/}"
  printf '%s' "${rel%%/*}"
}
```

- [ ] **Step 4: Add the section to clean-safe.sh**

After the keep-N section:

```bash
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
```

(`ls -1t` newest-first: the first `$AIKEEP` non-active children are kept, all later ones removed — active is unconditionally kept by the `continue`.)

- [ ] **Step 5: Run all tests, commit**

```bash
bats tests/ && git add -A && git commit -m "feat: AI CLI version retention pinned to launcher symlink (claude/cursor-agent/copilot)"
```

---

### Task 9: Coverage expansion — composer/gem/conda, Handoff pasteboard, browser-frameworks report

**Files:**
- Modify: `skills/mac-storage-cleaner/scripts/lib.sh` (`SAFE_PATHS` additions)
- Modify: `skills/mac-storage-cleaner/scripts/clean-safe.sh` (conda tool-native + Handoff section)
- Modify: `skills/mac-storage-cleaner/scripts/find-extras.sh` (browser-frameworks section)
- Modify: `skills/mac-storage-cleaner/references/cache-catalog.md` (rows for all of the above)
- Test: `tests/clean_safe.bats` (append)

**Interfaces:**
- Consumes: `DRY`, `is_whitelisted`, `log_op`, `human_kb`, `size_kb`.
- Locked decisions: Handoff pasteboard cleans only items **older than 60 minutes** (an in-flight Universal Clipboard sync must never be cut — mole #1178). Browser frameworks are **report-only** in find-extras (they live inside .app bundles: TCC App Management can block, and the browser must be quit — the agent proposes, the user picks, trash-items removes). Conda goes through its **owner command** only (`conda clean`), never raw rm — pkgs are hardlinked into live envs.

- [ ] **Step 1: Write the failing tests**

Append to `tests/clean_safe.bats`:

```bash
@test "composer and gem caches are cleared" {
  mkdir -p "$HOME/Library/Caches/composer/files" "$HOME/.composer/cache/repo" \
           "$HOME/.gem/ruby/3.3.0/cache"
  touch "$HOME/.gem/ruby/3.3.0/cache/foo-1.0.gem"
  run bash "$SCRIPTS/clean-safe.sh"
  [ ! -e "$HOME/Library/Caches/composer" ]
  [ ! -e "$HOME/.composer/cache" ]
  [ ! -e "$HOME/.gem/ruby/3.3.0/cache" ]
}

@test "Handoff pasteboard: only items older than 60 minutes go" {
  PB="$HOME/Library/Group Containers/group.com.apple.coreservices.useractivityd/shared-pasteboard"
  mkdir -p "$PB/old-item" "$PB/fresh-item"
  touch -t "$(date -v-2H +%Y%m%d%H%M)" "$PB/old-item"
  run bash "$SCRIPTS/clean-safe.sh"
  [ ! -e "$PB/old-item" ]
  [ -d "$PB/fresh-item" ]
}

@test "conda cleanup runs the owner command, never rm" {
  make_stub conda 0
  mkdir -p "$HOME/miniconda3/pkgs/somepkg"
  run bash "$SCRIPTS/clean-safe.sh"
  [[ "$output" == *"conda clean"* ]]
  [ -d "$HOME/miniconda3/pkgs/somepkg" ]   # rm never touches pkgs
}
```

- [ ] **Step 2: Run to verify failure**

Expected: FAIL on all three.

- [ ] **Step 3: Implement**

`lib.sh` — append to `SAFE_PATHS` (inside the array, after the Python block):

```bash
  # PHP / Ruby
  "$HOME/Library/Caches/composer"
  "$HOME/.composer/cache"
  "$HOME/.gem/ruby/*/cache"
```

`clean-safe.sh` — in the tool-native section, after brew:

```bash
# conda: owner command only — pkgs/ is hardlinked into live envs, raw rm breaks them.
if command -v conda >/dev/null 2>&1; then
  if [ "$DRY" = 1 ]; then echo "  would run: conda clean -y --tarballs --index-cache --logfiles"
  elif conda clean -y --tarballs --index-cache --logfiles >/dev/null 2>&1; then
    echo "  done: conda clean"; log_op cleaned "conda caches" "conda clean -y --tarballs --index-cache --logfiles"
  fi
fi
```

`clean-safe.sh` — new section after the AI-agents section:

```bash
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
```

`find-extras.sh` — new section before "Stale installers":

```bash
echo "===== Browser old-version frameworks (quit the browser, keep Current) ====="
echo "Chromium browsers leave whole previous versions inside the .app bundle."
echo "Safe to Trash every version EXCEPT the one 'Current' points to. Report-only:"
for fw in \
  "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions" \
  "/Applications/Microsoft Edge.app/Contents/Frameworks/Microsoft Edge Framework.framework/Versions" \
  "/Applications/Brave Browser.app/Contents/Frameworks/Brave Browser Framework.framework/Versions"; do
  [ -d "$fw" ] || continue
  cur=$(readlink "$fw/Current" 2>/dev/null)
  cur=$(basename "${cur:-none}")
  for v in "$fw"/*; do
    [ -d "$v" ] || continue
    name=$(basename "$v")
    [ "$name" = "Current" ] && continue
    if [ "$name" = "$cur" ]; then
      printf '  %s\t%s   (Current — KEEP)\n' "$(human_kb "$(size_kb "$v")")" "$v"
    else
      printf '  %s\t%s\n' "$(human_kb "$(size_kb "$v")")" "$v"
    fi
  done
done
echo "  (if empty: no multi-version browser frameworks found)"
echo
```

`references/cache-catalog.md` — add safe-tier rows: `~/Library/Caches/composer` + `~/.composer/cache` (Composer re-downloads packages), `~/.gem/ruby/*/cache` (downloaded .gem archives; installed gems live in `gems/`, untouched); ask-tier note: conda via `conda clean -y --tarballs --index-cache --logfiles` only (pkgs/ hardlinked into envs — never rm); safe-tier age-gated row: Handoff shared-pasteboard (60-min age gate, mole #1178); ask-tier row: browser framework old versions (report-only; quit browser; TCC App Management may require Finder).

- [ ] **Step 4: Run all tests, commit**

```bash
bats tests/ && git add -A && git commit -m "feat: composer/gem/conda coverage, Handoff pasteboard (60min gate), browser-frameworks report"
```

---

### Task 10: SKILL.md update, full-suite pass, sync to installed skill

**Files:**
- Modify: `skills/mac-storage-cleaner/SKILL.md`
- Sync: `~/.claude/skills/mac-storage-cleaner/`

- [ ] **Step 1: Update SKILL.md**

Edits (keep the existing structure and tone):
1. **Workflow step 2** — after the clean-safe command block, add: `To preview first (recommended when the user hesitates or asks what will go): add --dry-run — full preview with sizes, zero deletion, zero log writes. Guards and whitelist run identically in both modes, so the preview always matches reality.`
2. **Workflow step 2** — add: `The safe tier now keeps the 2 newest DeviceSupport versions (MSC_DEVICE_SUPPORT_KEEP), keeps the active + 1 previous version of auto-updating AI CLIs (claude / cursor-agent / copilot, pinned via their launcher symlink), and skips any path whose owning process is running (Xcode family, Gradle daemon) — report skipped items to the user instead of retrying.`
3. **New subsection "User whitelist"** under Workflow: `~/.config/mac-storage-cleaner/whitelist — one path or glob per line, # comments, ~/ expansion; protects the entry and everything under it in every mode. When the user says "always keep X", add a line here (and tell them where it lives) instead of relying on memory.`
4. **Trash paragraph** (step 4) — replace the TCC-only guidance with: `trash-items.sh now tries /usr/bin/trash first (no TCC prompt, works headless), then Finder (needs the Automation grant — System Settings › Privacy & Security › Automation), then a same-volume mv into ~/.Trash. The log records which method moved each item; refused entries mean the path is on the tool's deny list (system/user roots) — never work around a refusal.`
5. **Safety rules** — add bullet: `Handoff shared-pasteboard buffers are cleared only when untouched for 60+ minutes — never delete fresher ones, an in-flight Universal Clipboard sync may be using them.`
6. **New final section "Tests"**: `bats tests/ from the repo root (brew install bats-core). Every test runs against a fake $HOME; the dangerous-path corpus in tests/fixtures/ is a floor — investigate a failure, never weaken the corpus.`

- [ ] **Step 2: Full suite + shellcheck pass**

```bash
cd ~/Desktop/Projects/mac-storage-cleaner
bats tests/
command -v shellcheck >/dev/null && shellcheck skills/mac-storage-cleaner/scripts/*.sh || true
```
Expected: all tests PASS; fix any shellcheck finding that is a real bug (style-only findings may be skipped — note them in the commit message if so).

- [ ] **Step 3: Real-machine smoke test (this Mac, non-destructive)**

```bash
bash skills/mac-storage-cleaner/scripts/survey.sh | head -30
bash skills/mac-storage-cleaner/scripts/clean-safe.sh --dry-run
```
Expected: survey shows DeviceSupport with the keep-note; dry-run lists real caches as "would remove", deletes nothing (`df` before/after identical).

- [ ] **Step 4: Sync to the installed skill**

```bash
rsync -a --delete \
  ~/Desktop/Projects/mac-storage-cleaner/skills/mac-storage-cleaner/ \
  ~/.claude/skills/mac-storage-cleaner/
diff -rq ~/Desktop/Projects/mac-storage-cleaner/skills/mac-storage-cleaner ~/.claude/skills/mac-storage-cleaner
```
Expected: diff silent.

- [ ] **Step 5: Final commit**

```bash
git add -A && git commit -m "docs: SKILL.md for dry-run, whitelist, keep-N, guards, trash chain; sync installed skill"
```

---

## Self-Review (completed at plan time)

1. **Spec coverage:** all 7 approved items have tasks — tests (1), validation+corpus (2), trash chain (3), whitelist (4), dry-run (5), process guards (6), DeviceSupport keep-N (7), AI CLI retention (8), coverage expansion (9), docs+sync (10). ✔
2. **Placeholder scan:** every code step carries the actual code; no TBDs. ✔
3. **Type consistency:** `TRASH_METHOD`/rc-2 contract (T3) matches trash-items.sh usage; `guard_reason_for_path` (T6) reused verbatim in T7; `keep_newest_n_children` (T7) signature matches T7 caller; `DRY`/`MSC_DRY_RUN` naming uniform across T5-T9; `is_whitelisted` uniform across T4-T9. ✔
4. **Known ordering hazards encoded:** whitelist → guard → dry-run → rm order stated in T5/T6 and tested ("guard runs before the dry-run gate"); empty-child collapse guarded in T7/T8 loops; lib.sh sources after fake-HOME export in all tests. ✔
