# Changelog

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
