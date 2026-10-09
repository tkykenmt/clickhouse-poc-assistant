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
set -euo pipefail

DAYS="${1:-30}"
WITH_TEXT="${2:-}"
: "${CH_URL:?set CH_URL, e.g. https://<host>:8443}"
: "${CH_USER:?set CH_USER}"
: "${CH_PASSWORD:?set CH_PASSWORD}"
case "$DAYS" in ''|*[!0-9]*) echo "days must be a whole number" >&2; exit 2;; esac

HERE="$(cd "$(dirname "$0")" && pwd)"
# queries/ sits next to this script in the distributed kit, and one level up in the repository.
QDIR="$HERE/queries"; [ -d "$QDIR" ] || QDIR="$HERE/../queries"
OUT="sizing_export_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUT"

files=("$QDIR"/*.sql)
if [ "$WITH_TEXT" = "--with-query-text" ]; then
  files+=("$QDIR"/optional/*.sql)
fi

failed=0
for f in "${files[@]}"; do
  name="$(basename "$f" .sql)"
  sql="$(sed "s#30 /\*days\*/#${DAYS} /*days*/#g" "$f")"
  if curl -sS --fail-with-body -u "$CH_USER:$CH_PASSWORD" \
       "$CH_URL/?default_format=CSVWithNames" \
       --data-binary "$sql" -o "$OUT/$name.csv"; then
    echo "ok      $name ($(($(wc -l < "$OUT/$name.csv") - 1)) rows)"
  else
    echo "failed  $name (see $OUT/$name.csv)" >&2
    failed=$((failed + 1))
  fi
done

{
  echo "exported_at_utc,$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "days,$DAYS"
  echo "with_query_text,$([ "$WITH_TEXT" = "--with-query-text" ] && echo yes || echo no)"
} > "$OUT/_manifest.csv"

tar -czf "$OUT.tar.gz" "$OUT"
echo "wrote $OUT.tar.gz ($failed failed)"
