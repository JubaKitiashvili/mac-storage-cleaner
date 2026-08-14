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
