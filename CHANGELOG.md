# Changelog

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
