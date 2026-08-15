# Changelog

## 3.0.1 — 2026-08-15

### Fixed
- **`trash-items.sh` size cap could silently fail to fire.** `MSC_MAX_TRASH_GB`
  (and `MSC_MAX_TRASH_ITEMS`) were validated as all-digits, but an all-digit
  string like `08` is an invalid octal literal in bash arithmetic. That made
  `$((MAX_GB * 1024 * 1024))` abort with `value too great for base`, which
  made the enclosing size-cap `if` never take either branch — a fail-open in
  a safety guard. Both limits are now normalized to decimal (`$((10#$VAR))`)
  right after validation, so every later use — arithmetic and the
  user-facing refusal message alike — sees a clean decimal instead of a
  value that could error out or print as `08GB`.

## 3.0.0 — 2026-08-14

Cross-agent release: the skill now runs on every major AI coding agent, and its
default is no longer destructive.

### Breaking
- **`clean-safe.sh` previews by default.** Deleting requires `--apply`.
  `--dry-run` is still accepted as an alias, and `MSC_DRY_RUN=1` overrides
  `--apply` (the env var can only ever make a run safer). Several agents execute
  shell commands with no approval prompt, so a destructive default meant an agent
  could delete caches the user never saw proposed.
- **`trash-items.sh` refuses bulk operations.** Batches over 100 eligible items
  or 5 GB now exit 4 unless `--force` is the first argument
  (`MSC_MAX_TRASH_ITEMS`, `MSC_MAX_TRASH_GB`).
- **`trash-items.sh` rejects unknown leading flags.** Any argument after
  `--force` that starts with `-` and isn't `--dry-run` or `--` now exits 2
  instead of falling through to the path loop — previously an unrecognized
  flag like a typo'd `--dry-run` printed `not found: <flag>` and then
  trashed the remaining arguments for real, a preview request silently
  performing a real destructive run.

### Fixed
- **The skill now finds itself when installed by any agent.** Every SKILL.md
  command block searches all standard skill roots (Claude Code, Codex, Cursor,
  opencode, Antigravity, Windsurf, Hermes, `.agents/skills`, and project-scoped
  installs) instead of only `~/.claude/skills`, where an install anywhere else
  failed with "No such file or directory".

### Added
- `trash-items.sh --dry-run`, a real preview switch (same contract as
  `MSC_DRY_RUN=1`): previews what would be trashed and moves nothing.
  Composes with `--force` (`--force --dry-run` previews).
- Portable frontmatter: `license` plus a string-valued `metadata` map carrying
  version, author, platform and tags; the description is now asserted in bytes
  (972/1024) because Georgian trigger phrases cost 3 bytes per glyph.
- `agents/openai.yaml` (Codex display metadata and implicit invocation) and
  `.cursor-plugin/plugin.json` (Cursor Marketplace).
- A declared-behavior section in SKILL.md enumerating every destructive
  operation, for automated skill scanners.
- GitHub Actions CI on `macos-latest`: bats, shellcheck, SKILL.md bash-block
  linting and manifest version parity.
- `tools/bump-version.sh` — one command sets the version in all five places.
- Per-agent install matrix, per-agent safety table, and a telemetry disclosure in
  the README.

### Removed
- `dist/mac-storage-cleaner.skill` — built for a Claude Desktop upload flow that
  requires `.zip` and a ≤200-character description, so it was never installable
  there.

### Testing
- 131 tests (up from 89): resolver coverage for every documented install root
  (including the `MSC_SKILL_ROOT` escape hatch), the `--apply` gate, the
  blast-radius cap, frontmatter byte budget, manifest parity, a lint that
  `bash -n`s every command block in SKILL.md, and a post-release fix wave
  covering the `trash-items.sh` unknown-flag fail-open bug, `--force` consent
  logging, honest unmeasurable-size reporting, and the `clean-safe.sh`
  extra-argument gate.

## 2.0.6 — 2026-08-11

