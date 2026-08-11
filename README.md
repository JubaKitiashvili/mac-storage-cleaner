# mac-storage-cleaner

**A Claude skill that safely reclaims disk space on a Mac — the trustworthy, transparent, reversible alternative to CleanMyMac and the dozens of "cleaner" apps.**

The problem with one-click cleaners isn't that they don't free space — it's that you can't *see* what they're about to delete or *undo* it if they're wrong. This skill flips that. It's driven by Claude, so it reasons about every location, shows you the plan before touching anything, deletes only what provably regenerates, moves anything riskier to the **Trash** (not `rm`), and **logs every action**.

> Just tell Claude *"my Mac is out of space"* (or *"clear my caches"*, *"what's eating my storage"* — it understands other languages too, including Georgian *"ადგილი აღარ მაქვს"*) and the skill takes over.

---

## Why it's different

| | Typical cleaners | mac-storage-cleaner |
|---|---|---|
| Shows what it'll delete first | sometimes | **always** (read-only survey) |
| Reversible | rarely | **yes** — anything non-cache goes to Trash |
| Auto-deletes | broad, opaque | **only a vetted allowlist of pure caches** |
| Audit trail | no | **every deletion logged** |
| Finds app leftovers / big files | paid feature | **built in** |
| Trust model | "just trust the app" | **it reasons and explains, you decide** |

## How it works

1. **Survey (read-only).** Sizes every cache that actually exists on your Mac, grouped into **safe / ask / never**. Nothing is deleted.
2. **Clear the safe tier.** Only a hand-vetted allowlist of pure caches (npm, gradle, pip, Xcode DerivedData, Homebrew, …) — the *only* cost is a slower next build. Deleted directly so the space comes back immediately, and every path is logged.
3. **Ask before anything expensive.** Docker images, ML models, simulator devices, Xcode Archives — surfaced with sizes and a recommendation. You choose; these are **never** auto-deleted.
4. **Beyond caches.** Optionally finds leftover data from apps you uninstalled, big files, and stale installers — all removed **reversibly, into the Trash**.
5. **Report honestly.** Before/after free space, what was cleared, and the log path. If macOS holds freed space as "purgeable," it explains that instead of pretending.

Full tiered inventory, exact reclaim commands, and edge-case notes live in [`skills/mac-storage-cleaner/references/cache-catalog.md`](skills/mac-storage-cleaner/references/cache-catalog.md).

## Safety

- **Auto-deletes only pure caches** on an explicit allowlist — never your data.
- **The "never" tier is enforced in code, not just policy**: iOS backups, Photos libraries, Keychains, Mail/Messages data, `~/.ssh`/`~/.aws`/`~/.gnupg` are *mechanically refused* by the deletion validator — even if the reasoning layer were ever wrong, the scripts won't touch them. A property test guarantees the allowlist and the deny list can never overlap.
- **Reversible by default** for everything else — a three-stage Trash chain (`/usr/bin/trash` → Finder → same-volume move), restorable until emptied.
- **Preview first**: `--dry-run` shows exactly what a run would do — guards and whitelist apply identically in preview and reality.
- **Fail-closed process guards**: caches whose owner may be live (Xcode toolchain, Gradle daemon, running Electron apps) are skipped, and "can't tell" always means "skip".
- **Keeps what you still need**: DeviceSupport symbol caches keep the 2 newest OS versions; auto-updating AI CLIs (Claude Code, Cursor, Copilot) keep the active version — pinned via its launcher symlink, never guessed from timestamps.
- **Your whitelist wins**: one path per line in `~/.config/mac-storage-cleaner/whitelist` protects it (and everything under it) from every automatic tier, case-insensitively.
- **No `sudo`** into system/SIP-protected areas.
- **Every action logged** to `~/Library/Logs/mac-storage-cleaner/operations.log` (5 MB rotation) — and the scripts *refuse to delete unlogged* unless you explicitly override.
- **Honest accounting**: partial removals reported as partial, unmeasurable sizes as `size?` (never fake zeros), survey totals exclude whitelisted items, APFS "purgeable" space explained instead of hand-waved.
- **68 automated tests** (bats), including a 40+-entry dangerous-path corpus where every entry *must* be refused, adversarial symlink cases, and a fake-`$HOME` harness so tests can never touch a real machine. Audited by an independent multi-model panel before release; bash 3.2-compatible (the version macOS ships).

## Install

### Option A — Claude Code plugin (recommended)

```
/plugin marketplace add JubaKitiashvili/mac-storage-cleaner
/plugin install mac-storage-cleaner@mac-storage-cleaner
```

### Option B — drop-in skill folder

```bash
git clone https://github.com/JubaKitiashvili/mac-storage-cleaner.git
cp -R mac-storage-cleaner/skills/mac-storage-cleaner ~/.claude/skills/
```

### Option C — single `.skill` file

Download [`dist/mac-storage-cleaner.skill`](dist/mac-storage-cleaner.skill) and install it via your Claude client.

## Usage

Once installed, it triggers automatically when you mention being out of space or wanting to clean up. Or invoke it directly:

```
/mac-storage-cleaner
```

Then just talk to it: *"free up space, but ask me before deleting anything big."*

Useful knobs (all optional):

| | |
|---|---|
| `--dry-run` (or `MSC_DRY_RUN=1`) | full preview, zero deletions, zero log writes |
| `~/.config/mac-storage-cleaner/whitelist` | paths/globs to always keep (case-insensitive, protects subtrees) |
| `MSC_DEVICE_SUPPORT_KEEP` (default 2) | how many DeviceSupport OS versions to keep |
| `MSC_AI_AGENTS_KEEP` (default 1) | old AI-CLI versions to keep besides the active one |

## What's new in 2.0

- "Never" tier promoted from documentation to **mechanically enforced subtree denials** (Photos, iOS backups, Keychains, Mail/Messages, SSH/AWS/GPG keys), wired into *every* deletion loop as defense-in-depth.
- `--dry-run`, user whitelist, fail-closed process guards, keep-N retention (DeviceSupport + AI CLIs).
- Three-stage reversible Trash chain with per-method audit logging and hard refusal of protected roots.
- New coverage: Android Studio/SDK, Carthage, Poetry, mise, composer/gem/conda, Handoff clipboard buffers (60-min age gate), crash reports (30-day age gate), guarded Electron/Chromium app caches, browser old-version framework reporting.
- Honest accounting throughout: partial-removal reporting, `size?` instead of fake zeros, whitelist-aware survey totals, refuse-to-delete-unlogged, log rotation.
- **68-test bats suite** with a property-tested dangerous-path corpus and a fake-`$HOME` isolation harness.

## Requirements

macOS. No dependencies beyond what ships with the OS (the skill uses the system `bash`, `du`, `df`, `osascript`, and optional `brew`/`xcrun` only if present).

## Contributing

Issues and PRs welcome — especially new cache locations, safety corrections, or tier reclassifications. When proposing a new auto-deletable path, please justify why its only cost is a slower next run.

## License

[MIT](LICENSE) © 2026 Juba Kitiashvili
