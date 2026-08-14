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

@test "every SKILL.md command block uses one byte-identical resolver" {
  local n uniq
  n=$(grep -c '^D=""; for r in ' "$SKILL_MD")
  # >= 4 rather than == 4: Task 3 adds a fifth block (the --apply variant).
  [ "$n" -ge 4 ] || { echo "expected >=4 resolver lines, found $n"; false; }
  uniq=$(grep '^D=""; for r in ' "$SKILL_MD" | sort -u | wc -l | tr -d ' ')
  [ "$uniq" -eq 1 ] || { echo "the resolver lines are not identical to each other"; false; }
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
  # NOTE: this suite's pinned bats predates BATS_TEST_TMPDIR — every existing
  # test uses "${BATS_TMPDIR:-/tmp}" with mktemp. Do the same, or an unset
  # variable turns "mkdir -p $BATS_TEST_TMPDIR/blocks" into a write at /.
  local tmp b count=0
  tmp="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-blocks.XXXXXX")"
  awk -v out="$tmp" 'BEGIN{n=0}
    /^```bash$/ {n++; f=1; next}
    /^```$/     {f=0; next}
    f           {print >> (out "/b" n ".sh")}' "$SKILL_MD"
  for b in "$tmp"/b*.sh; do
    [ -f "$b" ] || continue
    count=$((count + 1))
    run /bin/bash -n "$b"
    [ "$status" -eq 0 ] || { echo "bash -n failed for $b"; rm -rf "$tmp"; false; }
  done
  rm -rf "$tmp"
  [ "$count" -ge 4 ] || { echo "expected >=4 bash blocks, found $count"; false; }
}
