# Cross-Agent Distribution Implementation Plan (v3.0.0)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `mac-storage-cleaner` actually run — not merely appear — on every major AI coding agent, and make its destructive default safe on agents that execute shell commands without asking.

**Architecture:** Three code changes carry the release: a portable skill-directory resolver in every SKILL.md command block (the skill currently only finds itself under `~/.claude/skills`), an inverted CLI default (`clean-safe.sh` previews unless `--apply`), and a blast-radius cap on `trash-items.sh`. Everything else — manifests, docs, CI, compat matrix — supports those three. Registry publications happen last, after manual per-agent verification.

**Tech Stack:** bash 3.2 (macOS stock), bats-core, GitHub Actions on `macos-latest`, shellcheck.

**Spec:** `docs/superpowers/specs/2026-08-14-cross-agent-distribution-design.md`

## Global Constraints

- **bash 3.2 compatible** — no `declare -A`, no extglob, no `readarray`, no `${var,,}`. Under `set -u`, expanding an EMPTY array with `"${arr[@]}"` crashes bash 3.2 — always guard with `[ "${#arr[@]}" -gt 0 ]` first.
- **`set -u` in every executable script**; `lib.sh` stays side-effect-free on source.
- **Source of truth:** `~/Desktop/Projects/mac-storage-cleaner` (branch `main`). The installed copy at `~/.claude/skills/mac-storage-cleaner/` is synced with `rsync -a --delete` at the end of each task that changes the skill folder.
- **NEVER execute `clean-safe.sh` or `trash-items.sh` outside (a) `bats tests/` or (b) a SINGLE command with an inline `env HOME="$FAKE" …` prefix against a verified `mktemp -d` directory, with `brew`/`xcode-select`/`pgrep`/`conda`/`ps` stubbed on `PATH`.** Three agents violated this during the previous release; one deleted the user's real caches.
- **Env-var prefix `MSC_`**. New in this release: `MSC_MAX_TRASH_ITEMS` (default `100`), `MSC_MAX_TRASH_GB` (default `5`).
- **`MSC_DRY_RUN=1` may only ever make a run safer** — it overrides `--apply`, never the reverse.
- **Every destructive action still logs via `log_op <action> <size> <path>`**; `log_op` no-ops when `MSC_DRY_RUN=1`.
- **Skill folder name and frontmatter `name` must both stay `mac-storage-cleaner`** — the resolver, manifests and every registry key on it.
- Commit after each task. Do not push and do not tag until Task 8.

## File Structure

```
.github/workflows/ci.yml                       # Create (T1)
skills/mac-storage-cleaner/SKILL.md            # Modify (T2 resolver, T3 --apply, T5 frontmatter, T7 docs)
skills/mac-storage-cleaner/scripts/clean-safe.sh   # Modify (T3)
skills/mac-storage-cleaner/scripts/trash-items.sh  # Modify (T4)
skills/mac-storage-cleaner/agents/openai.yaml  # Create (T6)
.cursor-plugin/plugin.json                     # Create (T6)
tools/bump-version.sh                          # Create (T6) — repo tooling, not shipped in the skill
tests/resolve.bats                             # Create (T2)
tests/apply_gate.bats                          # Create (T3)
tests/blast_radius.bats                        # Create (T4)
tests/frontmatter.bats                         # Create (T5)
tests/manifests.bats                           # Create (T6)
docs/compat/<agent>.md                         # Create (T8)
README.md, CHANGELOG.md                        # Modify (T7)
```

---

### Task 1: CI on macos-latest

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: a CI job named `test` that runs `bats tests/` and `shellcheck` on every push and PR. Later tasks add `.bats` files; CI picks them up automatically because it runs the whole directory.

- [ ] **Step 1: Confirm the suite is green locally before wiring CI**

Run: `cd ~/Desktop/Projects/mac-storage-cleaner && bats tests/`
Expected: `89 tests, 0 failures`. If it is not green, STOP and report — CI must codify a passing state, not a broken one.

