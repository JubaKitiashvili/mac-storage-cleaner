#!/bin/bash
# Repo tooling (NOT shipped inside the skill): set the release version in every
# manifest at once. The version lives in seven places and CI fails on drift.
set -eu
[ $# -eq 1 ] || { echo "usage: tools/bump-version.sh <semver>"; exit 1; }
V="$1"
echo "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "not a semver: $V"; exit 1; }
R="$(cd "$(dirname "$0")/.." && pwd)"

/usr/bin/sed -i '' -E "s/^(  version: ).*/\1$V/"            "$R/skills/mac-storage-cleaner/SKILL.md"
/usr/bin/sed -i '' -E "s/(\"version\": \")[^\"]+(\")/\1$V\2/" "$R/.claude-plugin/plugin.json"
/usr/bin/sed -i '' -E "s/(\"version\": \")[^\"]+(\")/\1$V\2/" "$R/.claude-plugin/marketplace.json"
/usr/bin/sed -i '' -E "s/(\"version\": \")[^\"]+(\")/\1$V\2/" "$R/.cursor-plugin/plugin.json"
/usr/bin/sed -i '' -E "s/(\"version\": \")[^\"]+(\")/\1$V\2/" "$R/plugin.json"
/usr/bin/sed -i '' -E "s/(\"version\": \")[^\"]+(\")/\1$V\2/" "$R/gemini-extension.json"

echo "bumped to $V:"
grep -n '  version: ' "$R/skills/mac-storage-cleaner/SKILL.md"
grep -n '"version"'   "$R/.claude-plugin/plugin.json" "$R/.claude-plugin/marketplace.json" "$R/.cursor-plugin/plugin.json" "$R/plugin.json" "$R/gemini-extension.json"