Fix for a cubic P2 finding, fallback path only: `_version_sort_desc`'s awk
key only used the first 4 numeric components, so names with more (e.g.
DeviceSupport's "18.5.1 (22G100)" = 18,5,1,22,100) tied on the key and fell
to a lexical tie-break where "22G100" sorted below "22G86" — a newer build
misclassified as older and deletable by keep-N. Key depth is now 8
components (covers every realistic version string with headroom), and any
name with a 9th+ numeric run left over makes the fallback fail closed: it
emits nothing for that directory rather than risk an ordering it can't
guarantee. The lexical tie-break still applies when two 8-component keys are
exactly equal (e.g. "22G76" vs "22F76"), which now only happens when the
numeric content is genuinely identical.

## 2.0.5 — 2026-08-11

Portable fallback for `version_sorted_children`'s retention ordering: it used
to fail CLOSED (print nothing, keep everything, silently) when `sort -V`
looked unsupported. That's now replaced with a new `_version_sort_desc`
helper that falls back to an awk-built lexical key (first 4 numeric
components, zero-padded) sorted with plain `sort -r` — same version order as
`sort -rV`, no silent no-op — so retention works even on a hypothetical
`sort` without `-V` support.

## 2.0.4 — 2026-08-11

Fix for a cubic P3 finding (PR #792): `_msc_remove_old_report`'s doc comment
claimed the same "rm with the skipped/partial honesty branch" as the keep-N
and app-cache loops, but its body only implemented a plain skip on a blocked
`rm` — no `chmod -R u+w` retry, no partial-removal accounting, so a crash
report that was only partly removable (or recoverable via a permission
retry) was misreported as a flat "skipped" instead of crediting freed bytes.
`_msc_remove_old_report` (shared by both the top-level `DiagnosticReports`
sweep and its `Retired` children) now retries a blocked `rm -rf` once with
`chmod -R u+w`, then — if the path still exists — compares before/after size
to report and log a `partial` outcome (crediting only the bytes actually
freed) instead of a blanket skip; the doc comment now states all three
possible outcomes (removed / partially removed / skipped) accurately.

## 2.0.3 — 2026-08-11

Fix for a cubic P1 finding (PR #792).

### Fixed
- **`DiagnosticReports/Retired` is no longer swept as one `rm -rf` unit** —
  the legacy `Retired` directory was matched by the top-level find and
  removed recursively, bypassing every per-item protection (30-day age,
  whitelist, `validate_target_path`) for whatever it contained: a
  whitelisted child, or a report file modified in place (fresh mtime) while
  the directory's own mtime stayed old. `Retired`'s direct children are now
  walked through the exact same per-item pipeline as top-level reports;
  only report artifacts older than 30 days are removed, and the (possibly
  emptied) `Retired` directory itself is never deleted.

## 2.0.2 — 2026-08-11

Fixes for a second round of external review findings.

### Fixed
- **Electron process guard: metachar-proof literal process probe** — `pgrep
  -f` patterns are ERE, so an app directory literally named e.g. `App
  (Beta)` built a regex whose parens were GROUPING, not literal characters,
  so the literal process name silently never matched its own process
  (empirically confirmed fail-open, rc 1). The two-probe `pgrep` check is
  replaced with a literal, case-insensitive `ps` snapshot + `grep -F` match
  against both process name and full command line — metachar-proof by
  construction. A failed/empty snapshot is still unknown state (skip), per
  the existing tri-state contract.
- **Control-char directory names now fail closed in retention scans** —
  `version_sorted_children` (DeviceSupport keep-N and the AI-agent version
  loop, which shares the same enumeration) now skips any child name
  containing a control character (e.g. an embedded newline) entirely:
  never counted toward the kept-N slots, never deleted. Such a name would
  otherwise corrupt the function's newline-delimited line protocol.
- **Handoff freshness scan is now rc-aware, not just match-aware** — an
  unreadable descendant inside a Handoff/Universal-Clipboard buffer makes
  `find`'s traversal exit non-zero without necessarily finding a fresh
  file; that's an inconclusive scan, not evidence of idleness, so a
  non-zero `find` exit now also skips the candidate (previously only a
  found match did).
- **`DiagnosticReports` cleanup now targets only report artifacts** — the
  30-day-old enumeration under `~/Library/Logs/DiagnosticReports` is
  restricted to files matching `*.ips *.crash *.diag *.spin *.hang *.panic
  *.shutdownStall` (case-insensitive) plus the legacy `Retired` directory,
  instead of sweeping up anything old sitting in that folder (e.g. a
  user's own notes file or an unrelated subdirectory).
- **`survey.sh` Electron cache listing aligned with `clean-safe.sh`** — the
  Application Support scan now also uses `-mindepth 2`, so a hypothetical
  top-level `~/Library/Application Support/Cache` is never listed as
  auto-clearable (it never was auto-cleared; the survey just previously
  over-reported it).
- **Narrower system-root subtree denials** — `validate_target_path` now
  denies `/System`, `/bin`, `/sbin`, `/dev`, and `/private/var/db` as full
  subtrees (path equals or is under), not just their bare roots.
  Deliberately scoped: `/Library`, `/Applications`, `/usr`, and `/var` stay
  bare-root-only denials, since legitimate workflows need to reach inside
  them (a leftover `/Library/LaunchAgents` plist, `/usr/local` Homebrew
  cruft, `/private/tmp` scratch caches).

### Note
An earlier review claimed the stock macOS `sort` lacks `-V` (version sort).
That claim was tested directly on this machine's shipped `/usr/bin/sort`
(macOS's bundled 2.3-Apple `sort`) and is **false** — it supports `-V` fine.
The fail-closed `sort -V` capability probe added in 2.0.1 stays in place
regardless, as protection for hypothetical older/non-Apple `sort`
implementations this could run under.

### Testing
- 80-test bats suite (up from 76): new coverage for the metachar-proof
  Electron probe (literal-parens app name, idle-vs-running-vs-unknown `ps`
  states), control-char retention-name fail-closed, rc-aware Handoff
  freshness scan on an unreadable descendant, `DiagnosticReports` artifact
  filtering, and the narrowed system-root subtree denials.

## 2.0.1 — 2026-08-11

Fixes for the external Greptile + cubic code-review findings raised on the
marketplace PR (davila7/claude-code-templates#792) against the 2.0.0 release.

### Fixed
- **Electron process guard no longer fails open on a name mismatch** (Greptile
  P1): the folder-name-vs-process-name probe is now a both-directions,
  case-insensitive check (`pgrep -qix` exact-name OR `pgrep -qif` command-line
  substring) — over-matching only ever costs an extra skip; only a clean
  double miss counts as idle.
- **DeviceSupport keep-N retention now orders by OS version, not mtime**
  (Greptile): `keep_newest_n_children` enumerates via a newline-safe glob and
  sorts with `sort -rV`, falling closed (keeps everything) if this `sort`
  lacks `-V`. The AI-agent version loop was switched to the same
  glob+version-sort enumeration for consistency (semver sorts correctly under
  `-V` too).
- **Symlinked retention roots no longer let deletion walk through to the
  target** (cubic P0): the DeviceSupport keep-N loop, the AI-agent versions
  loop, `DiagnosticReports`, and the Electron cache scan's `Application
  Support` base now explicitly refuse a symlinked base (`skipped (symlink
  base)`, logged, counted) instead of silently following it via `[ -d ]`.
- **Handoff age gate is now content-aware, not just top-level-mtime-aware**
  (cubic P1): a candidate directory is skipped if any descendant was modified
  in the last 60 minutes, even when the directory's own mtime looks old —
  never cuts an in-flight multi-file sync.
- **NUL-delimited enumeration in every `find`-driven deletion loop** (cubic
  P1): the Handoff, `DiagnosticReports`, and Electron cache-dir loops now read
  from `find ... -print0` via process substitution (`< <(...)`, bash
  3.2-safe) instead of a newline-delimited heredoc, and keep counters in the
  calling shell (not a pipe subshell).
- **Unresolved `Current` symlink no longer produces a misleading browser-
  framework report** (cubic P2): `find-extras.sh` now prints a
  could-not-resolve notice and skips suggestions for that framework instead
  of listing every version as if none were "Current".
- **Survey no longer overclaims what's auto-cleared** (cubic P2): the
  Electron/browser cache section in `survey.sh` is split into an "Electron
  apps" listing under the auto-clear title and a separately-labeled "browser
  profile caches (NOT auto-cleared)" subsection.
- **`trash-items.sh` exit-code contract clarified** (cubic P2): added
  `previewed`/`missing` counters; exit is `1` on any failure, `2` only when
  nothing was moved or previewed AND at least one item was refused (so a
  mixed valid+refused dry-run now exits `0`; an all-refused run, dry or real,
  still exits `2`; a missing-only run exits `0` with the count called out).

### Testing
- 76-test bats suite (up from 68): new coverage for both-direction Electron
  matching, version-ordering-beats-mtime retention, symlinked-base refusal,
  Handoff content freshness, and the trash-items.sh exit-code contract.

## 2.0.0 — 2026-08-11

Hardening release: safety mechanisms inspired by a deep comparative audit against
[tw93/mole](https://github.com/tw93/mole), followed by an independent multi-model
security panel (25 commits, 68 tests).

### Safety
- **Never-tier enforced in code**: subtree denials for iOS backups (MobileSync),
  Photos libraries, Keychains, Mail, Messages, `~/.ssh`, `~/.aws`, `~/.gnupg` —
  refused by `validate_target_path`, which now also runs as defense-in-depth
  inside every automatic deletion loop. A property test guarantees the safe-tier
  allowlist and the deny list never overlap.
- Three-stage Trash chain (`/usr/bin/trash` → Finder → same-volume `mv`) with
  per-method logging; symlinks get consistent link-only semantics (the Finder
  stage is skipped for them — AppleScript alias coercion resolves to the target).
- Fail-closed tri-state process guards (Xcode family, Gradle daemon, running
  Electron apps): *unknown* always means *skip*.
- Deletion refuses to run if the audit log is unwritable (`MSC_ALLOW_UNLOGGED=1`
  overrides); `operations.log` rotates at 5 MB.
- Fixed: word-splitting on `$HOME` containing spaces/glob chars; locale-dependent
  case folding; whitelist case-sensitivity on case-insensitive APFS; `#` in
  whitelisted paths; trailing-slash `$HOME` disabling home-relative denials.

### Features
- `--dry-run` / `MSC_DRY_RUN=1` — full preview with guards and whitelist applied
  identically to a real run; zero deletions, zero log writes.
- User whitelist: `~/.config/mac-storage-cleaner/whitelist` (case-insensitive,
  protects subtrees, honored by every automatic tier).
- Keep-N retention: DeviceSupport keeps the 2 newest OS versions
  (`MSC_DEVICE_SUPPORT_KEEP`); AI CLIs (Claude Code, Cursor, Copilot) keep the
  active version — resolved via launcher symlink, never mtime — plus
  `MSC_AI_AGENTS_KEEP` previous ones.
- New coverage: Android Studio/SDK caches, `~/.android/avd` (ask-tier), Carthage,
  Poetry, mise, Composer, RubyGems, conda (owner command only), Handoff/Universal
  Clipboard buffers (60-minute age gate), `DiagnosticReports` (30-day age gate),
  guarded Electron/Chromium app caches, browser old-version framework report,
  simulator-runtime reporting.
- Honest accounting: partial removals reported as `partially removed`,
  unmeasurable sizes as `size?`, survey totals exclude whitelisted entries,
  end-of-run skip rollup.

### Testing
- 68-test bats suite: fake-`$HOME` isolation harness, 40+-entry dangerous-path
  corpus (every entry must be refused; the corpus has a size floor so deleting
  test cases fails the build), adversarial symlink cases, `/bin/bash` 3.2 pinning.

## 1.0.0 — 2026-07-14

Initial release: read-only survey, safe-tier allowlist cleanup, ask-tier
recommendations, app-leftover/big-file/installer discovery, Finder-Trash
reversible removal, per-action audit log.