- [ ] **Step 2: Write the workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install bats-core and shellcheck
        run: brew install bats-core shellcheck

      - name: Run the test suite
        run: bats tests/

      - name: ShellCheck the skill's scripts
        # SC1091: shellcheck cannot follow the runtime-resolved `. "$DIR/lib.sh"` source.
        run: shellcheck -e SC1091 skills/mac-storage-cleaner/scripts/*.sh
```

- [ ] **Step 3: Verify the shellcheck invocation passes locally first**

Run: `cd ~/Desktop/Projects/mac-storage-cleaner && shellcheck -e SC1091 skills/mac-storage-cleaner/scripts/*.sh; echo "exit=$?"`
Expected: `exit=0`. If shellcheck is not installed: `brew install shellcheck`. If it reports real findings, fix them in this task (they would fail CI otherwise) and note each fix in the commit message.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: run bats and shellcheck on macos-latest"
```

---

### Task 2: Portable skill-directory resolver

**Files:**
- Modify: `skills/mac-storage-cleaner/SKILL.md` (the 4 command blocks at lines 41, 55, 112, 122, and the "Locating the scripts" paragraph at lines 33-36)
- Create: `tests/resolve.bats`

**Interfaces:**
- Produces: the canonical two-line resolver snippet below. Task 3 and Task 7 edit the same command blocks and must keep the snippet **byte-identical across all four blocks** — `tests/resolve.bats` enforces that.

**Why:** `~/.claude/skills` is currently the only fallback. Installed to `~/.cursor/skills`, `~/.codex/skills`, `~/.config/opencode/skills`, a Hermes tap, or a project-scoped `.claude/skills`, every command fails with *No such file or directory*.

- [ ] **Step 1: Write the failing tests**

Create `tests/resolve.bats`:

```bash
#!/usr/bin/env bats
load test_helper

SKILL_MD="$BATS_TEST_DIRNAME/../skills/mac-storage-cleaner/SKILL.md"

setup ()    { setup_fake_home; }
teardown () { teardown_fake_home; }

# The resolver is two consecutive lines: the `D=""; for r in …` loop and the
# `[ -n "$D" ] || { … }` guard. Extract the first occurrence.
resolver_snippet () {
  awk '/^D=""; for r in /{print; getline; print; exit}' "$SKILL_MD"
}

@test "SKILL.md has exactly four command blocks and one identical resolver" {
  local n uniq
  n=$(grep -c '^D=""; for r in ' "$SKILL_MD")
  [ "$n" -eq 4 ] || { echo "expected 4 resolver lines, found $n"; false; }
  uniq=$(grep '^D=""; for r in ' "$SKILL_MD" | sort -u | wc -l | tr -d ' ')
  [ "$uniq" -eq 1 ] || { echo "the four resolver lines are not identical"; false; }
}

@test "resolver finds the skill in every documented global root" {
  local rel root
  for rel in ".claude/skills" ".agents/skills" ".cursor/skills" ".codex/skills" \
             ".config/opencode/skills" ".gemini/config/skills" \
             ".gemini/antigravity/skills" ".codeium/windsurf/skills" ".hermes/skills"; do
    root="$HOME/$rel/mac-storage-cleaner"
    mkdir -p "$root/scripts"
    : > "$root/scripts/lib.sh"
    run bash -c "$(resolver_snippet); printf '%s' \"\$D\""
    [ "$status" -eq 0 ] || { echo "resolver exited $status for $rel"; false; }
    [ "$output" = "$root" ] || { echo "for $rel got '$output', wanted '$root'"; false; }
    rm -rf "$HOME/${rel%%/*}"
  done
}

@test "resolver finds a project-scoped install" {
  local proj="$HOME/proj"
  mkdir -p "$proj/.agents/skills/mac-storage-cleaner/scripts"
  : > "$proj/.agents/skills/mac-storage-cleaner/scripts/lib.sh"
  run bash -c "cd '$proj' && $(resolver_snippet) && printf '%s' \"\$D\""
  [ "$status" -eq 0 ]
  [ "$output" = ".agents/skills/mac-storage-cleaner" ]
}

@test "resolver honours CLAUDE_PLUGIN_ROOT ahead of everything else" {
  local pr="$HOME/plugin-root"
  mkdir -p "$pr/skills/mac-storage-cleaner/scripts" "$HOME/.claude/skills/mac-storage-cleaner/scripts"
  : > "$pr/skills/mac-storage-cleaner/scripts/lib.sh"
  : > "$HOME/.claude/skills/mac-storage-cleaner/scripts/lib.sh"
  run bash -c "export CLAUDE_PLUGIN_ROOT='$pr'; $(resolver_snippet); printf '%s' \"\$D\""
  [ "$output" = "$pr/skills/mac-storage-cleaner" ]
}

@test "resolver fails loudly, not silently, when the skill is nowhere" {
  run bash -c "$(resolver_snippet); printf '%s' \"\$D\""
  [ "$status" -ne 0 ] || { echo "resolver exited 0 with no skill installed"; false; }
  [[ "$output" == *"not found in any standard skill root"* ]] || false
}

@test "every bash block in SKILL.md is syntactically valid" {
  local tmp="$BATS_TEST_TMPDIR/blocks" b count=0
  mkdir -p "$tmp"
  awk -v out="$tmp" 'BEGIN{n=0}
    /^```bash$/ {n++; f=1; next}
    /^```$/     {f=0; next}
    f           {print >> (out "/b" n ".sh")}' "$SKILL_MD"
  for b in "$tmp"/b*.sh; do
    [ -f "$b" ] || continue
    count=$((count + 1))
    run /bin/bash -n "$b"
    [ "$status" -eq 0 ] || { echo "bash -n failed for $b"; false; }
  done
  [ "$count" -ge 4 ] || { echo "expected >=4 bash blocks, found $count"; false; }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/resolve.bats`
Expected: FAIL — `expected 4 resolver lines, found 0` (SKILL.md still uses the old `D="${CLAUDE_PLUGIN_ROOT:+…}"` form).

- [ ] **Step 3: Replace all four command blocks in SKILL.md**

In each of the four ```bash blocks, replace the single `D=…` line with these two lines (byte-identical in all four):

```bash
D=""; for r in "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/skills" "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.cursor/skills" "$HOME/.codex/skills" "$HOME/.config/opencode/skills" "$HOME/.gemini/config/skills" "$HOME/.gemini/antigravity/skills" "$HOME/.codeium/windsurf/skills" "$HOME/.hermes/skills" ".claude/skills" ".agents/skills" ".cursor/skills" ".windsurf/skills"; do [ -f "$r/mac-storage-cleaner/scripts/lib.sh" ] && { D="$r/mac-storage-cleaner"; break; }; done
[ -n "$D" ] || { echo "mac-storage-cleaner: not found in any standard skill root (looked under CLAUDE_PLUGIN_ROOT and ~/.claude, ~/.agents, ~/.cursor, ~/.codex, ~/.config/opencode, ~/.gemini, ~/.codeium/windsurf, ~/.hermes, plus ./.claude|.agents|.cursor|.windsurf)"; exit 1; }
```

`${CLAUDE_PLUGIN_ROOT:-/nonexistent}` keeps the loop a single expression under `set -u` while making the unset case unmatchable.

- [ ] **Step 4: Replace the "Locating the scripts" paragraph (SKILL.md lines 33-36)**

```markdown
**Locating the scripts.** Each command block below starts by resolving `$D` to
this skill's own directory. It searches every standard agent skill root —
Claude Code, Codex, Cursor, opencode, Antigravity, Windsurf, Hermes, the
cross-agent `.agents/skills`, and project-scoped installs — so the commands work
no matter which agent installed the skill or where. Shell state doesn't persist
between commands, so every block re-resolves `$D`; keep the two lines byte-identical
when editing (a test enforces it).
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats tests/resolve.bats && bats tests/`
Expected: `resolve.bats` 6/6 pass; the full suite passes (95 tests).

- [ ] **Step 6: Sync and commit**

```bash
rsync -a --delete ~/Desktop/Projects/mac-storage-cleaner/skills/mac-storage-cleaner/ ~/.claude/skills/mac-storage-cleaner/
diff -rq ~/Desktop/Projects/mac-storage-cleaner/skills/mac-storage-cleaner ~/.claude/skills/mac-storage-cleaner
git add skills/mac-storage-cleaner/SKILL.md tests/resolve.bats
git commit -m "fix: resolve the skill directory across every agent install root

Previously only ~/.claude/skills was searched, so an install into Cursor,
Codex, opencode, Antigravity, Windsurf, Hermes or a project-scoped root
made every command fail with 'No such file or directory'."
```

---

### Task 3: Safe by default — `clean-safe.sh` previews unless `--apply`

**Files:**
- Modify: `skills/mac-storage-cleaner/scripts/clean-safe.sh` (argument parsing at lines 12-20; the summary line containing `run without --dry-run to apply`)
- Modify: `skills/mac-storage-cleaner/SKILL.md` (section 2 command block and the paragraph beginning "To preview first")
- Modify: existing tests that assume deletion is the default
- Create: `tests/apply_gate.bats`

**Interfaces:**
- Consumes: the Task 2 resolver (SKILL.md block for section 2 gains `--apply`).
- Produces: CLI contract — no argument or `--dry-run` = preview, exit 0, nothing deleted; `--apply` = delete; any other argument = exit 2; `MSC_DRY_RUN=1` forces preview even with `--apply`. A real (applying) run writes `log_op consent "-" "--apply"` as its first log line.

**Why:** opencode defaults to allow-bash with no prompts and OpenClaw defaults to `security="full", ask="off"`. On those agents today, the obvious invocation deletes caches the user never saw proposed. A prose rule cannot fix that; a default can.

- [ ] **Step 1: Write the failing tests**

Create `tests/apply_gate.bats`:

```bash
#!/usr/bin/env bats
load test_helper

setup () {
  setup_fake_home
  make_stub brew 1
  make_stub xcode-select 1
  make_stub pgrep 1
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

@test "the preview summary tells the user how to actually apply" {
  run bash "$SCRIPTS/clean-safe.sh"
  [[ "$output" == *"--apply"* ]] || false
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/apply_gate.bats`
Expected: FAIL — the no-argument run currently deletes `$HOME/.npm/junk` and `--apply` is rejected as an unknown argument.

- [ ] **Step 3: Replace the argument parsing in `clean-safe.sh`**

Replace the block that currently reads (lines 12-20, from the `# Reject anything other than --dry-run` comment through the `[ "$DRY" = 1 ] && echo "=== DRY RUN …"` line) with:

```bash
# Safe by default (v3.0.0): no argument previews. Deleting requires --apply.
# Rationale: several agents (opencode, OpenClaw) execute shell commands with no
# approval prompt at all, so a destructive default means an agent can delete
# caches the user never saw proposed. --dry-run is still accepted as a no-op
# alias, because it is what the previous docs, the aitmpl copy and muscle memory
# use. An unrecognized argument still exits 2 rather than failing open.
APPLY=0
case "${1:-}" in
  "")        ;;
  --apply)   APPLY=1 ;;
  --dry-run) ;;
  *) echo "unknown argument: $1 (use --apply to delete; no argument or --dry-run previews)"; exit 2 ;;
esac
DRY=1
[ "$APPLY" = 1 ] && DRY=0
# MSC_DRY_RUN may only ever make a run safer, so it overrides --apply.
[ "${MSC_DRY_RUN:-0}" = "1" ] && DRY=1
export MSC_DRY_RUN="$DRY"
if [ "$DRY" = 1 ]; then
  echo "=== PREVIEW — nothing will be deleted (re-run with --apply to delete) ==="
else
  log_op consent "-" "--apply"
fi
```

`log_op` is already sourced from `lib.sh` above this point; no other ordering changes.

- [ ] **Step 4: Update the preview summary line**

Find the line reading:

```bash
  echo "Would reclaim from cache deletions: $(human_kb "$total_kb") — run without --dry-run to apply."
```

Replace with:

```bash
  echo "Would reclaim from cache deletions: $(human_kb "$total_kb") — re-run with --apply to delete."
```

- [ ] **Step 5: Update every existing test that expected deletion by default**

Run: `grep -rn 'clean-safe\.sh"$\|clean-safe\.sh$' tests/*.bats`
For each invocation whose assertions expect deletion (a `[ ! -e … ]` or a `grep removed …log` afterwards), append ` --apply`. Leave invocations that assert preview/skip behavior unchanged — they already exercise the new default. Do not change `tests/apply_gate.bats`.

- [ ] **Step 6: Update SKILL.md section 2**

In the section-2 command block, change the invocation line to:

```bash
bash "$D/scripts/clean-safe.sh" --apply
```

Replace the paragraph beginning "To preview first" with:

```markdown
**Preview is the default.** Running `clean-safe.sh` with no argument previews
everything with sizes and deletes nothing; `--apply` performs the deletion.
Guards and the whitelist run identically in both modes, so the preview always
matches reality. Show the user the preview before you run `--apply` — and always
do so on agents that execute shell commands without asking them first (opencode,
OpenClaw and anything configured to auto-run). `MSC_DRY_RUN=1` forces preview
even when `--apply` is passed.
```

- [ ] **Step 7: Run the whole suite**

Run: `bats tests/`
Expected: all pass (101 tests). Every failure here is a test that assumed the old default — fix it per Step 5, not by weakening `apply_gate.bats`.

- [ ] **Step 8: Sync and commit**

```bash
rsync -a --delete ~/Desktop/Projects/mac-storage-cleaner/skills/mac-storage-cleaner/ ~/.claude/skills/mac-storage-cleaner/
git add -A
git commit -m "feat!: clean-safe.sh previews by default; deleting requires --apply

BREAKING CHANGE: 'clean-safe.sh' with no argument no longer deletes. Agents
that run shell commands without an approval prompt can no longer delete
caches the user never saw proposed. --dry-run remains accepted as an alias
and MSC_DRY_RUN=1 overrides --apply."
```

---

### Task 4: Blast-radius cap on `trash-items.sh`

**Files:**
- Modify: `skills/mac-storage-cleaner/scripts/trash-items.sh` (usage/exit-code header lines 1-11; the argument check at line 16; insert the cap before the main loop at line 45)
- Create: `tests/blast_radius.bats`

**Interfaces:**
- Consumes: `validate_target_path`, `size_kb`, `human_kb`, `log_op` from `lib.sh` (unchanged).
- Produces: `trash-items.sh [--force] <path>…`. New exit code **4** = refused as a bulk operation. Limits: `MSC_MAX_TRASH_ITEMS` (default 100), `MSC_MAX_TRASH_GB` (default 5). Counted over *eligible* paths only — missing and protected-refused paths never count toward the cap.

**Why:** `trash-items.sh` takes arbitrary argv. It is the one surface where an unsupervised agent assembling a "big old files" list can move hundreds of a user's files in a single call.

- [ ] **Step 1: Write the failing tests**

Create `tests/blast_radius.bats`:

```bash
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
  for i in $(seq 1 99); do
    : > "$HOME/junk/g$i"
    paths+=("$HOME/junk/g$i")
  done
  # 99 eligible + one refused root + one missing path = under the cap of 100.
  run bash "$SCRIPTS/trash-items.sh" "${paths[@]}" "$HOME/Library" "$HOME/nope"
  [ "$status" -ne 4 ] || { echo "ineligible paths were counted toward the cap"; false; }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/blast_radius.bats`
Expected: FAIL — 101 items are trashed today and `--force` is treated as a path (`not found: --force`).

- [ ] **Step 3: Add `--force` parsing**

In `trash-items.sh`, immediately after `. "$DIR/lib.sh"` (line 14), insert:

```bash
# --force must be the first argument. It only ever relaxes the bulk-operation
# cap below; it does not bypass path validation or the never-tier denials.
FORCE=0
[ "${1:-}" = "--force" ] && { FORCE=1; shift; }
```

Then update the empty-argument check on the following line to mention the flag:

```bash
[ "$#" -eq 0 ] && { echo "usage: trash-items.sh [--force] <path> [<path> ...]  (exit 0=ok/previewed/missing-only, 1=a trash failed, 2=all refused & nothing moved/previewed, 3=audit log unwritable, 4=refused as a bulk operation)"; exit 1; }
```

- [ ] **Step 4: Add the cap, immediately before the `for p in "$@"; do` main loop**

```bash
# Blast-radius cap. Some agents (opencode, OpenClaw) run shell commands with no
# approval prompt, so a single call assembling "all my old downloads" could move
# hundreds of a user's files at once. Count only ELIGIBLE paths — missing and
# protected-refused paths are not the user's data leaving its place. One `du -sck`
# gives the grand total in a single walk.
MAX_ITEMS="${MSC_MAX_TRASH_ITEMS:-100}"
MAX_GB="${MSC_MAX_TRASH_GB:-5}"
case "$MAX_ITEMS" in ''|*[!0-9]*) MAX_ITEMS=100 ;; esac
case "$MAX_GB"    in ''|*[!0-9]*) MAX_GB=5 ;; esac
eligible_n=0
eligible=()
for p in "$@"; do
  { [ -e "$p" ] || [ -L "$p" ]; } || continue
  validate_target_path "$p" || continue
  eligible+=("$p")
  eligible_n=$((eligible_n + 1))
done
bulk_kb=0
if [ "$eligible_n" -gt 0 ]; then
  bulk_kb=$(du -sck "${eligible[@]}" 2>/dev/null | tail -1 | awk '{print $1}')
  case "$bulk_kb" in ''|*[!0-9]*) bulk_kb=0 ;; esac
fi
if [ "$FORCE" != 1 ] && { [ "$eligible_n" -gt "$MAX_ITEMS" ] || [ "$bulk_kb" -gt $((MAX_GB * 1024 * 1024)) ]; }; then
  echo "✗ Refusing a bulk operation: $eligible_n item(s), $(human_kb "$bulk_kb") (limits: $MAX_ITEMS items, ${MAX_GB}GB)."
  echo "  This guard exists because some agents run shell commands without asking you first."
  echo "  Review the list, then re-run the same command with --force as the first argument."
  log_op refused-blast-radius "$(human_kb "$bulk_kb")" "$eligible_n item(s)"
  exit 4
fi
```

The `eligible+=(…)` growth and the `[ "$eligible_n" -gt 0 ]` guard before `"${eligible[@]}"` are required for bash 3.2 under `set -u`.

- [ ] **Step 5: Update the exit-code comment block at the top of the file**

Add to the header comment (lines 6-11) and to the trailing exit-code comment: `4 = refused as a bulk operation (see MSC_MAX_TRASH_ITEMS / MSC_MAX_TRASH_GB and --force)`.

- [ ] **Step 6: Run the tests**

Run: `bats tests/blast_radius.bats && bats tests/`
Expected: `blast_radius.bats` 5/5 pass; full suite green (106 tests).

- [ ] **Step 7: Sync and commit**

```bash
rsync -a --delete ~/Desktop/Projects/mac-storage-cleaner/skills/mac-storage-cleaner/ ~/.claude/skills/mac-storage-cleaner/
git add -A
git commit -m "feat: refuse bulk trash operations without --force

100 items or 5GB by default (MSC_MAX_TRASH_ITEMS / MSC_MAX_TRASH_GB).
Counts only eligible paths, so missing and protected-refused entries never
push a legitimate batch over the limit."
```

---

### Task 5: Frontmatter harmonization + byte-budget test

**Files:**
- Modify: `skills/mac-storage-cleaner/SKILL.md` (frontmatter, lines 1-4)
- Create: `tests/frontmatter.bats`

**Interfaces:**
- Produces: frontmatter carrying `name`, `description`, `license`, and a flat string-valued `metadata:` map including `version`. Task 6's parity test reads `metadata.version` from this file with:
  `awk '/^metadata:/{m=1;next} m&&/^[a-z]/{m=0} m&&/^  version:/{print $2}' SKILL.md`

**Why:** Hermes requires `version`/`author`/`license`; Cursor's documented schema does not include them, and an unknown top-level key fails validation rather than degrading. `metadata:` is documented by Cursor and ignored by everything else, so it is the safe carrier. opencode requires `description` ≤ 1024 **bytes** — the current description is 872 characters but **972 bytes**, leaving 52 bytes of headroom.

- [ ] **Step 1: Write the failing tests**

Create `tests/frontmatter.bats`:

```bash
#!/usr/bin/env bats

SKILL_MD="$BATS_TEST_DIRNAME/../skills/mac-storage-cleaner/SKILL.md"

fm () {  # print the YAML frontmatter block
  awk 'NR==1 && $0=="---" {inb=1; next} inb && $0=="---" {exit} inb {print}' "$SKILL_MD"
}

@test "name matches the strictest agent regex and the folder name" {
  local name
  name=$(fm | awk '/^name:/{print $2}')
  [ "$name" = "mac-storage-cleaner" ]
  [ -d "$BATS_TEST_DIRNAME/../skills/$name" ]
  echo "$name" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'
}

@test "description fits opencode's 1024-BYTE limit with headroom" {
  local bytes
  bytes=$(fm | awk '/^description:/{sub(/^description: /,""); print}' | tr -d '\n' | wc -c | tr -d ' ')
  [ "$bytes" -le 1000 ] || { echo "description is $bytes bytes; budget is 1000 (hard limit 1024)"; false; }
  [ "$bytes" -gt 200 ] || { echo "description collapsed to $bytes bytes — trigger coverage lost"; false; }
}

@test "required and portable keys are present" {
  fm | grep -q '^name:'
  fm | grep -q '^description:'
  fm | grep -q '^license: MIT$'
  fm | grep -q '^metadata:'
}

@test "every metadata value is a scalar string — opencode rejects nested maps" {
  local body
  body=$(fm | awk '/^metadata:/{m=1;next} m&&/^[a-z]/{m=0} m{print}')
  [ -n "$body" ]
  # every metadata line must be exactly "  key: value" with a non-empty value
  echo "$body" | grep -vqE '^  [a-z][a-z0-9-]*: .+$' && { echo "non-scalar metadata line:"; echo "$body"; false; }
  echo "$body" | grep -q '^  version: '
}

@test "the frontmatter is valid YAML" {
  if ! command -v ruby >/dev/null 2>&1; then skip "ruby not available"; fi
  fm > "$BATS_TEST_TMPDIR/fm.yaml"
  run ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$BATS_TEST_TMPDIR/fm.yaml"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/frontmatter.bats`
Expected: FAIL on the `license`/`metadata` assertions — the frontmatter currently has only `name` and `description`.

- [ ] **Step 3: Replace the frontmatter**

Keep line 3 (`description:`) **exactly as it is** — it is byte-budgeted and trigger-tuned. Add the new keys around it:

```yaml
---
name: mac-storage-cleaner
description: <UNCHANGED — do not retype this line, leave the existing one in place>
license: MIT
metadata:
  version: 3.0.0
  author: Juba Kitiashvili
  homepage: https://github.com/JubaKitiashvili/mac-storage-cleaner
  platforms: macOS
  category: productivity
  tags: macos, disk-space, cache, cleanup, storage, cleanmymac-alternative
---
```

- [ ] **Step 4: Run the tests**

Run: `bats tests/frontmatter.bats && bats tests/`
Expected: `frontmatter.bats` 5/5 pass (or 4 pass + 1 skip if ruby is missing); full suite green (111 tests).

- [ ] **Step 5: Verification spike — confirm the frontmatter loads on locally installed agents**

For each of Cursor, Codex CLI and opencode that is actually installed on this machine, copy the skill into that agent's global skills root and confirm it loads (the agent lists it, or a probe prompt surfaces it). Record the result — agent, version, loaded yes/no — in the commit message. For any agent not installed locally, write `not installed locally — unverified`.

If an agent **rejects** the skill because of the new keys, remove only the offending key and re-run; do not move `version` to the top level.

```bash
mkdir -p ~/.cursor/skills && rsync -a ~/Desktop/Projects/mac-storage-cleaner/skills/mac-storage-cleaner/ ~/.cursor/skills/mac-storage-cleaner/
mkdir -p ~/.codex/skills  && rsync -a ~/Desktop/Projects/mac-storage-cleaner/skills/mac-storage-cleaner/ ~/.codex/skills/mac-storage-cleaner/
```

- [ ] **Step 6: Sync and commit**

```bash
rsync -a --delete ~/Desktop/Projects/mac-storage-cleaner/skills/mac-storage-cleaner/ ~/.claude/skills/mac-storage-cleaner/
git add -A
git commit -m "feat: portable frontmatter (license + string-valued metadata) with a byte-budget test

Risky keys live under metadata:, which Cursor documents and other agents
ignore. The description is asserted in BYTES (972/1024 today) because the
Georgian trigger phrases cost 3 bytes per glyph.

Spike results: <fill in per agent>"
```

---

### Task 6: Agent manifests, version parity, bump tooling

**Files:**
- Create: `skills/mac-storage-cleaner/agents/openai.yaml`
- Create: `.cursor-plugin/plugin.json`
- Create: `tools/bump-version.sh`
- Create: `tests/manifests.bats`

**Interfaces:**
- Consumes: `metadata.version` from SKILL.md (Task 5).
- Produces: `tools/bump-version.sh <semver>` rewrites the version in all five locations. `tests/manifests.bats` fails the build if any drift.

- [ ] **Step 1: Write the failing tests**

Create `tests/manifests.bats`:

```bash
#!/usr/bin/env bats

ROOT="$BATS_TEST_DIRNAME/.."

skill_version () {
  awk '/^metadata:/{m=1;next} m&&/^[a-z]/{m=0} m&&/^  version:/{print $2}' "$ROOT/skills/mac-storage-cleaner/SKILL.md"
}
json_version () { grep -m1 '"version"' "$1" | sed -E 's/.*"version"[^"]*"([^"]+)".*/\1/'; }

