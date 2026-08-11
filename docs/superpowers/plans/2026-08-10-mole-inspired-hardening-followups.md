# Mole-inspired hardening — deferred follow-ups (post-merge triage)

Final whole-branch review triaged all deferred minors as defer-ok. Kept here as the
in-repo record (SDD workspace was removed per process; git history holds the rest).

- Whitelist: absolute entries (no ~) stop matching under a trailing-slash $HOME (fails toward less protection, never more deletion) — the load_whitelist analog of the fixed C1.
- AI-agents loop: a whitelisted version dir consumes a keep slot instead of freeing it (deletion set stays a strict subset — safe direction; mirrors keep-N semantics).
- clean-safe.sh --dry-run <extra-junk>: extra args after a valid --dry-run are ignored (fails safe into preview).
- trash-items.sh dry-run prints the "Log:" path line although nothing was logged (cosmetic).
- tests: make_stub STUB_DIR never cleaned (bounded /tmp litter); duplicate PATH entries per call.
- lib.sh: system-roots deny is exact-match by design (e.g. /Library/LaunchAgents/<file> allowed — needed for legitimate leftover cleanup; Trash is reversible).
- keep-N numeric guard accepts "007" (displayed literally; compares fine).
- No test for trash_path true rc-1 (all three stages fail) path.
- cache-catalog conda row: ask-tier prose vs auto owner-command in clean-safe — add clarifying sentence on next catalog pass.
- SKILL.md: MSC_DRY_RUN / MSC_AI_AGENTS_KEEP / MSC_WHITELIST_FILE not yet listed in an env-var reference block.
- Structural tripwire idea (from incident review): scripts could refuse to run when MSC_EXPECT_FAKE_HOME=1 and $HOME is not under a temp root — cheap ad-hoc-probe protection for future development.

## Post-audit deferrals (tech-lead panel audit, 2026-08-11)
- Newline-in-name children in keep-N/AI ls-1t parsing: split halves fail -e and skip (fail-safe); only exploitable if a half coincides with a real sibling name. Revisit with a glob-based mtime sort if ever rewritten.
- Per-stage revalidation/dev:inode binding in trash chain (Codex TOCTOU hypothesis): single-operator tool, symlink divergence already fixed by Finder-stage skip; defer.
- DARWIN_USER_CACHE_DIR per-user /var/folders cache age-gate: novel, no prior art in either project — research separately.
- mdfind timeout (fail-closed) in container_is_orphan: needs a perl/bg-kill wrapper on stock macOS; defer.
- ~/.orbstack ask-row marked verify-layout-first; confirm data conventions before advising deletion.
- A3 DiagnosticReports per-child symlink skip mirrors Handoff (silent continue) while A4 logs+counts — cosmetic inconsistency, unify on next touch.
- AI-CLI retention flagged by deep-reasoner as "least justified complexity per GB" — counterpoint: this machine had 4 stale Claude Code versions; keep, revisit if it ever causes a fix round.
