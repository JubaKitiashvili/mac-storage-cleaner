#!/usr/bin/env bats

ROOT="$BATS_TEST_DIRNAME/.."

skill_version () {
  awk '/^metadata:/{m=1;next} m&&/^[a-z]/{m=0} m&&/^  version:/{print $2}' "$ROOT/skills/mac-storage-cleaner/SKILL.md"
}
json_version () { grep -m1 '"version"' "$1" | sed -E 's/.*"version"[^"]*"([^"]+)".*/\1/'; }

@test "every manifest carries the same version as SKILL.md" {
  local v; v=$(skill_version)
  [ -n "$v" ]
  [ "$(json_version "$ROOT/.claude-plugin/plugin.json")" = "$v" ]
  [ "$(json_version "$ROOT/.cursor-plugin/plugin.json")" = "$v" ]
  local mp; mp="$ROOT/.claude-plugin/marketplace.json"
  # marketplace.json carries the version twice (metadata + the plugin entry)
  [ "$(grep -c "\"version\": \"$v\"" "$mp")" -eq 2 ]
}

@test "every JSON manifest is valid JSON" {
  local f
  for f in "$ROOT/.claude-plugin/plugin.json" "$ROOT/.claude-plugin/marketplace.json" "$ROOT/.cursor-plugin/plugin.json"; do
    run python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f"
    [ "$status" -eq 0 ] || { echo "invalid JSON: $f"; false; }
  done
}

@test "the Codex manifest declares implicit invocation" {
  local y="$ROOT/skills/mac-storage-cleaner/agents/openai.yaml"
  [ -f "$y" ]
  grep -q 'allow_implicit_invocation: true' "$y"
}

@test "bump-version.sh rewrites every location" {
  local tmp
  tmp="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-bump.XXXXXX")"
  rsync -a --exclude .git --exclude dist "$ROOT/" "$tmp/"
  run bash "$tmp/tools/bump-version.sh" 9.9.9
  [ "$status" -eq 0 ] || { echo "$output"; rm -rf "$tmp"; false; }
  grep -q '  version: 9.9.9' "$tmp/skills/mac-storage-cleaner/SKILL.md"
  grep -q '"version": "9.9.9"' "$tmp/.claude-plugin/plugin.json"
  grep -q '"version": "9.9.9"' "$tmp/.cursor-plugin/plugin.json"
  [ "$(grep -c '"version": "9.9.9"' "$tmp/.claude-plugin/marketplace.json")" -eq 2 ]
  # idempotent: a second run must not corrupt anything
  run bash "$tmp/tools/bump-version.sh" 9.9.9
  [ "$status" -eq 0 ]
  rm -rf "$tmp"
}
