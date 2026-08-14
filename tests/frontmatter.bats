#!/usr/bin/env bats

SKILL_MD="$BATS_TEST_DIRNAME/../skills/mac-storage-cleaner/SKILL.md"

fm () {  # print the YAML frontmatter block
  awk 'NR==1 && $0=="---" {inb=1; next} inb && $0=="---" {exit} inb {print}' "$SKILL_MD"
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
  body=$(fm | awk '/^metadata:/{m=1;next} m&&/^[a-z]/{m=0} m{print}')
  [ -n "$body" ]
  # every metadata line must be exactly "  key: value" with a non-empty value
  echo "$body" | grep -vqE '^  [a-z][a-z0-9-]*: .+$' && { echo "non-scalar metadata line:"; echo "$body"; false; }
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
