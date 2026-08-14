# Cross-Agent Distribution — Design (v3.0.0)

**Status:** approved for planning · **Date:** 2026-08-14 · **Supersedes:** nothing

## Goal

Make `mac-storage-cleaner` **natively usable and verifiably functional** on the major AI
coding agents, not merely discoverable by them. Success has two halves:

1. **One universal install command** works: `npx skills add JubaKitiashvili/mac-storage-cleaner`
   (already true today) — *and the skill actually runs after installing that way* (not true today).
2. **Registry presence** on the self-serve registries that matter: skills.sh, ClawHub,
   Cursor Marketplace, plus the existing aitmpl listing.

The skill stays **macOS-only**. This is about agent portability, not OS portability.

**Wave 1 (targeted):** OpenAI Codex + Codex CLI, Cursor, Windsurf (now "Devin Desktop"),
Google Antigravity.
**Wave 2 (near-free, same mechanism):** opencode, OpenClaw, Hermes Agent.
**Declared unsupported:** Claude Desktop / claude.ai (see D9).

## Non-goals

Windows/Linux support · a bespoke installer or npm package · submission to
`google/skills` (a Google-Cloud venue) · Anthropic's official plugin directory
(it serves Desktop, where the skill cannot function) · a PR to Hermes' official
optional-skills catalog (later wave) · rewriting the cleaning logic.

## Background — the facts that drive the decisions

Verified live, August 2026:

- SKILL.md is now a **cross-vendor standard** (agentskills.io), natively supported by every
  target agent.
- **Cursor, Windsurf and opencode read `~/.claude/skills/` and `.claude/skills/` directly**, so
  a Claude Code skill is already visible to them.
- `npx skills add JubaKitiashvili/mac-storage-cleaner` (Vercel skills CLI, 76 agents) already
  discovers and installs this repo correctly — empirically verified.
- **skills.sh listing is automatic** for public GitHub repos via the installer's telemetry;
  there is no PR or form.
- **Execution-approval models differ sharply.** Claude Code prompts per bash command; Cursor
  has a sandbox plus explicit file-deletion protection; Antigravity's own docs deny-list
  `command(rm -rf)`; Windsurf has four auto-exec levels. But **opencode defaults to
  allow-bash with no prompts**, and **OpenClaw defaults to `security="full", ask="off"`** —
  host execution with no approval at all.
- **ClawHub scans daily** (VirusTotal + Code Insight) and compares *declared* behavior against
  *actual* behavior; undeclared destructive operations are flagged suspicious or blocked.
  Hermes scans at install time for destructive commands.
- **Claude Desktop / claude.ai cannot run this skill for real**: chat executes skill scripts in
  Anthropic's server-side container, and Cowork in a VM restricted to explicitly connected
  folders. Neither can reach `~/Library/Caches`.

## Decisions

### D1 — Portable skill-directory resolution (the blocking defect)

**Problem.** All four command blocks in `SKILL.md` resolve the skill directory as:

```bash
D="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/mac-storage-cleaner}"; D="${D:-$HOME/.claude/skills/mac-storage-cleaner}"
```

`~/.claude/skills/` is the only fallback. Installed to `~/.cursor/skills/`, `~/.codex/skills/`,
`~/.config/opencode/skills/`, `~/.gemini/…`, a Hermes tap, or a **project-scoped
`.claude/skills/`**, every command fails with *No such file or directory*. Without this fix the
rest of the work makes the skill discoverable on 76 agents and functional on one.

**Decision.** Replace the two-candidate expression with a **candidate-root search** that probes
for a marker file (`scripts/lib.sh`) and fails loudly, listing what it searched. The snippet
stays **inline and self-contained** in each command block — a separate resolver script cannot be
used, because finding *it* is the same problem. Shell state does not persist between the agent's
command invocations, which is why the block is repeated today and stays repeated.

Candidate roots, in order (global first, then project-scoped):

```
$CLAUDE_PLUGIN_ROOT/skills   ~/.claude/skills   ~/.agents/skills   ~/.cursor/skills
~/.codex/skills              ~/.config/opencode/skills             ~/.gemini/config/skills
~/.gemini/antigravity/skills ~/.codeium/windsurf/skills            ~/.hermes/skills
./.claude/skills             ./.agents/skills   ./.cursor/skills   ./.windsurf/skills
```

Each command block becomes: resolve `$D` → hard-fail with a searched-paths message if empty →
run the script. Scripts already self-locate their own dependencies, so only the invocation path
changes.

### D2 — Safe by default: preview unless `--apply` (breaking, hence v3.0.0)

