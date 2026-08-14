# Antigravity

- **Verified:** 2026-08-14
- **Agent version:** `2.5.0` (Antigravity.app `CFBundleShortVersionString`)
- **Install path used:** `~/.gemini/antigravity/skills/mac-storage-cleaner`

| Assertion | Result | Evidence |
|---|---|---|
| Resolution | ✅ | `D=/Users/macbook/.gemini/antigravity/skills/mac-storage-cleaner` — resolver script from SKILL.md run with `MSC_SKILL_ROOT` pinned to `~/.gemini/antigravity/skills` (see caveat in [codex-cli.md](codex-cli.md), which applies identically here — `$HOME/.claude/skills` is also populated and sorts earlier in the unmodified candidate order, and the unmodified resolver would also match the *unrelated* earlier `$HOME/.gemini/config/skills` candidate before reaching the Antigravity-specific root, if that path existed). |
| Trigger | unverified — requires an interactive session | Antigravity is a GUI application (`/Applications/Antigravity.app`) with no `antigravity` CLI binary on `PATH` and no CLI shim under its app bundle (`Contents/Resources/app/bin` does not exist). A separate `gemini` CLI (Google's Gemini CLI, v0.49.0, same `~/.gemini/` namespace but a distinct product) is on `PATH` and does have a real `gemini skills list` command — but it scans `~/.gemini/skills` and `~/.agents/skills` (plus its own bundled skills), **not** `~/.gemini/antigravity/skills`; running it confirms it does **not** discover the installed skill, which is expected since it is the wrong root for a different tool, and is therefore neither positive nor negative evidence about the Antigravity IDE itself. No non-interactive way was found to query whether the Antigravity GUI app discovers or loads skills from `~/.gemini/antigravity/skills/`. No controlled trigger-prompt test was run; this would require opening the Antigravity GUI. |
| Gating | ✅ | `grep -c '^APPLY=0$' "$D/scripts/clean-safe.sh"` → `1`; `grep -c 'PREVIEW — nothing will be deleted' "$D/scripts/clean-safe.sh"` → `1`. Grep-only, read-only — the script was never executed. |

## Verification commands (literal transcript)

Install:

```
$ mkdir -p ~/.gemini/antigravity/skills && rsync -a --delete ~/Desktop/Projects/mac-storage-cleaner/skills/mac-storage-cleaner/ ~/.gemini/antigravity/skills/mac-storage-cleaner/
$ ls ~/.gemini/antigravity/skills/mac-storage-cleaner
agents  references  scripts  SKILL.md
$ test -f ~/.gemini/antigravity/skills/mac-storage-cleaner/scripts/lib.sh && echo present
present
```

Resolution (subshell, `MSC_SKILL_ROOT` pinned to the Antigravity root only):

```
$ ( D=""; MSC_SKILL_ROOT="$HOME/.gemini/antigravity/skills"; for r in "${MSC_SKILL_ROOT:-/nonexistent}" "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/skills" "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.cursor/skills" "$HOME/.codex/skills" "$HOME/.config/opencode/skills" "$HOME/.gemini/config/skills" "$HOME/.gemini/antigravity/skills" "$HOME/.codeium/windsurf/skills" "$HOME/.hermes/skills" ".claude/skills" ".agents/skills" ".cursor/skills" ".windsurf/skills"; do [ -f "$r/mac-storage-cleaner/scripts/lib.sh" ] && { D="$r/mac-storage-cleaner"; break; }; done; echo "D=$D" )
D=/Users/macbook/.gemini/antigravity/skills/mac-storage-cleaner
```

Trigger (CLI probing — no `antigravity` CLI binary; a distinct `gemini` CLI exists but scans a different root):

```
$ command -v antigravity
(exit 1, no output)
$ ls /Applications/Antigravity.app/Contents/Resources/app/bin
ls: /Applications/Antigravity.app/Contents/Resources/app/bin: No such file or directory
$ command -v gemini
/Users/macbook/.nvm/versions/node/v22.22.0/bin/gemini
$ gemini --version
0.49.0
$ gemini skills list --all 2>&1 | grep -i "mac-storage\|antigravity"
antigravity-support [Enabled] [Built-in]
  Description: Use when the user asks questions, seeks help, or requests instructions related to installing, setting up, or migrating to Antigravity CLI. This skill provides the latest up to date details, requirements, and commands sourced from the official Antigravity CLI documentation.
  Location:    /Users/macbook/.nvm/versions/node/v22.22.0/lib/node_modules/@google/gemini-cli/bundle/builtin/antigravity-support/SKILL.md
```

(`mac-storage-cleaner` does not appear in `gemini skills list` output — expected, since that
command scans `~/.gemini/skills` and `~/.agents/skills`, not `~/.gemini/antigravity/skills`
where this skill was installed. The one match, `antigravity-support`, is an unrelated
built-in Gemini CLI skill about installing "Antigravity CLI" — a separate product from
the `/Applications/Antigravity.app` GUI IDE detected for this row. This does not confirm
or deny whether the Antigravity IDE itself loads the installed skill.)

Gating (installed copy, read-only, script never executed):

```
$ grep -c '^APPLY=0$' "$D/scripts/clean-safe.sh"
1
$ grep -c 'PREVIEW — nothing will be deleted' "$D/scripts/clean-safe.sh"
1
```
