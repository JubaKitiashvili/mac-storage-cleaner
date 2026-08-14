# Codex CLI

- **Verified:** 2026-08-14
- **Agent version:** `codex-cli 0.144.5` (via `codex --version`; `codex doctor` shows an update to 0.147.0 is available but was not installed for this verification)
- **Install path used:** `~/.codex/skills/mac-storage-cleaner`

| Assertion | Result | Evidence |
|---|---|---|
| Resolution | ✅ | `D=/Users/macbook/.codex/skills/mac-storage-cleaner` — resolver script from SKILL.md run with `MSC_SKILL_ROOT` pinned to `~/.codex/skills` (see caveat below on why pinning was necessary) found `scripts/lib.sh` at this path. |
| Trigger | unverified — requires an interactive session | No CLI subcommand exists to list or dry-run skill loading. `codex skills list` does not exist (`error: unexpected argument 'list' found`). Checked `codex --help`, `codex plugin --help`, and `codex features list` for anything skill-related: `codex features list \| grep -i skill` returns two internal feature flags — `skill_mcp_dependency_install  stable  true` and `skill_env_var_dependency_prompt  removed  false` — confirming Codex CLI has skill-loading machinery built in and enabled, but this does not confirm *this* skill is discovered or invoked. The skill also ships a Codex-specific `agents/openai.yaml` (copied by the install rsync) declaring `allow_implicit_invocation: true`, which is packaging evidence of intended compatibility, not proof of a successful load. No controlled trigger-prompt test was run. |
| Gating | ✅ | `grep -c '^APPLY=0$' "$D/scripts/clean-safe.sh"` → `1`; `grep -c 'PREVIEW — nothing will be deleted' "$D/scripts/clean-safe.sh"` → `1`. Grep-only, read-only — the script was never executed. |

## Caveat on resolution methodology

The resolver in SKILL.md tries candidates in a fixed order, and `$HOME/.claude/skills`
(which also has the skill installed, from the Claude Code verification) comes
before `$HOME/.codex/skills` in that order. Running the resolver unmodified
would therefore resolve to the Claude Code path regardless of whether the
Codex path is also valid, and would not prove the Codex root specifically
works. To isolate the Codex root, the resolver was run with `MSC_SKILL_ROOT`
(the resolver's documented escape-hatch, checked first in the candidate list)
temporarily set to `$HOME/.codex/skills` for this one invocation — this does
not change the installed files, only which candidate the search starts from.

## Verification commands (literal transcript)

Install:

```
$ mkdir -p ~/.codex/skills && rsync -a --delete ~/Desktop/Projects/mac-storage-cleaner/skills/mac-storage-cleaner/ ~/.codex/skills/mac-storage-cleaner/
$ ls ~/.codex/skills/mac-storage-cleaner
agents  references  scripts  SKILL.md
$ test -f ~/.codex/skills/mac-storage-cleaner/scripts/lib.sh && echo present
present
```

Resolution (subshell, `MSC_SKILL_ROOT` pinned to the Codex root only):

```
$ ( D=""; MSC_SKILL_ROOT="$HOME/.codex/skills"; for r in "${MSC_SKILL_ROOT:-/nonexistent}" "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/skills" "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.cursor/skills" "$HOME/.codex/skills" "$HOME/.config/opencode/skills" "$HOME/.gemini/config/skills" "$HOME/.gemini/antigravity/skills" "$HOME/.codeium/windsurf/skills" "$HOME/.hermes/skills" ".claude/skills" ".agents/skills" ".cursor/skills" ".windsurf/skills"; do [ -f "$r/mac-storage-cleaner/scripts/lib.sh" ] && { D="$r/mac-storage-cleaner"; break; }; done; echo "D=$D" )
D=/Users/macbook/.codex/skills/mac-storage-cleaner
```

Trigger (CLI probing — no positive evidence found):

```
$ codex skills list
error: unexpected argument 'list' found
$ codex features list | grep -i skill
skill_env_var_dependency_prompt      removed            false
skill_mcp_dependency_install         stable             true
```

Gating (installed copy, read-only, script never executed):

```
$ grep -c '^APPLY=0$' "$D/scripts/clean-safe.sh"
1
$ grep -c 'PREVIEW — nothing will be deleted' "$D/scripts/clean-safe.sh"
1
```
