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
- **Reversible by default** for everything else (Trash via Finder, restorable until emptied).
- **Never touches** iOS backups, Photos/Mail/Messages data, keychains, credentials, whole app-support folders, or Time Machine snapshots — it reports their size and leaves them alone.
- **No `sudo`** into system/SIP-protected areas.
- **Every action logged** to `~/Library/Logs/mac-storage-cleaner/operations.log`.
- Reviewed adversarially (multi-agent code review) before release; bash 3.2-compatible (the version macOS ships), handles read-only files, TCC-protected paths, and a fresh Mac with no caches.

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

## Requirements

macOS. No dependencies beyond what ships with the OS (the skill uses the system `bash`, `du`, `df`, `osascript`, and optional `brew`/`xcrun` only if present).

## Contributing

Issues and PRs welcome — especially new cache locations, safety corrections, or tier reclassifications. When proposing a new auto-deletable path, please justify why its only cost is a slower next run.

## License

[MIT](LICENSE) © 2026 Juba Kitiashvili
