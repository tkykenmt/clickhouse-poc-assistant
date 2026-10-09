#!/usr/bin/env bash
# Build the distributable zips into dist/:
#   ch-sizing-export.zip  export kit for users (README in English and Japanese, setup_user.sql, export.sh, queries/)
#   <skill>-skill.zip     one per directory in clickhouse-agents/skills/, with SKILL.md and
#                         exactly the files it references (queries/.../*.sql, reference/*.md)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"; TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
rm -rf "$DIST"; mkdir -p "$DIST"

kit="$TMP/ch-sizing-export"
mkdir -p "$kit/queries/optional"
cp "$ROOT"/export/{README.md,README.ja.md,setup_user.sql,export.sh} "$ROOT/LICENSE" "$kit/"
cp "$ROOT"/queries/*.sql "$kit/queries/"
cp "$ROOT"/queries/optional/*.sql "$kit/queries/optional/"
(cd "$TMP" && zip -qr "$DIST/ch-sizing-export.zip" ch-sizing-export)

for dir in "$ROOT"/clickhouse-agents/skills/*/; do
  name="$(basename "$dir")"
  out="$TMP/skills/$name"
  mkdir -p "$out"
  cp "$dir/SKILL.md" "$ROOT/LICENSE" "$out/"
  # The agent cannot list folders, so SKILL.md names every file; ship exactly those.
  refs="$(grep -oE '(queries/[A-Za-z0-9_/]+\.sql|reference/[A-Za-z0-9_-]+\.md)' "$dir/SKILL.md" | sort -u)"
  # Reference files can point to other reference files; ship those too (until nothing new is found).
  while :; do
    more="$(for r in $refs; do case "$r" in reference/*) if [ -f "$ROOT/$r" ]; then grep -oE 'reference/[A-Za-z0-9_-]+\.md' "$ROOT/$r" || true; fi;; esac; done | sort -u)"
    all="$(printf '%s\n%s\n' "$refs" "$more" | grep -v '^$' | sort -u)"
    [ "$all" = "$refs" ] && break
    refs="$all"
  done
  [ -n "$refs" ] || { echo "$name: SKILL.md references no files" >&2; exit 1; }
  for ref in $refs; do
    [ -f "$ROOT/$ref" ] || { echo "$name: $ref does not exist" >&2; exit 1; }
    mkdir -p "$out/$(dirname "$ref")"
    cp "$ROOT/$ref" "$out/$ref"
  done
  (cd "$TMP/skills" && zip -qr "$DIST/$name-skill.zip" "$name")
done

# Every core query must be listed by the sizing skill.
for f in "$ROOT"/queries/*.sql; do
  grep -q "queries/$(basename "$f")" "$ROOT/clickhouse-agents/skills/poc-sizing-stats/SKILL.md" \
    || { echo "poc-sizing-stats does not list queries/$(basename "$f")" >&2; exit 1; }
done
ls -l "$DIST"
