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
| Claude Code | 2026-08-14 | see file | ✅ | ✅* | ✅ |
| Codex CLI | 2026-08-14 | 0.144.5 | ✅ | unverified — requires an interactive session | ✅ |
| Cursor | 2026-08-14 | 3.15.19 | ✅ | unverified — requires an interactive session | ✅ |
| Windsurf | 2026-08-14 | 2.3.15 | ✅ | unverified — requires an interactive session | ✅ |
| Antigravity | 2026-08-14 | 2.5.0 | ✅ | unverified — requires an interactive session | ✅ |
| opencode | 2026-08-14 | 1.14.22 | ✅ | unverified — requires an interactive session | ✅ |

\* Not a controlled test of the fixed trigger prompt — see the "Trigger" row's
evidence in [claude-code.md](claude-code.md) for what was actually verified.

For Codex CLI, Cursor, Windsurf, Antigravity, and opencode: Resolution and
Gating were verified directly against each agent's own installed copy (see
[codex-cli.md](codex-cli.md), [cursor.md](cursor.md), [windsurf.md](windsurf.md),
[antigravity.md](antigravity.md), [opencode.md](opencode.md)). Trigger could
not be verified for any of them — none exposes a non-interactive way to prove
a skill was actually loaded and invoked by the agent's model, so each file
records that honestly rather than inferring a pass from installation alone.
