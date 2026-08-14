# Cursor

- **Verified:** 2026-08-14
- **Agent version:** `3.15.19` (Cursor.app `CFBundleShortVersionString`, build `de07bee81cefe43461ebf4f40c3d2d78d15052a0`, arm64 — via the bundled `cursor` CLI shim's `--version` output)
- **Install path used:** `~/.cursor/skills/mac-storage-cleaner`

| Assertion | Result | Evidence |
|---|---|---|
| Resolution | ✅ | `D=/Users/macbook/.cursor/skills/mac-storage-cleaner` — resolver script from SKILL.md run with `MSC_SKILL_ROOT` pinned to `~/.cursor/skills` (see caveat in [codex-cli.md](codex-cli.md), which applies identically here — `$HOME/.claude/skills` is also populated and sorts earlier in the unmodified candidate order) found `scripts/lib.sh` at this path. |
| Trigger | unverified — requires an interactive session | Cursor is a GUI editor (VS Code fork); its bundled CLI shim (`/Applications/Cursor.app/Contents/Resources/app/bin/cursor`) only supports editor-launch flags (`--version`, file/folder open, tunnel) — there is no `skills list` or equivalent non-interactive command to query what the editor's agent has loaded. No skill-listing capability was found. No controlled trigger-prompt test was run; this would require opening the Cursor GUI and inspecting its agent chat. |
| Gating | ✅ | `grep -c '^APPLY=0$' "$D/scripts/clean-safe.sh"` → `1`; `grep -c 'PREVIEW — nothing will be deleted' "$D/scripts/clean-safe.sh"` → `1`. Grep-only, read-only — the script was never executed. |

## Verification commands (literal transcript)

Install:

```
$ mkdir -p ~/.cursor/skills && rsync -a --delete ~/Desktop/Projects/mac-storage-cleaner/skills/mac-storage-cleaner/ ~/.cursor/skills/mac-storage-cleaner/
$ ls ~/.cursor/skills/mac-storage-cleaner
agents  references  scripts  SKILL.md
$ test -f ~/.cursor/skills/mac-storage-cleaner/scripts/lib.sh && echo present
present
```

Resolution (subshell, `MSC_SKILL_ROOT` pinned to the Cursor root only):

```
$ ( D=""; MSC_SKILL_ROOT="$HOME/.cursor/skills"; for r in "${MSC_SKILL_ROOT:-/nonexistent}" "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/skills" "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.cursor/skills" "$HOME/.codex/skills" "$HOME/.config/opencode/skills" "$HOME/.gemini/config/skills" "$HOME/.gemini/antigravity/skills" "$HOME/.codeium/windsurf/skills" "$HOME/.hermes/skills" ".claude/skills" ".agents/skills" ".cursor/skills" ".windsurf/skills"; do [ -f "$r/mac-storage-cleaner/scripts/lib.sh" ] && { D="$r/mac-storage-cleaner"; break; }; done; echo "D=$D" )
D=/Users/macbook/.cursor/skills/mac-storage-cleaner
```

Trigger (CLI probing — no skills-listing capability exists):

```
$ /Applications/Cursor.app/Contents/Resources/app/bin/cursor --version
3.15.19
de07bee81cefe43461ebf4f40c3d2d78d15052a0
arm64
```

(No `skills`/`agent`/equivalent subcommand exists on this CLI to query loaded skills.)

Gating (installed copy, read-only, script never executed):

```
$ grep -c '^APPLY=0$' "$D/scripts/clean-safe.sh"
1
$ grep -c 'PREVIEW — nothing will be deleted' "$D/scripts/clean-safe.sh"
1
```
