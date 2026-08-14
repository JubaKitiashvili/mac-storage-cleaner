# Windsurf

- **Verified:** 2026-08-14
- **Agent version:** `2.3.15` (Windsurf.app `CFBundleShortVersionString`; the bundled `windsurf` CLI shim reports `1.110.1` — its underlying VS Code base build, not the Windsurf product version — build `c46c49e94b4d3f41181204d59809d8f1b2c48d68`, arm64)
- **Install path used:** `~/.codeium/windsurf/skills/mac-storage-cleaner`

| Assertion | Result | Evidence |
|---|---|---|
| Resolution | ✅ | `D=/Users/macbook/.codeium/windsurf/skills/mac-storage-cleaner` — resolver script from SKILL.md run with `MSC_SKILL_ROOT` pinned to `~/.codeium/windsurf/skills` (see caveat in [codex-cli.md](codex-cli.md), which applies identically here — `$HOME/.claude/skills` is also populated and sorts earlier in the unmodified candidate order) found `scripts/lib.sh` at this path. |
| Trigger | unverified — requires an interactive session | Windsurf is a GUI editor (VS Code fork); its bundled CLI shim (`/Applications/Windsurf.app/Contents/Resources/app/bin/windsurf`) only supports editor-launch flags (`--version`, file/folder open) — there is no `skills list` or equivalent non-interactive command to query what the editor's Cascade agent has loaded. No skill-listing capability was found. No controlled trigger-prompt test was run; this would require opening the Windsurf GUI and inspecting its Cascade chat. |
| Gating | ✅ | `grep -c '^APPLY=0$' "$D/scripts/clean-safe.sh"` → `1`; `grep -c 'PREVIEW — nothing will be deleted' "$D/scripts/clean-safe.sh"` → `1`. Grep-only, read-only — the script was never executed. |

## Verification commands (literal transcript)

Install:

```
$ mkdir -p ~/.codeium/windsurf/skills && rsync -a --delete ~/Desktop/Projects/mac-storage-cleaner/skills/mac-storage-cleaner/ ~/.codeium/windsurf/skills/mac-storage-cleaner/
$ ls ~/.codeium/windsurf/skills/mac-storage-cleaner
agents  references  scripts  SKILL.md
$ test -f ~/.codeium/windsurf/skills/mac-storage-cleaner/scripts/lib.sh && echo present
present
```

Resolution (subshell, `MSC_SKILL_ROOT` pinned to the Windsurf root only):

```
$ ( D=""; MSC_SKILL_ROOT="$HOME/.codeium/windsurf/skills"; for r in "${MSC_SKILL_ROOT:-/nonexistent}" "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/skills" "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.cursor/skills" "$HOME/.codex/skills" "$HOME/.config/opencode/skills" "$HOME/.gemini/config/skills" "$HOME/.gemini/antigravity/skills" "$HOME/.codeium/windsurf/skills" "$HOME/.hermes/skills" ".claude/skills" ".agents/skills" ".cursor/skills" ".windsurf/skills"; do [ -f "$r/mac-storage-cleaner/scripts/lib.sh" ] && { D="$r/mac-storage-cleaner"; break; }; done; echo "D=$D" )
D=/Users/macbook/.codeium/windsurf/skills/mac-storage-cleaner
```

Trigger (CLI probing — no skills-listing capability exists):

```
$ /Applications/Windsurf.app/Contents/Resources/app/bin/windsurf --version
1.110.1
c46c49e94b4d3f41181204d59809d8f1b2c48d68
arm64
```

(No `skills`/`cascade`/equivalent subcommand exists on this CLI to query loaded skills.)

Gating (installed copy, read-only, script never executed):

```
$ grep -c '^APPLY=0$' "$D/scripts/clean-safe.sh"
1
$ grep -c 'PREVIEW — nothing will be deleted' "$D/scripts/clean-safe.sh"
1
```
