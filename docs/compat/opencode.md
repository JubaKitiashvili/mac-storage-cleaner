# opencode

- **Verified:** 2026-08-14
- **Agent version:** `1.14.22` (via `opencode --version`)
- **Install path used:** `~/.config/opencode/skills/mac-storage-cleaner`

| Assertion | Result | Evidence |
|---|---|---|
| Resolution | ✅ | `D=/Users/macbook/.config/opencode/skills/mac-storage-cleaner` — resolver script from SKILL.md run with `MSC_SKILL_ROOT` pinned to `~/.config/opencode/skills` (see caveat in [codex-cli.md](codex-cli.md), which applies identically here — `$HOME/.claude/skills` is also populated and sorts earlier in the unmodified candidate order) found `scripts/lib.sh` at this path. |
| Trigger | unverified — requires an interactive session | `opencode --help` was checked for a skills-listing subcommand. Its command tree has `opencode agent list` (lists *agents*, a distinct opencode concept from filesystem skills) but no `skills`/`skill` subcommand of any kind. No non-interactive way was found to confirm opencode discovers or loads a skill from `~/.config/opencode/skills/`. No controlled trigger-prompt test was run; this would require an interactive `opencode` session. |
| Gating | ✅ | `grep -c '^APPLY=0$' "$D/scripts/clean-safe.sh"` → `1`; `grep -c 'PREVIEW — nothing will be deleted' "$D/scripts/clean-safe.sh"` → `1`. Grep-only, read-only — the script was never executed. |

## Verification commands (literal transcript)

Install:

```
$ mkdir -p ~/.config/opencode/skills && rsync -a --delete ~/Desktop/Projects/mac-storage-cleaner/skills/mac-storage-cleaner/ ~/.config/opencode/skills/mac-storage-cleaner/
$ ls ~/.config/opencode/skills/mac-storage-cleaner
agents  references  scripts  SKILL.md
$ test -f ~/.config/opencode/skills/mac-storage-cleaner/scripts/lib.sh && echo present
present
```

Resolution (subshell, `MSC_SKILL_ROOT` pinned to the opencode root only):

```
$ ( D=""; MSC_SKILL_ROOT="$HOME/.config/opencode/skills"; for r in "${MSC_SKILL_ROOT:-/nonexistent}" "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/skills" "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.cursor/skills" "$HOME/.codex/skills" "$HOME/.config/opencode/skills" "$HOME/.gemini/config/skills" "$HOME/.gemini/antigravity/skills" "$HOME/.codeium/windsurf/skills" "$HOME/.hermes/skills" ".claude/skills" ".agents/skills" ".cursor/skills" ".windsurf/skills"; do [ -f "$r/mac-storage-cleaner/scripts/lib.sh" ] && { D="$r/mac-storage-cleaner"; break; }; done; echo "D=$D" )
D=/Users/macbook/.config/opencode/skills/mac-storage-cleaner
```

Trigger (CLI probing — command tree has no skills subcommand):

```
$ opencode --help
...
Commands:
  opencode completion          generate shell completion script
  opencode acp                 start ACP (Agent Client Protocol) server
  opencode mcp                 manage MCP (Model Context Protocol) servers
  opencode [project]           start opencode tui                                          [default]
  opencode attach <url>        attach to a running opencode server
  opencode run [message..]     run opencode with a message
  opencode debug               debugging and troubleshooting tools
  opencode providers           manage AI providers and credentials                   [aliases: auth]
  opencode agent               manage agents
  ...
$ opencode agent --help
opencode agent
manage agents
Commands:
  opencode agent create  create a new agent
  opencode agent list    list all available agents
```

(`agent` here means opencode's own agent-persona concept, not the filesystem
skill installed above; no subcommand inspects `~/.config/opencode/skills/`.)

Gating (installed copy, read-only, script never executed):

```
$ grep -c '^APPLY=0$' "$D/scripts/clean-safe.sh"
1
$ grep -c 'PREVIEW — nothing will be deleted' "$D/scripts/clean-safe.sh"
1
```