**Problem.** `clean-safe.sh` with no arguments deletes; `--dry-run` is opt-in. On opencode and
OpenClaw an agent runs bash with no approval prompt, so the obvious invocation deletes caches
the user never saw proposed. A prose rule in SKILL.md is a disclaimer, not enforcement — the
same model that reads the rule can ignore it in the same turn.

**Decision.** Invert the default. `clean-safe.sh` with no arguments performs a **preview** and
exits without deleting. Deletion requires the explicit `--apply` flag. `--dry-run` remains
accepted as a no-op alias (muscle memory, existing docs, the aitmpl copy). `MSC_DRY_RUN=1`
continues to force preview and, when set, **overrides `--apply`** (fail-safe direction). The
audit log records which consent path was taken (`consent=apply` / `consent=force`).

This is the one change that makes the skill safe on *every* agent regardless of that agent's
approval model, so it is worth a breaking CLI change and a major version.

**Honesty constraint.** No in-script check can distinguish an agent from a human. The claim we
make in docs is precisely: *there is no destructive default* — not *a human always approves*.

### D3 — Blast-radius cap on `trash-items.sh`

`trash-items.sh` takes arbitrary argv, which is the genuinely dangerous surface: an unsupervised
agent assembling a "big old files" list can bulk-trash a user's Downloads in one call. Refuse a
batch exceeding **100 items or 5 GB** unless `--force` is passed, printing the counts and the
exact command to proceed. Logged as `refused-blast-radius`. Existing per-path validation and
never-tier denials are unchanged and still run first.

### D4 — Frontmatter: verify, then ship

Hermes *requires* `version`, `author`, `license` in frontmatter; Cursor's documented schema
lists only `name`, `description`, `paths`, `disable-model-invocation`, `metadata`. Tolerance of
unknown top-level keys is verified for Codex (it has an explicit repair pass) and opencode
(documented as ignored), but **not** for Cursor, Windsurf or Antigravity — and a rejected key
fails validation rather than degrading.

**Decision.** A verification spike precedes the change: install a probe skill carrying the full
frontmatter into every locally installable target and confirm it loads. Ship the largest field
set that passes everywhere. Default plan (pending that spike): keep `name` and `description`
top-level, add `license: MIT` (an Anthropic-spec field), and add `version`, `author`,
`platforms`, `tags`, `category` plus a `hermes` namespace **inside `metadata:`**, which Cursor
documents and every other target ignores. If the spike shows top-level `version`/`author` are
tolerated everywhere, promote them (Hermes prefers them there).

**Description length.** The description is 872 characters but **972 bytes** (Georgian triggers
are 3 bytes per glyph) against opencode's 1024 limit — 52 bytes of headroom. Tests must assert
**bytes**, not characters, with a ≤1000-byte budget, so a future edit cannot silently break
opencode discovery.

### D5 — Destructive-behavior declaration at the mechanism level

