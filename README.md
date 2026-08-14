# mac-storage-cleaner

[![version](https://img.shields.io/github/v/tag/JubaKitiashvili/mac-storage-cleaner?label=version&style=flat-square)](https://github.com/JubaKitiashvili/mac-storage-cleaner/blob/main/CHANGELOG.md)
[![tests](https://img.shields.io/badge/tests-120%20passing-brightgreen?style=flat-square)](#safety)
[![platform](https://img.shields.io/badge/platform-macOS-black?style=flat-square)](#requirements)
[![license](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)
[![aitmpl](https://img.shields.io/badge/listed%20on-aitmpl.com-8A2BE2?style=flat-square)](https://aitmpl.com)

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
- **Preview is the default**: a bare `clean-safe.sh` shows exactly what a run would do and deletes nothing; `--apply` performs it. Guards and whitelist apply identically in both, so the preview always matches reality.
- **Fail-closed process guards**: caches whose owner may be live (Xcode toolchain, Gradle daemon, running Electron apps) are skipped, and "can't tell" always means "skip".
- **Keeps what you still need**: DeviceSupport symbol caches keep the 2 newest OS versions; auto-updating AI CLIs (Claude Code, Cursor, Copilot) keep the active version — pinned via its launcher symlink, never guessed from timestamps.
- **Your whitelist wins**: one path per line in `~/.config/mac-storage-cleaner/whitelist` protects it (and everything under it) from every automatic tier, case-insensitively.
- **No `sudo`** into system/SIP-protected areas.
- **Every action logged** to `~/Library/Logs/mac-storage-cleaner/operations.log` (5 MB rotation) — and the scripts *refuse to delete unlogged* unless you explicitly override.
- **Honest accounting**: partial removals reported as partial, unmeasurable sizes as `size?` (never fake zeros), survey totals exclude whitelisted items, APFS "purgeable" space explained instead of hand-waved.
- **120 automated tests** (bats), including a 47-entry dangerous-path corpus where every entry *must* be refused, adversarial symlink cases, and a fake-`$HOME` harness so tests can never touch a real machine. Audited by an independent multi-model panel, then battle-tested through three external bot-review rounds (Greptile + cubic — 15 valid findings fixed, each with a regression test); bash 3.2-compatible (the version macOS ships).

### How safety works on your agent

The skill's own guardrails (allowlist-only deletion, mechanically refused
never-tier, Trash instead of `rm`, audit log) are identical everywhere. What
differs is whether your agent asks before running a command:

| Agent | Before a destructive command |
|---|---|
| Claude Code | prompts per command |
| Cursor | sandbox + explicit file-deletion protection for `rm` |
| Antigravity | permission lists; `command(rm -rf)` is a documented deny entry |
| Windsurf | four auto-execution levels; `rm` is a documented deny-list example |
| Codex | approval policy per session |
| **opencode** | **no prompt by default** |
| **OpenClaw** | **no prompt by default** (`security="full", ask="off"`) |

That is why `clean-safe.sh` **previews by default** and needs `--apply` to
delete, and why `trash-items.sh` refuses batches over 100 items or 5 GB without
`--force`. On a no-prompt agent those defaults are the only thing standing
between an over-eager agent and your files — no script can tell an agent from a
human, so the guarantee is *there is no destructive default*, not *a human always
approves*.

## Install

**Any agent — one command:**

```bash
npx skills add JubaKitiashvili/mac-storage-cleaner
```

This installs into whichever agents you have (Claude Code, Codex, Cursor,
Windsurf, opencode, Antigravity, Gemini CLI, Copilot CLI and ~70 more) via the
open [skills CLI](https://github.com/vercel-labs/skills). Add `-g` for a global
install, or `-a <agent>` to target one.

| Agent | Command | Lands in |
|---|---|---|
| Claude Code | `/plugin marketplace add JubaKitiashvili/mac-storage-cleaner` then `/plugin install mac-storage-cleaner@mac-storage-cleaner` | plugin root |
| Codex / Codex CLI | `npx skills add JubaKitiashvili/mac-storage-cleaner -a codex -g` | `~/.codex/skills/` |
| Cursor | `npx skills add JubaKitiashvili/mac-storage-cleaner -a cursor -g` | `~/.cursor/skills/` |
| Windsurf | `npx skills add JubaKitiashvili/mac-storage-cleaner -a windsurf -g` | `~/.codeium/windsurf/skills/` |
| Antigravity | `npx skills add JubaKitiashvili/mac-storage-cleaner -a antigravity -g` | `~/.gemini/antigravity/skills/` |
| opencode | `npx skills add JubaKitiashvili/mac-storage-cleaner -a opencode -g` | `~/.config/opencode/skills/` |
| Hermes Agent | `hermes skills install JubaKitiashvili/mac-storage-cleaner/skills/mac-storage-cleaner` | `~/.hermes/skills/` |
| OpenClaw | `openclaw skills install …` (see ClawHub listing) | OpenClaw skills dir |
| Manual | `git clone` then copy `skills/mac-storage-cleaner/` into any skills root | — |

> **Deprecated:** `dist/mac-storage-cleaner.skill` remains for one release only.
> It was built for Claude Desktop, which requires a `.zip` whose root is the
> skill folder and caps skill descriptions at 200 characters — so it was never
> installable there. Use the install commands above. The file will be removed in
> the next minor release.

### Claude Desktop / claude.ai — not supported, and here's why

Skills uploaded to Claude Desktop or claude.ai run their scripts in a sandbox:
in chat they execute in Anthropic's server-side container, and in Cowork inside a
VM that can only reach folders you explicitly connect. Neither can see
`~/Library/Caches`, `~/Library/Developer`, or your Trash — so a disk cleaner
there would report success while freeing nothing on your Mac. Use Claude **Code**
(or any of the agents above), which runs on your real filesystem with your
approval model.

> **Telemetry.** This skill sends nothing anywhere — it makes no network
> requests at all. The `npx skills add` installer, which is third-party, reports
> installs of public GitHub repositories to skills.sh; that is what produces the
> public listing. Install by cloning if you would rather not.

## Usage

Once installed, it triggers automatically when you mention being out of space or wanting to clean up. Or invoke it directly:

```
/mac-storage-cleaner
```

Then just talk to it: *"free up space, but ask me before deleting anything big."*

Useful knobs (all optional):

| | |
|---|---|
| `--apply` | actually delete (without it, a run only previews) |
| `--force` (trash-items.sh) | proceed past the 100-item / 5 GB bulk cap |
| `~/.config/mac-storage-cleaner/whitelist` | paths/globs to always keep (case-insensitive, protects subtrees) |
| `MSC_DEVICE_SUPPORT_KEEP` (default 2) | how many DeviceSupport OS versions to keep |
| `MSC_AI_AGENTS_KEEP` (default 1) | old AI-CLI versions to keep besides the active one |

## What's new in 2.x

- "Never" tier promoted from documentation to **mechanically enforced subtree denials** (Photos, iOS backups, Keychains, Mail/Messages, SSH/AWS/GPG keys, `/System` and friends), wired into *every* deletion loop as defense-in-depth.
- `--dry-run`, user whitelist, fail-closed process guards (with a metachar-proof literal process probe), keep-N retention ordered by **OS version, not mtime** (DeviceSupport + AI CLIs, symlink-pinned active version).
- Three-stage reversible Trash chain with per-method audit logging and hard refusal of protected roots.
- New coverage: Android Studio/SDK, Carthage, Poetry, mise, composer/gem/conda, Handoff clipboard buffers (60-min content-aware age gate), crash reports (30-day age gate, artifact-filtered), guarded Electron/Chromium app caches, browser old-version framework reporting.
- Honest accounting throughout: partial-removal reporting, `size?` instead of fake zeros, whitelist-aware survey totals, refuse-to-delete-unlogged, log rotation.
- **89-test bats suite** with a property-tested dangerous-path corpus and a fake-`$HOME` isolation harness.

Full version-by-version detail: [CHANGELOG.md](CHANGELOG.md).

## Requirements

macOS. No dependencies beyond what ships with the OS (the skill uses the system `bash`, `du`, `df`, `osascript`, and optional `brew`/`xcrun` only if present).

## Contributing

Issues and PRs welcome — especially new cache locations, safety corrections, or tier reclassifications. When proposing a new auto-deletable path, please justify why its only cost is a slower next run.

## License

[MIT](LICENSE) © 2026 Juba Kitiashvili