@test "every manifest carries the same version as SKILL.md" {
  local v; v=$(skill_version)
  [ -n "$v" ]
  [ "$(json_version "$ROOT/.claude-plugin/plugin.json")" = "$v" ]
  [ "$(json_version "$ROOT/.cursor-plugin/plugin.json")" = "$v" ]
  local mp; mp="$ROOT/.claude-plugin/marketplace.json"
  # marketplace.json carries the version twice (metadata + the plugin entry)
  [ "$(grep -c "\"version\": \"$v\"" "$mp")" -eq 2 ]
}

@test "every JSON manifest is valid JSON" {
  local f
  for f in "$ROOT/.claude-plugin/plugin.json" "$ROOT/.claude-plugin/marketplace.json" "$ROOT/.cursor-plugin/plugin.json"; do
    run python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f"
    [ "$status" -eq 0 ] || { echo "invalid JSON: $f"; false; }
  done
}

@test "the Codex manifest declares implicit invocation" {
  local y="$ROOT/skills/mac-storage-cleaner/agents/openai.yaml"
  [ -f "$y" ]
  grep -q 'allow_implicit_invocation: true' "$y"
}

@test "bump-version.sh rewrites every location" {
  local tmp; tmp="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$tmp"
  ( cd "$ROOT" && rsync -a --exclude .git ./ "$tmp/" )
  run bash "$tmp/tools/bump-version.sh" 9.9.9
  [ "$status" -eq 0 ]
  grep -q '  version: 9.9.9' "$tmp/skills/mac-storage-cleaner/SKILL.md"
  grep -q '"version": "9.9.9"' "$tmp/.claude-plugin/plugin.json"
  grep -q '"version": "9.9.9"' "$tmp/.cursor-plugin/plugin.json"
  [ "$(grep -c '"version": "9.9.9"' "$tmp/.claude-plugin/marketplace.json")" -eq 2 ]
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/manifests.bats`
Expected: FAIL — `.cursor-plugin/plugin.json`, `agents/openai.yaml` and `tools/bump-version.sh` do not exist.

- [ ] **Step 3: Create the Codex manifest**

`skills/mac-storage-cleaner/agents/openai.yaml`:

```yaml
# Codex-specific presentation and invocation policy. Codex reads this file
# alongside SKILL.md; every other agent ignores the directory.
interface:
  display_name: Mac Storage Cleaner
  short_description: Safe, reversible macOS disk cleanup with an audit log.
policy:
  # The skill should surface when a user says they are out of disk space, not
  # only when they name it explicitly.
  allow_implicit_invocation: true
```

- [ ] **Step 4: Create the Cursor plugin manifest**

`.cursor-plugin/plugin.json` (Cursor auto-discovers components from `skills/`, which this repo already has):

```json
{
  "name": "mac-storage-cleaner",
  "version": "3.0.0",
  "description": "Trust-first macOS disk cleaner: allowlist-only auto-clean, mechanically enforced never-tier, reversible Trash removals, preview by default, audit log.",
  "author": "Juba Kitiashvili",
  "license": "MIT",
  "repository": "https://github.com/JubaKitiashvili/mac-storage-cleaner"
}
```

- [ ] **Step 5: Create the bump script**

`tools/bump-version.sh`:

```bash
#!/bin/bash
# Repo tooling (NOT shipped inside the skill): set the release version in every
# manifest at once. The version lives in five places and CI fails on drift.
set -eu
[ $# -eq 1 ] || { echo "usage: tools/bump-version.sh <semver>"; exit 1; }
V="$1"
echo "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "not a semver: $V"; exit 1; }
R="$(cd "$(dirname "$0")/.." && pwd)"

/usr/bin/sed -i '' -E "s/^(  version: ).*/\1$V/"            "$R/skills/mac-storage-cleaner/SKILL.md"
/usr/bin/sed -i '' -E "s/(\"version\": \")[^\"]+(\")/\1$V\2/" "$R/.claude-plugin/plugin.json"
/usr/bin/sed -i '' -E "s/(\"version\": \")[^\"]+(\")/\1$V\2/" "$R/.claude-plugin/marketplace.json"
/usr/bin/sed -i '' -E "s/(\"version\": \")[^\"]+(\")/\1$V\2/" "$R/.cursor-plugin/plugin.json"

echo "bumped to $V:"
grep -n '  version: ' "$R/skills/mac-storage-cleaner/SKILL.md"
grep -n '"version"'   "$R/.claude-plugin/plugin.json" "$R/.claude-plugin/marketplace.json" "$R/.cursor-plugin/plugin.json"
```

Make it executable: `chmod +x tools/bump-version.sh`

- [ ] **Step 6: Bring the existing manifests to 3.0.0**

Run: `bash tools/bump-version.sh 3.0.0`
Expected: the command prints five version lines, all `3.0.0`.

- [ ] **Step 7: Run the tests**

Run: `bats tests/manifests.bats && bats tests/`
Expected: `manifests.bats` 4/4 pass; full suite green (115 tests).

- [ ] **Step 8: Add the parity check to CI**

In `.github/workflows/ci.yml`, after the shellcheck step, add:

```yaml
      - name: Manifest version parity
        run: bats tests/manifests.bats
```

(The full-suite step already covers it; this step makes a drift failure obvious in the job log.)

- [ ] **Step 9: Sync and commit**

```bash
rsync -a --delete ~/Desktop/Projects/mac-storage-cleaner/skills/mac-storage-cleaner/ ~/.claude/skills/mac-storage-cleaner/
git add -A
git commit -m "feat: Codex and Cursor manifests, single-source version bumping"
```

---

### Task 7: Documentation — declaration, README, deprecation, CHANGELOG

**Files:**
- Modify: `skills/mac-storage-cleaner/SKILL.md` (add the declaration section; env vars; Tests section)
- Modify: `README.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: the CLI contract from Tasks 3-4 (`--apply`, `--force`, exit 4) and the env vars `MSC_MAX_TRASH_ITEMS` / `MSC_MAX_TRASH_GB`.

**Why:** ClawHub compares *declared* behavior against observed syscalls daily; undeclared `osascript` Finder automation is exactly the pattern that gets flagged suspicious. And the README currently promises a Claude Desktop install that cannot work.

- [ ] **Step 1: Add the declaration section to SKILL.md**

Insert immediately after the "Core principles" section:

```markdown
## What this skill does to your disk (declared behavior)

This section is a complete, mechanism-level statement of every destructive
operation, so automated skill scanners and human reviewers can compare what is
declared here against what the scripts actually do.

**Deletes permanently (`rm -rf`)** — only paths on the hard-coded safe allowlist
in `scripts/lib.sh` (`SAFE_PATHS`, `KEEP_N_PATHS`, AI-CLI version roots) plus
age-gated Handoff clipboard buffers and crash-report artifacts. Retries once
after `chmod -R u+w` when a read-only file blocks removal.

**Moves to the Trash (reversible)** — everything else, via `/usr/bin/trash`, then
Finder automation through `osascript` (`tell application "Finder" to delete`),
then a same-volume `mv` into `~/.Trash`.

**Runs these third-party cleanup commands** — `brew cleanup -s --prune=all`,
`conda clean -y --tarballs --index-cache --logfiles`, `xcrun simctl delete unavailable`.

**Reads** — `du`, `df`, `find`, `stat`, `pgrep`/`ps`, `mdfind` (Spotlight, to check
whether an app is still installed), and `defaults read` on app bundles.

**Writes** — `~/Library/Logs/mac-storage-cleaner/operations.log` (audit trail,
rotated at 5 MB) and nothing else.

**Mechanically refuses** — `/System`, `/bin`, `/sbin`, `/dev`, `/private/var/db`,
other users' home directories, and the never-tier: iOS backups (MobileSync),
Photos libraries, Keychains, Mail, Messages, `~/.ssh`, `~/.aws`, `~/.gnupg`.
These are enforced in `validate_target_path`, not by convention.

**Never uses `sudo`** and makes **no network requests**.
```

- [ ] **Step 2: Update SKILL.md's environment-variable list**

Add these two entries:

```markdown
- `MSC_MAX_TRASH_ITEMS` (default `100`) — refuse a `trash-items.sh` batch with more eligible items unless `--force` is passed.
- `MSC_MAX_TRASH_GB` (default `5`) — refuse a `trash-items.sh` batch larger than this unless `--force` is passed.
```

- [ ] **Step 3: Fix SKILL.md's Tests section**

Replace the Tests section body with:

```markdown
`bats tests/` from a clone of the source repository
(https://github.com/JubaKitiashvili/mac-storage-cleaner, `brew install bats-core`).
The tests are not shipped inside the installed skill. Every test runs against a
fake `$HOME`; the dangerous-path corpus in `tests/fixtures/` is a floor —
investigate a failure, never weaken the corpus.
```

- [ ] **Step 4: Rewrite the README install section**

Replace the four Option A-D blocks with:

```markdown
## Install

**Any agent — one command:**

```bash
npx skills add JubaKitiashvili/mac-storage-cleaner
```

This installs into whichever agents you have (Claude Code, Codex, Cursor,
Windsurf, opencode, Antigravity, Gemini CLI, Copilot CLI and ~70 more) via the
open [skills CLI](https://github.com/vercel-labs/skills). Add `-g` for a global
install, or `-a <agent>` to target one.

| Agent | Command | Lands in |
|---|---|---|
| Claude Code | `/plugin marketplace add JubaKitiashvili/mac-storage-cleaner` then `/plugin install mac-storage-cleaner@mac-storage-cleaner` | plugin root |
| Codex / Codex CLI | `npx skills add JubaKitiashvili/mac-storage-cleaner -a codex -g` | `~/.codex/skills/` |
| Cursor | `npx skills add JubaKitiashvili/mac-storage-cleaner -a cursor -g` | `~/.cursor/skills/` |
| Windsurf | `npx skills add JubaKitiashvili/mac-storage-cleaner -a windsurf -g` | `~/.codeium/windsurf/skills/` |
| Antigravity | `npx skills add JubaKitiashvili/mac-storage-cleaner -a antigravity -g` | `~/.gemini/antigravity/skills/` |
| opencode | `npx skills add JubaKitiashvili/mac-storage-cleaner -a opencode -g` | `~/.config/opencode/skills/` |
| Hermes Agent | `hermes skills install JubaKitiashvili/mac-storage-cleaner/skills/mac-storage-cleaner` | `~/.hermes/skills/` |
| OpenClaw | `openclaw skills install …` (see ClawHub listing) | OpenClaw skills dir |
| Manual | `git clone` then copy `skills/mac-storage-cleaner/` into any skills root | — |

### Claude Desktop / claude.ai — not supported, and here's why

Skills uploaded to Claude Desktop or claude.ai run their scripts in a sandbox:
in chat they execute in Anthropic's server-side container, and in Cowork inside a
VM that can only reach folders you explicitly connect. Neither can see
`~/Library/Caches`, `~/Library/Developer`, or your Trash — so a disk cleaner
there would report success while freeing nothing on your Mac. Use Claude **Code**
(or any of the agents above), which runs on your real filesystem with your
approval model.
```

- [ ] **Step 5: Add the per-agent safety section to the README**

Insert after the Safety section:

```markdown
### How safety works on your agent

The skill's own guardrails (allowlist-only deletion, mechanically refused
never-tier, Trash instead of `rm`, audit log) are identical everywhere. What
differs is whether your agent asks before running a command:

| Agent | Before a destructive command |
|---|---|
| Claude Code | prompts per command |
| Cursor | sandbox + explicit file-deletion protection for `rm` |
| Antigravity | permission lists; `command(rm -rf)` is a documented deny entry |
| Windsurf | four auto-execution levels; `rm` is a documented deny-list example |
| Codex | approval policy per session |
| **opencode** | **no prompt by default** |
| **OpenClaw** | **no prompt by default** (`security="full", ask="off"`) |

That is why `clean-safe.sh` **previews by default** and needs `--apply` to
delete, and why `trash-items.sh` refuses batches over 100 items or 5 GB without
`--force`. On a no-prompt agent those defaults are the only thing standing
between an over-eager agent and your files — no script can tell an agent from a
human, so the guarantee is *there is no destructive default*, not *a human always
approves*.
```

- [ ] **Step 6: Add the telemetry disclosure to the README**

Insert directly after the install section:

```markdown
> **Telemetry.** This skill sends nothing anywhere — it makes no network
> requests at all. The `npx skills add` installer, which is third-party, reports
> installs of public GitHub repositories to skills.sh; that is what produces the
> public listing. Install by cloning if you would rather not.
```

- [ ] **Step 7: Deprecate the `.skill` artifact**

Replace the README line linking `dist/mac-storage-cleaner.skill` with:

```markdown
> **Deprecated:** `dist/mac-storage-cleaner.skill` remains for one release only.
> It was built for Claude Desktop, which requires a `.zip` whose root is the
> skill folder and caps skill descriptions at 200 characters — so it was never
> installable there. Use the install commands above. The file will be removed in
> the next minor release.
```

Do **not** delete the file in this release: it is a linked path and deleting it breaks external references.

- [ ] **Step 8: Write the CHANGELOG entry**

Add at the top of `CHANGELOG.md`:

```markdown
## 3.0.0 — 2026-08-14

Cross-agent release: the skill now runs on every major AI coding agent, and its
default is no longer destructive.

### Breaking
- **`clean-safe.sh` previews by default.** Deleting requires `--apply`.
  `--dry-run` is still accepted as an alias, and `MSC_DRY_RUN=1` overrides
  `--apply` (the env var can only ever make a run safer). Several agents execute
  shell commands with no approval prompt, so a destructive default meant an agent
  could delete caches the user never saw proposed.
- **`trash-items.sh` refuses bulk operations.** Batches over 100 eligible items
  or 5 GB now exit 4 unless `--force` is the first argument
  (`MSC_MAX_TRASH_ITEMS`, `MSC_MAX_TRASH_GB`).

### Fixed
- **The skill now finds itself when installed by any agent.** Every SKILL.md
  command block searches all standard skill roots (Claude Code, Codex, Cursor,
  opencode, Antigravity, Windsurf, Hermes, `.agents/skills`, and project-scoped
  installs) instead of only `~/.claude/skills`, where an install anywhere else
  failed with "No such file or directory".

### Added
- Portable frontmatter: `license` plus a string-valued `metadata` map carrying
  version, author, platform and tags; the description is now asserted in bytes
  (972/1024) because Georgian trigger phrases cost 3 bytes per glyph.
- `agents/openai.yaml` (Codex display metadata and implicit invocation) and
  `.cursor-plugin/plugin.json` (Cursor Marketplace).
- A declared-behavior section in SKILL.md enumerating every destructive
  operation, for automated skill scanners.
- GitHub Actions CI on `macos-latest`: bats, shellcheck, SKILL.md bash-block
  linting and manifest version parity.
- `tools/bump-version.sh` — one command sets the version in all five places.
- Per-agent install matrix, per-agent safety table, and a telemetry disclosure in
  the README.

### Deprecated
- `dist/mac-storage-cleaner.skill` — built for a Claude Desktop upload flow that
  requires `.zip` and a ≤200-character description, so it was never installable
  there. Removed next minor.

### Testing
- 115 tests (up from 89): resolver coverage for every documented install root,
  the `--apply` gate, the blast-radius cap, frontmatter byte budget, manifest
  parity, and a lint that `bash -n`s every command block in SKILL.md.
```

- [ ] **Step 9: Verify the docs match reality**

Run: `bats tests/` (all green) and `grep -n '\-\-apply' README.md skills/mac-storage-cleaner/SKILL.md | head`
Expected: both files reference `--apply`; no remaining text tells the user that a bare `clean-safe.sh` deletes.

- [ ] **Step 10: Sync and commit**

```bash
rsync -a --delete ~/Desktop/Projects/mac-storage-cleaner/skills/mac-storage-cleaner/ ~/.claude/skills/mac-storage-cleaner/
git add -A
git commit -m "docs: declared-behavior section, per-agent install and safety matrices, v3.0.0 changelog"
```

---

### Task 8: Compat matrix, release v3.0.0

**Files:**
- Create: `docs/compat/README.md`
- Create: `docs/compat/claude-code.md`

**Interfaces:**
- Produces: the per-agent verification record format that Task 9 fills in for the remaining agents.

- [ ] **Step 1: Create the compat matrix index**

`docs/compat/README.md`:

```markdown
# Agent compatibility

No agent can be verified in CI — each one has its own install path, skill loader
and approval model. This directory records manual verification runs instead.

Each file records, for one agent: the agent version, the date, and three
assertions.

1. **Resolution** — after installing through that agent's own path, the resolver
   in SKILL.md finds the skill and `scripts/lib.sh` exists.
2. **Trigger** — the fixed prompt *"my mac is out of space"* causes the agent to
   load the skill. This is the assertion no manifest can guarantee: the
   description is tuned for Claude's selector, and "natively usable" fails
   silently if another agent never invokes it.
3. **Gating** — `clean-safe.sh` with no argument deletes nothing.

The top three agents are re-verified every release.

| Agent | Verified | Version | Resolution | Trigger | Gating |
|---|---|---|---|---|---|
| Claude Code | 2026-08-14 | see file | ✅ | ✅ | ✅ |
| Codex CLI | — | — | — | — | — |
| Cursor | — | — | — | — | — |
| Windsurf | — | — | — | — | — |
| Antigravity | — | — | — | — | — |
| opencode | — | — | — | — | — |
```

- [ ] **Step 2: Verify Claude Code and record it**

Run these three checks and paste the real output into `docs/compat/claude-code.md`:

```bash
# 1. Resolution — run the resolver exactly as SKILL.md does
D=""; for r in "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/skills" "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.cursor/skills" "$HOME/.codex/skills" "$HOME/.config/opencode/skills" "$HOME/.gemini/config/skills" "$HOME/.gemini/antigravity/skills" "$HOME/.codeium/windsurf/skills" "$HOME/.hermes/skills" ".claude/skills" ".agents/skills" ".cursor/skills" ".windsurf/skills"; do [ -f "$r/mac-storage-cleaner/scripts/lib.sh" ] && { D="$r/mac-storage-cleaner"; break; }; done; echo "D=$D"
# 3. Gating — preview must delete nothing (safe: this is the new default)
bash "$D/scripts/clean-safe.sh" | tail -3
```

For assertion 2, note that this very session's skill invocation is the evidence.

`docs/compat/claude-code.md`:

```markdown
# Claude Code

- **Verified:** 2026-08-14
- **Agent version:** <output of `claude --version`>
- **Install path used:** `~/.claude/skills/mac-storage-cleaner`

| Assertion | Result | Evidence |
|---|---|---|
| Resolution | ✅ | `D=/Users/…/.claude/skills/mac-storage-cleaner` |
| Trigger | ✅ | "my mac is out of space" loads the skill |
| Gating | ✅ | bare `clean-safe.sh` printed PREVIEW and deleted nothing |
```

- [ ] **Step 3: Full suite, then tag**

```bash
cd ~/Desktop/Projects/mac-storage-cleaner
bats tests/
bash tools/bump-version.sh 3.0.0   # idempotent; confirms all five locations
git add -A
git commit -m "docs: agent compatibility matrix"
git tag -a v3.0.0 -m "v3.0.0 — cross-agent release: portable resolver, preview by default, blast-radius cap"
```

Do **not** push yet — Task 9 gates the push on verification.

---

### Task 9: Verification and publication (manual, gated)

**Files:**
- Modify: `docs/compat/*.md` (fill in per agent)

**Interfaces:**
- Consumes: everything above. This task performs the irreversible steps and must not start until `bats tests/` is green and the tag exists.

- [ ] **Step 1: Push code and tag**

```bash
cd ~/Desktop/Projects/mac-storage-cleaner
git push origin main --tags
```

Confirm CI goes green on GitHub before continuing. If CI fails, fix forward and re-tag; do not publish from a red tree.

- [ ] **Step 2: Verify each locally installed agent and record it**

For every agent installed on this machine, run the three assertions from `docs/compat/README.md` and write a `docs/compat/<agent>.md` file with real output. Mark uninstalled agents as `not verified — agent not installed locally` in the index table rather than claiming a pass.

Commit: `git add docs/compat && git commit -m "docs: record per-agent verification" && git push`

- [ ] **Step 3: Seed the skills.sh listing**

```bash
cd "$(mktemp -d)" && npx skills add JubaKitiashvili/mac-storage-cleaner -a claude-code -y --copy
```

Run this **without** `DISABLE_TELEMETRY=1` — the install event is what creates the public listing. Then confirm within a few minutes: `open https://skills.sh/jubakitiashvili/mac-storage-cleaner`. Delete the temp directory afterward.

- [ ] **Step 4: Publish to ClawHub**

Only after Step 2 recorded at least one verified non-Claude agent. ClawHub claims a namespace and starts daily VirusTotal scans that compare declared behavior against observed behavior — the declaration added in Task 7 is what keeps the scan clean.

```bash
clawhub publish   # from the skill folder; follow the CLI's prompts
```

If the scan flags the skill, respond by pointing at the declaration section, not by weakening the scripts.

- [ ] **Step 5: Submit to the Cursor Marketplace**

Open https://cursor.com/marketplace/publish and submit the repository. Requirements already met: open source (MIT), `.cursor-plugin/plugin.json` present, components auto-discovered from `skills/`. Manual review takes time; nothing else blocks on it.

- [ ] **Step 6: Update the open aitmpl PR to v3.0.0**

```bash
cd ~/Desktop/Projects/_forks/claude-code-templates
git fetch upstream main && git checkout update-mac-storage-cleaner-v2
DEST=cli-tool/components/skills/productivity/mac-storage-cleaner
rm -rf "$DEST" && cp -R ~/.claude/skills/mac-storage-cleaner "$DEST"
find "$DEST" -name .DS_Store -delete
git add "$DEST"
git -c user.name="Juba" -c user.email="juba.kitiashvili@gmail.com" commit -m "mac-storage-cleaner: v3.0.0 — cross-agent release"
git push
```

Then comment on PR #792 explaining the breaking change (preview by default) and that one version now ships everywhere.

- [ ] **Step 7: Final state check**

```bash
cd ~/Desktop/Projects/mac-storage-cleaner
git status --short          # clean
git log --oneline -1        # v3.0.0 release commit
bats tests/                 # green
diff -rq skills/mac-storage-cleaner ~/.claude/skills/mac-storage-cleaner  # silent
```

---

## Self-Review

**1. Spec coverage.** D1→T2 · D2→T3 · D3→T4 · D4→T5 · D5→T7 Step 1 · D6→T6 · D7→T1 (+T6 Step 8, and the bash-block lint lives in T2 as a bats test so it runs locally too) · D8→T7 Step 7 · D9→T7 Steps 4-6 + SKILL.md Tests fix in Step 3 · D10→T8 + T9 Step 2 · D11→T6 Step 5 · D12→ the task order itself, with publications isolated in T9.

**2. Placeholder scan.** The only intentional fill-ins are real measurements that cannot be known before running: the frontmatter spike results (T5 Step 5), the Claude Code version string and per-agent evidence (T8 Step 2, T9 Step 2). Each says exactly what to record and what to write when an agent is not installed.

**3. Type consistency.** `--apply` / `--dry-run` / `MSC_DRY_RUN` semantics are identical in T3, T7 and the CHANGELOG. `--force`, exit 4, `MSC_MAX_TRASH_ITEMS`, `MSC_MAX_TRASH_GB` match across T4 and T7. The resolver snippet in T2 Step 3, T8 Step 2 and the docs is the same text. `metadata.version` is read the same way by T6's `skill_version()` and written the same way by `tools/bump-version.sh`. Test counts rise 89 → 95 → 101 → 106 → 111 → 115 consistently across tasks.
