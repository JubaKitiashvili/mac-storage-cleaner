# Claude Code

- **Verified:** 2026-08-14
- **Agent version:** 2.1.232 (Claude Code)
- **Install path used:** `~/.claude/skills/mac-storage-cleaner`

| Assertion | Result | Evidence |
|---|---|---|
| Resolution | ✅ | `D=/Users/macbook/.claude/skills/mac-storage-cleaner` — resolver script (verbatim from SKILL.md) found `scripts/lib.sh` at this path on the first matching root (`$HOME/.claude/skills`). |
| Trigger | ✅ | Not a controlled test of the literal fixed prompt "my mac is out of space" in English. Evidence instead: in this session the skill was explicitly invoked via its slash command with the Georgian prompt *"ეხლა ჩვენი სქილი ეხლა რეალურად მუშაობს claude cli-ზე"* ("now our skill actually works on claude cli"); in an earlier session, the skill auto-triggered (no explicit invocation) from a Georgian out-of-space phrasing. Together this shows the skill loads in Claude Code and has been used to run real cleanups — recorded honestly as real usage, not a controlled trigger-prompt experiment. |
| Gating | ✅ | `grep -c '^APPLY=0$' "$D/scripts/clean-safe.sh"` → `1`; `grep -c 'PREVIEW — nothing will be deleted' "$D/scripts/clean-safe.sh"` → `1`. Additionally ran the gated demonstration (fake `$HOME`, stubbed `brew`/`xcode-select`/`pgrep`/`conda`/`ps`, real `$HOME` never touched): bare invocation printed `=== PREVIEW — nothing will be deleted (re-run with --apply to delete) ===` and only logged `would run: ...` lines — nothing was deleted. |

## Verification commands (literal transcript)

Resolution:

```
$ D=""; for r in "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/skills" "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.cursor/skills" "$HOME/.codex/skills" "$HOME/.config/opencode/skills" "$HOME/.gemini/config/skills" "$HOME/.gemini/antigravity/skills" "$HOME/.codeium/windsurf/skills" "$HOME/.hermes/skills" ".claude/skills" ".agents/skills" ".cursor/skills" ".windsurf/skills"; do [ -f "$r/mac-storage-cleaner/scripts/lib.sh" ] && { D="$r/mac-storage-cleaner"; break; }; done; echo "D=$D"
D=/Users/macbook/.claude/skills/mac-storage-cleaner
```

Gating (installed copy, read-only):

```
$ grep -c '^APPLY=0$' "$D/scripts/clean-safe.sh"
1
$ grep -c 'PREVIEW — nothing will be deleted' "$D/scripts/clean-safe.sh"
1
```

Gating (optional demonstration, staleness-gated, fake `$HOME`, stubbed tool commands):

```
$ grep -q '^APPLY=0$' "$D/scripts/clean-safe.sh" || { echo "installed copy is stale — sync it first"; exit 1; }
$ FAKE="$(mktemp -d)"; STUB="$(mktemp -d)"
$ for s in brew xcode-select pgrep conda ps; do printf '#!/bin/bash\nexit 1\n' > "$STUB/$s"; chmod +x "$STUB/$s"; done
$ env HOME="$FAKE" PATH="$STUB:$PATH" bash "$D/scripts/clean-safe.sh" | head -3
=== PREVIEW — nothing will be deleted (re-run with --apply to delete) ===
Clearing safe caches (pure caches only)...
  would run: brew cleanup -s --prune=all
$ rm -rf "$FAKE" "$STUB"
```
