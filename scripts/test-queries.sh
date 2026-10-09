#!/usr/bin/env bash
# Run every query in queries/ against a throwaway local ClickHouse server, as a least-privilege user
# with the grants from export/setup_user.sql. Fails if any query errors.
#
# Needs a `clickhouse` binary on PATH (or set CLICKHOUSE=/path/to/clickhouse).
# The server gets a cluster named "default" pointing at itself, so clusterAllReplicas('default', ...) works.
set -euo pipefail
CH="${CLICKHOUSE:-clickhouse}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
TCP=19000; HTTP=18123
PASS="test-only-$RANDOM$RANDOM"

cleanup() {
  status=$?
  if [ -n "${SERVER_PID:-}" ]; then kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true; fi
  rm -rf "$WORK" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT

cat > "$WORK/config.xml" <<EOF
<clickhouse>
  <logger><level>warning</level><console>1</console></logger>
  <tcp_port>$TCP</tcp_port>
  <http_port>$HTTP</http_port>
  <path>$WORK/data/</path>
  <remote_servers><default><shard><replica><host>localhost</host><port>$TCP</port></replica></shard></default></remote_servers>
  <query_log><database>system</database><table>query_log</table><flush_interval_milliseconds>1000</flush_interval_milliseconds></query_log>
  <part_log><database>system</database><table>part_log</table><flush_interval_milliseconds>1000</flush_interval_milliseconds></part_log>
  <metric_log><database>system</database><table>metric_log</table><flush_interval_milliseconds>1000</flush_interval_milliseconds><collect_interval_milliseconds>1000</collect_interval_milliseconds></metric_log>
  <asynchronous_metric_log><database>system</database><table>asynchronous_metric_log</table><flush_interval_milliseconds>1000</flush_interval_milliseconds></asynchronous_metric_log>
  <profiles><default/></profiles>
  <quotas><default/></quotas>
  <users><default><password/><networks><ip>::1</ip><ip>127.0.0.1</ip></networks><profile>default</profile><quota>default</quota><access_management>1</access_management></default></users>
  <user_directories><users_xml><path>$WORK/config.xml</path></users_xml><local_directory><path>$WORK/data/access/</path></local_directory></user_directories>
</clickhouse>
EOF

"$CH" server -C "$WORK/config.xml" > "$WORK/server.log" 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 60); do "$CH" client --port "$TCP" -q 'SELECT 1' >/dev/null 2>&1 && break; sleep 0.5; done
"$CH" client --port "$TCP" -q 'SELECT version()'

admin() { "$CH" client --port "$TCP" --multiquery -q "$1"; }

# A small workload so the logs have rows: a partitioned table, inserts, selects, one failing query.
admin "
CREATE DATABASE app;
CREATE TABLE app.events (ts DateTime, user_id UInt64, kind LowCardinality(String), v Float64)
  ENGINE = MergeTree PARTITION BY toYYYYMM(ts) ORDER BY (kind, ts);"
for _ in 1 2 3; do
  admin "INSERT INTO app.events SELECT now() - number % 86400, number % 1000, ['a','b','c'][number % 3 + 1], rand() / 1e9 FROM numbers(200000)"
done
for i in $(seq 1 10); do
  admin "SELECT kind, count(), avg(v) FROM app.events WHERE user_id = $i GROUP BY kind FORMAT Null"
done
admin "SELECT * FROM app.missing" >/dev/null 2>&1 || true
admin "SYSTEM FLUSH LOGS"

# The least-privilege user from export/setup_user.sql.
sed "s/<choose a strong password>/$PASS/" "$ROOT/export/setup_user.sql" | grep -v '^--' | admin "$(cat)"

failed=0
while IFS= read -r f; do
  sql="$(sed 's#30 /\*days\*/#30 /*days*/#g' "$f")"
  if out="$("$CH" client --port "$TCP" --user sizing_reader --password "$PASS" -q "$sql" --format Null 2>&1)"; then
    echo "ok   ${f#"$ROOT"/}"
  else
    echo "FAIL ${f#"$ROOT"/}"; echo "$out" | head -5; failed=$((failed + 1))
  fi
done < <(find "$ROOT/queries" -name '*.sql' | sort)

# The least-privilege user must not be able to read user tables.
if "$CH" client --port "$TCP" --user sizing_reader --password "$PASS" -q 'SELECT count() FROM app.events' >/dev/null 2>&1; then
  echo "FAIL sizing_reader can read app.events"; failed=$((failed + 1))
else
  echo "ok   sizing_reader cannot read app.events"
fi

echo "$failed failed"
[ "$failed" -eq 0 ]
