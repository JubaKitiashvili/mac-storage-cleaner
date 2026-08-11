# Audit wave 2 — implementation report

Branch: `feat/mole-inspired-hardening`. Full test run: `bats tests/` — 68/68 green
(up from 60 baseline after wave 1; every new item added at least one focused
test except A2/A7/A9/A10, which are documented as report-only/code-reading/
doc-only per spec).

## Per-item status

| Item | Status | Notes |
|---|---|---|
| A1 — SAFE_PATHS additions (Carthage, Poetry, mise, Android Studio, `.android/{cache,build-cache}`) | Done | New commented group `# iOS/Android/tooling (audit wave 2)` appended to `SAFE_PATHS` in `lib.sh`; 7 corresponding rows added to the safe-tier catalog table. Test: `.android/cache` + `Library/Caches/pypoetry` both removed on a real run. |
| A2 — ASK_PATHS additions (`.android/avd`, Android SDK `system-images`, `.orbstack`) | Done | Appended to `ASK_PATHS` with inline comments; 3 ask-tier catalog rows added with the specified recommendations (per-AVD review, `sdkmanager --uninstall`, "verify layout — prefer OrbStack's own prune"). Report-only tier, no test per spec. |
| A3 — DiagnosticReports age-gated cleaner | Done | New section in `clean-safe.sh` placed after Handoff, mirroring its shape exactly (base symlink/whitelist gate, per-child symlink-continue + whitelist-skip, `validate_target_path`, DRY preview, rm + skipped/removed honesty branch). `find -mindepth 1 -maxdepth 1 -mtime +30`. Catalog row added. Test: 40-day-old crash file removed, fresh one survives, dry-run previews only. |
| A4 — Guarded Electron/Chromium Application Support cache auto-clean | Done | New section after A3 in `clean-safe.sh`. `find "$HOME/Library/Application Support" -mindepth 2 -maxdepth 2 -type d \( -name Cache -o "Code Cache" -o GPUCache -o DawnWebGPUCache \)`, app name derived from the first path component, symlink (dir+parent) → whitelist (dir+app-support root) → tri-state `pgrep -x "$app"` guard (running/unknown ⇒ skip, comment explicitly notes the app-name-vs-folder-name approximation is accepted/fail-closed) → `validate_target_path` → DRY → rm with partial/failure honesty. Newline-safe heredoc `while read`. Catalog Electron block + survey App-caches header both updated. New `tests/electron.bats` (4 tests): idle-removes, running-skips, dry-run previews, whitelist protects. |
| A5 — Deferred-skip rollup summary | Done | Added `skipped_inuse`/`skipped_wl`/`skipped_sym` counters, incremented alongside `skipped` in every symlink/whitelist/guard branch across all six loops (safe-tier, keep-N, AI-agent, Handoff, A3, A4). One rollup line printed before "Free space now:" — only non-zero parts, comma-joined, exact format from spec. Test: one whitelisted + one pgrep-guarded path → rollup line contains "1 in-use" and "1 whitelisted". |
| A6 — Log rotation | Done | `log_writable` in `lib.sh` now stats `operations.log` before the writability probe; `mv -f` to `.1` (best-effort, `2>/dev/null`) when > 5MB (single generation, mirrors mole). Test: 6MB fake log rotates to `.1`, fresh `operations.log` is writable and empty. |
| A7 — Size-unknown honesty | Done | `disp=$([ -n "$kb" ] && human_kb "$kb" || echo "size?")` pattern applied at every `kb=$(size_kb "$p")` site across all six deletion loops in `clean-safe.sh` and in `trash-items.sh`'s `sz` computation; used in every "would remove"/"removed"/"skipped" message and the corresponding `log_op` size column. `${kb:-0}` arithmetic guards left untouched (still 0 on unknown, so totals are never inflated). Not practically forceable in a portable bats test (`du` failure), so this is covered by code-reading only — full suite green confirms no regression. |
| A8 — Survey simulator runtimes line | Done | After the Docker.raw line in `survey.sh`'s ASK section: gated on `xcode-select -p` only (per spec — no `command -v xcrun` add-on), counts `xcrun simctl list runtimes 2>/dev/null \| grep -c " - "`, prints the runtimes-installed line only when count > 0. Read-only, no test needed (visual/environment-dependent). |
| A9 — Catalog stale-project sweep expansion | Done | `find` name list in the optional stale-project sweep extended with `.expo .cxx .turbo coverage .venv __pycache__`; added the CACHEDIR.TAG-by-declaration sentence. Doc-only, no test. |
| A10 — SKILL.md env-var reference block | Done | New "## Environment variables" section before "## Tests" listing all six vars (`MSC_DRY_RUN`, `MSC_WHITELIST_FILE`, `MSC_TRASH_BIN`, `MSC_DEVICE_SUPPORT_KEEP` default 2, `MSC_AI_AGENTS_KEEP` default 1, `MSC_ALLOW_UNLOGGED`), one line each. |

## Spec conflicts / judgment calls

- **A3's "same shape as Handoff" vs. per-child symlink logging.** The Handoff
  section's per-child symlink check is a silent `[ -L "$p" ] && continue`
  (no `log_op`, no `skipped` increment) — unlike the four older loops, which
  all log+count symlink skips. Mirrored that silent behavior exactly in A3
  for fidelity to "same shape as Handoff," which means A3 never increments
  `skipped_sym` (there's no existing `skipped` increment there to piggyback
  on, and A5 only asked to add counters "alongside existing `skipped`" in
  each respective branch). Flagging this as a minor inconsistency versus A4
  (which does log/count its symlink branch) rather than silently picking one
  interpretation.
- **A7 loop scope.** The spec literally says "the four deletion loops," which
  predates this wave's two new loops (A3, A4). Applied the same honesty
  pattern to all six loops (plus `trash-items.sh`) for consistency, since A4's
  own spec explicitly says its rm/honesty branch should look "like the
  safe-tier loop" — read together, six loops was the more consistent choice
  than leaving A3/A4 half-upgraded of a rule introduced in the same wave.
- No other ambiguities encountered.

## Verification

- `bash -n` on all four modified scripts — clean.
- `bats tests/` (full) — 68/68.
- Manual end-to-end dry-run against an isolated fake `$HOME` (stubbed
  brew/xcode-select/pgrep/conda on `PATH`, single inline-`env HOME=...`
  command, never run outside that guard) confirmed: new safe-tier paths,
  the DiagnosticReports age-gate preview, and the guarded Electron cache
  preview all appear correctly, with honest `size?`/`0.0K` formatting intact.
- `rsync -a --delete` to `~/.claude/skills/mac-storage-cleaner/` + `diff -rq` —
  silent (identical).
