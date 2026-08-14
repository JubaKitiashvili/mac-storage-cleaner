#!/usr/bin/env bats

SKILL_MD="$BATS_TEST_DIRNAME/../skills/mac-storage-cleaner/SKILL.md"

fm () {  # print the YAML frontmatter block of a file (default: the real SKILL.md)
  local f="${1:-$SKILL_MD}"
  awk 'NR==1 && $0=="---" {inb=1; next} inb && $0=="---" {exit} inb {print}' "$f"
}

metadata_lines () {  # reads a frontmatter block on stdin, prints just the metadata: sub-block
  awk '/^metadata:/{m=1;next} m&&/^[a-z]/{m=0} m{print}'
}

metadata_has_non_scalar_line () {
  # reads a metadata body on stdin; succeeds (exit 0) if it finds a line that is
  # NOT "  key: <value>" with a value that (a) is non-empty, (b) does not start
  # with whitespace, and (c) does not start with '[' or '{' — i.e. flow-style
  # YAML (a list or map) written inline, which parses to Array/Hash, not String.
  grep -vqE '^  [a-z][a-z0-9-]*: [^[{[:space:]].*$'
}

@test "name matches the strictest agent regex and the folder name" {
  local name
  name=$(fm | awk '/^name:/{print $2}')
  [ "$name" = "mac-storage-cleaner" ]
  [ -d "$BATS_TEST_DIRNAME/../skills/$name" ]
  echo "$name" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'
}

@test "description fits opencode's 1024-BYTE limit with headroom" {
  local bytes
  bytes=$(fm | awk '/^description:/{sub(/^description: /,""); print}' | tr -d '\n' | wc -c | tr -d ' ')
  [ "$bytes" -le 1000 ] || { echo "description is $bytes bytes; budget is 1000 (hard limit 1024)"; false; }
  [ "$bytes" -gt 200 ] || { echo "description collapsed to $bytes bytes — trigger coverage lost"; false; }
}

@test "required and portable keys are present" {
  fm | grep -q '^name:'
  fm | grep -q '^description:'
  fm | grep -q '^license: MIT$'
  fm | grep -q '^metadata:'
}

@test "every metadata value is a scalar string — opencode rejects nested maps" {
  local body
  body=$(fm | metadata_lines)
  [ -n "$body" ]
  # every metadata line must be "  key: value" with a non-empty, non-whitespace
  # value that is not flow-style YAML ('[...]' or '{...}') — those parse to an
  # Array/Hash, not a String, even though a naive ".+" check would accept them.
  echo "$body" | metadata_has_non_scalar_line && { echo "non-scalar metadata line:"; echo "$body"; false; }
  echo "$body" | grep -q '^  version: '
}

@test "the frontmatter is valid YAML" {
  if ! command -v ruby >/dev/null 2>&1; then skip "ruby not available"; fi
  local f
  f="$(mktemp "${BATS_TMPDIR:-/tmp}/msc-fm.XXXXXX")"
  fm > "$f"
  run ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$f"
  rm -f "$f"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "every metadata value is a real YAML String (ruby type-check, catches block and flow style alike)" {
  if ! command -v ruby >/dev/null 2>&1; then skip "ruby not available"; fi
  local f
  f="$(mktemp "${BATS_TMPDIR:-/tmp}/msc-fm.XXXXXX")"
  fm > "$f"
  run ruby -ryaml -e '
    doc = YAML.load_file(ARGV[0])
    md = doc["metadata"] || {}
    bad = md.select { |_, v| !v.is_a?(String) }
    if bad.empty?
      exit 0
    else
      warn "non-string metadata values: #{bad.inspect}"
      exit 1
    end
  ' "$f"
  rm -f "$f"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "flow-style YAML in metadata is rejected by both checks (regression: tags: [macos, disk-space] must fail)" {
  local before after tmp body
  before="$(md5 -q "$SKILL_MD" 2>/dev/null || md5sum "$SKILL_MD" | awk '{print $1}')"

  tmp="$(mktemp "${BATS_TMPDIR:-/tmp}/msc-badfm.XXXXXX")"
  cat > "$tmp" <<'EOF'
---
name: mac-storage-cleaner
description: synthetic skill used only to prove the hardened check rejects flow-style YAML
license: MIT
metadata:
  version: 3.0.0
  tags: [macos, disk-space]
---
EOF

  body=$(fm "$tmp" | metadata_lines)
  [ -n "$body" ]

  # (1) hardened structural check (bash/grep, no ruby dependency) must flag it
  echo "$body" | metadata_has_non_scalar_line \
    || { echo "structural check failed to flag flow-style 'tags: [macos, disk-space]'"; false; }

  # (2) stronger type check (ruby, when available): YAML parses the bracketed
  # value as an Array, not a String — the walk-the-hash check must catch it too
  if command -v ruby >/dev/null 2>&1; then
    run ruby -ryaml -e '
      doc = YAML.load_file(ARGV[0])
      md = doc["metadata"] || {}
      bad = md.select { |_, v| !v.is_a?(String) }
      exit(bad.empty? ? 1 : 0)   # exit 0 == found a non-string value, as expected here
    ' "$tmp"
    [ "$status" -eq 0 ] || { echo "ruby type-check failed to flag the Array value: $output"; false; }
  fi

  rm -f "$tmp"

  after="$(md5 -q "$SKILL_MD" 2>/dev/null || md5sum "$SKILL_MD" | awk '{print $1}')"
  [ "$before" = "$after" ]
}