ClawHub's scanner compares declared behavior with observed syscalls; a philosophical statement
does not satisfy it. The declaration enumerates the actual operations: `rm -rf` restricted to the
safe allowlist, the `chmod -R u+w` retry, `mv` into `~/.Trash`, `/usr/bin/trash`, **`osascript`
driving Finder's `delete`** (the most likely "suspicious" trigger if undeclared), `brew cleanup
-s --prune=all`, `conda clean`, `xcrun simctl delete unavailable`, `mdfind` reads, and writes to
`~/Library/Logs/mac-storage-cleaner/`. It also states what is mechanically refused.

### D6 — Adapter files: only those with a behavioral or submission purpose

- **`skills/mac-storage-cleaner/agents/openai.yaml`** — kept for `policy.allow_implicit_invocation`
  and display metadata, which affect Codex triggering.
- **`.cursor-plugin/plugin.json`** — added, because the Cursor Marketplace submission is in scope
  this release. Without that submission it would buy nothing (Cursor already reads
  `~/.claude/skills/`).
- **`.codex-plugin/…`** — dropped. Codex CLI 0.146+ consumes Claude Code plugin marketplaces, and
  we already ship `.claude-plugin/marketplace.json`; a second manifest for an unverified path is
  speculation. Verify the existing one is consumed; only then reconsider.

### D7 — CI (prerequisite, not polish)

There is no `.github/` today: 89 tests run only by hand while the README badge asserts them.
Before four registry publications, add GitHub Actions on `macos-latest`:

1. `bats tests/`
2. `shellcheck` over the skill's scripts
3. **SKILL.md bash-block lint** — extract every ` ```bash ` block and `bash -n` it (this check
   would have caught D1's drift)
4. frontmatter validation (name regex, byte-length budget, required fields)
5. **version parity** across `SKILL.md` metadata, both `.claude-plugin/*.json`, and
   `.cursor-plugin/plugin.json`

CI is also the cheapest credible artifact for ClawHub, Hermes and Cursor reviewers.

### D8 — `dist/mac-storage-cleaner.skill`: deprecate, don't delete

`README.md:70` links it; deleting it in this release breaks an externally referenceable URL.
Mark it deprecated in README and CHANGELOG this release, remove it in the next minor. The
CHANGELOG must state the accurate reason: Claude Desktop requires a **`.zip`** whose root is the
skill folder and caps `description` at 200 characters, so this artifact was never installable
there — it is being retired as misleading, not merely as unsupported.

### D9 — README rework, including an honest "why not Claude Desktop"

Universal install command at the top; a per-agent install matrix (agent → command → where it
lands); a **"How safety works on your agent"** section naming each agent's approval model and
stating plainly that on opencode and OpenClaw there is **no prompt**, so the preview-by-default
rule (D2) and the skill's internal tiers are the guardrails; a Claude Desktop section explaining
the sandbox architecture that makes real cleanup impossible there; and a **telemetry disclosure**
— the skill itself transmits nothing, but `npx skills add` reports installs to skills.sh, which
is what produces the listing.

SKILL.md's own Tests section is corrected at the same time: it currently tells the agent to run
`bats tests/` "from the repo root", which does not exist inside an installed skill — it must
point at the GitHub repository instead.

### D10 — Verification: a compat matrix with pinned versions

No agent can be fully automated in CI, so credible evidence is a recorded manual pass. For each
target, `docs/compat/<agent>.md` records agent version, date, and three assertions:

- **Resolution** — after installing through that agent's own path, the D1 snippet finds the skill
  and `scripts/lib.sh` exists. (Mechanical.)
- **Trigger** — one fixed prompt ("my mac is out of space") causes the agent to load the skill.
  This is the risk no manifest fixes: the description is tuned for Claude's selector, and
  "natively usable" fails silently if Codex or Cursor never invoke it.
- **Gating** — `clean-safe.sh` with no arguments deletes nothing.

Top three targets are re-verified each release.

### D11 — Version parity has a single source of truth

After D6 the version appears in `SKILL.md` metadata, `.claude-plugin/plugin.json`,
`.claude-plugin/marketplace.json` (twice), `.cursor-plugin/plugin.json`, `agents/openai.yaml`,
CHANGELOG and the git tag. A `scripts/bump-version.sh` (repo tooling, not shipped in the skill)
writes them all from one argument; the CI parity check (D7.5) fails the build on drift.

### D12 — Sequencing: reversible work first, publications last

1. CI green (D7) on the current tree.
2. Code: D1 resolver → D2 `--apply` → D3 cap, each with tests.
3. D4 frontmatter spike, then the frontmatter change.
4. Manifests (D6), docs (D5, D8, D9), compat scaffolding (D10), bump tooling (D11).
5. Tag **v3.0.0**, push.
6. Manual per-agent verification (D10) — recorded before any publication.
7. Publications, in this order: **skills.sh seed** (one telemetry-enabled install) →
   **`clawhub publish`** (claims a namespace and starts daily scans) → **Cursor Marketplace form**
   (human review queue).
8. Update the open aitmpl PR #792 to v3.0.0 with an explanatory comment (decision: one version
   everywhere, no divergence).

Publications are the irreversible half and must not precede verification.

## Testing strategy

New bats coverage, added alongside the existing 89:

- `resolve.bats` — the D1 candidate list covers every documented install root; a skill placed in
  each root is found; an absent skill produces the loud failure, not a silent one.
- `apply-gate.bats` — no args deletes nothing and exits 0 with preview output; `--apply` deletes;
  `--dry-run` still previews; `MSC_DRY_RUN=1` overrides `--apply`; consent mode reaches the log.
- `blast-radius.bats` — 101 items and a >5 GB batch are both refused without `--force` and pass
  with it; the refusal is logged; small batches are unaffected.
- `frontmatter.bats` — name regex, **byte** budget ≤1000, required fields present, YAML parses.
- `manifests.bats` — every manifest carries the same version; JSON is valid.

Plus the CI-only SKILL.md bash-block lint. Existing tests must stay green; the `--apply`
inversion will require updating tests that assume the old default.

## Risks

- **Frontmatter rejection** on an unverified agent — mitigated by the D4 spike and by keeping the
  risky fields inside `metadata:`; rollback is deleting keys.
- **Trigger failure** (agent never invokes the skill) — the description is Claude-tuned. D10's
  trigger assertion surfaces it; the fix, if needed, is description tuning within the byte budget.
- **ClawHub flags the skill anyway** — the D5 declaration is the mitigation; if flagged, the
  response is publishing the declaration diff, not weakening the skill.
- **v3.0.0 breaks a user's muscle memory** — `--dry-run` still works, and the new default is the
  safe direction; CHANGELOG leads with the change.
