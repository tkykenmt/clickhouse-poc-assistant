#!/usr/bin/env bash
# Export sizing statistics from your ClickHouse Cloud service as CSV files.
# Reads only system tables. Never reads rows from your own tables.
#
# Usage:
#   export CH_URL="https://<your-service>.<region>.<cloud>.clickhouse.cloud:8443"
#   export CH_USER="sizing_reader"
#   read -rs CH_PASSWORD; export CH_PASSWORD
#   ./export.sh [days] [--with-query-text]
#
# days defaults to 30. --with-query-text also runs queries/optional/ (sample query text per pattern).
# Exits with status 1 if any query fails; the archive is still written so the failures can be inspected.
set -euo pipefail

DAYS=30
WITH_TEXT=no
for arg in "$@"; do
  case "$arg" in
    --with-query-text) WITH_TEXT=yes ;;
    ''|*[!0-9]*) echo "unknown argument: $arg (expected a number of days or --with-query-text)" >&2; exit 2 ;;
    *) DAYS="$arg" ;;
  esac
done
: "${CH_URL:?set CH_URL, e.g. https://<host>:8443}"
: "${CH_USER:?set CH_USER}"
: "${CH_PASSWORD:?set CH_PASSWORD}"

# --fail-with-body needs curl 7.76 or later; older curl only has --fail (no error body).
if curl --help all 2>/dev/null | grep -q -- '--fail-with-body'; then
  FAIL_OPT=--fail-with-body
else
  FAIL_OPT=--fail
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
# queries/ sits next to this script in the distributed kit, and one level up in the repository.
QDIR="$HERE/queries"; [ -d "$QDIR" ] || QDIR="$HERE/../queries"
OUT="sizing_export_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUT"

files=("$QDIR"/*.sql)
if [ "$WITH_TEXT" = yes ]; then
  files+=("$QDIR"/optional/*.sql)
fi

# Escape backslashes and double quotes for curl's config syntax.
esc() { local s="${1//\\/\\\\}"; printf '%s' "${s//\"/\\\"}"; }
CRED="$(esc "$CH_USER"):$(esc "$CH_PASSWORD")"

failed=0
for f in "${files[@]}"; do
  name="$(basename "$f" .sql)"
  sql="$(sed "s#30 /\*days\*/#${DAYS} /*days*/#g" "$f")"
  # Credentials go to curl on stdin as a config file, so they do not appear in the process list.
  if printf 'user = "%s"\n' "$CRED" | \
       curl -sS "$FAIL_OPT" -K - \
         "$CH_URL/?default_format=CSVWithNames" \
         --data-binary "$sql" -o "$OUT/$name.csv"; then
    echo "ok      $name ($(wc -c < "$OUT/$name.csv" | tr -d ' ') bytes)"
  else
    [ -f "$OUT/$name.csv" ] && mv "$OUT/$name.csv" "$OUT/$name.error.txt"
    echo "failed  $name (see $OUT/$name.error.txt)" >&2
    failed=$((failed + 1))
  fi
done

{
  echo "exported_at_utc,$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "days,$DAYS"
  echo "with_query_text,$WITH_TEXT"
  echo "failed_queries,$failed"
} > "$OUT/_manifest.csv"

tar -czf "$OUT.tar.gz" "$OUT"
echo "wrote $OUT.tar.gz ($failed failed)"
[ "$failed" -eq 0 ] || exit 1
