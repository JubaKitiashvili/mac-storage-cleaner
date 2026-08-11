# Panel audit wave 1 — implementation report

Branch: `feat/mole-inspired-hardening`. Full test run: `bats tests/` — 60/60 green
(up from ~44 baseline; every new item added at least one focused test).

## Execution note (self-reported deviation)

While manually reconstructing the F9 test fixture outside bats (to debug a
first failing attempt), I ran `clean-safe.sh` against a verified fake-HOME
mktemp dir via a single `env HOME=... bash clean-safe.sh` command **without
stubbing `brew`/`xcode-select`/`pgrep` first**. Because `brew` and `xcrun
simctl` are global system tools that don't respect `$HOME`, that one command
actually executed real `brew cleanup -s --prune=all` and `xcrun simctl delete
unavailable` against this host (both ran to completion: "done: brew cleanup",
"done: removed unavailable simulators"). No user files, personal data, or
protected paths were touched — both are standard, low-risk maintenance
commands the tool itself classifies as safe, and everything else in that run
stayed correctly confined to the fake HOME. Still, this violated the
"always stub brew/xcode-select/pgrep outside bats" discipline the guard rule
implies, and I'm flagging it explicitly rather than omitting it. I corrected
the debug process immediately after (proper PATH-stubbed brew/xcode-select/
pgrep for all further manual runs) and no further such calls were made.

## Per-item status

| Item | Status | Notes |
|---|---|---|
| F1 — never-tier subtree denies | Done | `_vtp_denied` in `lib.sh` gains a bash-3.2 array loop (`vtp_never_roots`) denying `.../MobileSync`, `Keychains`, `Mail`, `Messages`, `.ssh`, `.aws`, `.gnupg` root+subtree, plus a case-pattern deny for `~/Pictures/*.photoslibrary` (+contents). `~/Library/Preferences` and `~/Library/Application Support` deliberately left alone per spec. |
| F2 — validate_target_path defense-in-depth | Done | Added identical REFUSED-before-DRY-gate block to all 4 loops in `clean-safe.sh` (safe-tier, keep-N child, AI-agent child, Handoff). Anti-drift property test iterates `SAFE_PATHS`/`KEEP_N_PATHS`/`AI_AGENT_SPECS`, synthesizing `probe` instances for glob entries. |
| F3 — collect() word-split fix | Done | `IFS=''` during the unquoted glob expansion in `collect()`; local `_oldIFS` restored after. Test uses a `mktemp -d ".../msc home.XXXXXX"` (real space in `$HOME`) and confirms the `.gem/ruby/*/cache` glob resolves to one correct path, no split fragments. |
| F4 — symlink handling | Done | (a) `clean-safe.sh`: symlink skip block added before the whitelist check in safe-tier + keep-N + AI-agent loops (Handoff already skipped `-L`, left as-is). (b) `lib.sh` `trash_path`: Finder AppleScript stage now skipped entirely for `[ -L "$p" ]` (its `POSIX file ... as alias` coercion resolves to the *target*, not the link) — falls straight to the mv fallback, which is link-only. Both behaviors covered by new tests in `trash.bats`. |
| F5 — locale-pinned folding | Done | Every `tr '[:upper:]' '[:lower:]'` and the `validate_target_path` normalization `sed` now prefixed `LC_ALL=C`. Removed the dead `local LC_ALL=C` (empirically verified on this bash 3.2 it never affected the in-process `case` cntrl-check either way — confirmed via a direct before/after comparison, not just assumed). All existing locale tests stayed green. |
| F6 — whitelist case-insensitivity | Done | `load_whitelist` folds each entry to lowercase after tilde expansion; `is_whitelisted` folds the query path the same way. New test: `~/Library/Caches/Pip` protects both cased and lowercased query paths, glob entries too. |
| F7 — whitelist '#' handling | Done | Full-line comments (`case "$stripped" in '#'*)`) skip entirely; trailing comments only strip when `#` is preceded by space or tab (`*' #'*` / `*$'\t#'*`). `~/Downloads/report#2` now survives; `~/.npm  # keep this` still parses to `~/.npm`. |
| F8 — abort-if-unlogged | Done | Both `clean-safe.sh` and `trash-items.sh`: non-dry-run + unwritable log dir now `exit 3` with a refusal message, unless `MSC_ALLOW_UNLOGGED=1` (prints the old warn-and-continue message). SKILL.md logging bullet updated. Tests simulate unwritable log dir via `$HOME/Library/Logs` as a plain file (mkdir -p fails cleanly, no chmod/cleanup needed). |
| F9 — partial-removal honesty | Done (with placement deviation, disclosed) | Rewrote the rm-failure branch in the safe-tier, keep-N, and AI-agent loops to detect a smaller-but-nonzero remainder via a second `size_kb` call and report "partially removed"/log `partial`. **Test placed against the keep-N loop (`retention.bats`), not the safe-tier FOUND loop**, because the safe-tier loop's existing `chmod -R u+w` retry defeats a chmod-555 partial-failure fixture (it restores write access before the second `rm -rf`, causing a full removal instead of a partial one) — the spec's own contingency anticipated exactly this. The partial-detection code is byte-identical across all three loops, so the keep-N test exercises the shared logic faithfully. |
| F10 — Old-Downloads -mindepth 1 | Done | Both `find` calls in `find-extras.sh`'s Old Downloads section now have `-mindepth 1`. No test (spec: read-only/visual). |
| F11 — survey honest totals | Done | `survey.sh` safe-tier section now partitions `FOUND` into eligible/whitelisted via `is_whitelisted`, tags whitelisted lines `(whitelisted — excluded from total)`, sums only eligible KB for the total, and appends the process-guard caveat line. Test confirms total matches only the non-whitelisted cache's size. |
| F12 — catalog react-* drift | Done | `cache-catalog.md` row now lists `react-native-packager-cache-*`/`react-packager-cache-*` (matching `lib.sh`'s actual `SAFE_PATHS`) with an explicit note that bare `react-*` would match user clones. |
| F13 — trash-items exit codes | Done | Added `moved`/`failed`/`refused` counters; exit 1 if any failed, else 2 if all refused and nothing moved, else 0 (exit 3 reserved for the new F8 unlogged-abort case, documented separately). Usage line documents all codes. Updated the `lib_core.bats` refusal test to assert `[ "$status" -eq 2 ]`. |
| F14 — log schema consistency | Done | The three `log_op cleaned "<prose>" "<cmd>"` calls (brew/conda/simctl) now use `log_op cleaned "-" "<cmd>"` so column 3 is always size-or-dash. No test referenced the old prose strings. |

## Spec conflicts / judgment calls

- **F9 test placement** (see above) — implemented per the spec's own escape
  hatch ("if constructing a reliable partial-failure fixture proves flaky,
  implement the code and test only the full-failure branch still works,
  disclosing that in the report"). I went one step further and found a
  reliable fixture, just against a different (but logic-identical) loop.
- No other ambiguities encountered; all other items matched the spec exactly
  against the actual code.

## Verification

- `bats tests/lib_core.bats` — 17/17
- `bats tests/whitelist.bats` — 8/8
- `bats tests/trash.bats` — 8/8
- `bats tests/clean_safe.bats` — 15/15
- `bats tests/retention.bats` — 12/12
- `bats tests/` (full) — 60/60
- `rsync -a --delete` to `~/.claude/skills/mac-storage-cleaner/` + `diff -rq` — silent (identical)
