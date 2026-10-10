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
  <asynchronous_insert_log><database>system</database><table>asynchronous_insert_log</table><flush_interval_milliseconds>1000</flush_interval_milliseconds></asynchronous_insert_log>
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
# One async insert over HTTP with a time limit (the native client sometimes did not return after the flush).
curl -sS --max-time 30 "http://localhost:$HTTP/?async_insert=1&wait_for_async_insert=1" \
  --data-binary "INSERT INTO app.events VALUES (now(), 1, 'a', 1.0)" || echo "warning: async insert did not finish"
admin "SELECT * FROM app.missing" >/dev/null 2>&1 || true
# INSERT ... SELECT names its source in tables; only the target may count as an insert target.
admin "CREATE TABLE app.src ENGINE = MergeTree ORDER BY tuple() AS SELECT number AS n FROM numbers(10)"
admin "CREATE TABLE app.copy (n UInt64) ENGINE = MergeTree ORDER BY tuple()"
admin "INSERT INTO app.copy SELECT n FROM app.src"
# A query the assistant ran on a user table with its log_comment must not count as workload.
admin "SELECT count() FROM app.src SETTINGS log_comment = 'poc-assistant' FORMAT Null"
# A column named final must not count as FINAL.
admin "SELECT v AS final_x FROM app.events WHERE user_id = 999999 FORMAT Null"
# A table with TTL, a detached part, and a loaded dictionary with no elements, for 10, 27 and 13.
admin "CREATE TABLE app.with_ttl (ts DateTime) ENGINE = MergeTree ORDER BY ts TTL ts + INTERVAL 1 YEAR"
admin "INSERT INTO app.copy SELECT 1"
admin "ALTER TABLE app.copy DETACH PART '$(admin "SELECT name FROM system.parts WHERE database = 'app' AND table = 'copy' AND active ORDER BY name DESC LIMIT 1")'"
admin "CREATE TABLE app.dict_src (k UInt64, v String) ENGINE = MergeTree ORDER BY k"
admin "CREATE DICTIONARY app.empty_dict (k UInt64, v String) PRIMARY KEY k SOURCE(CLICKHOUSE(DB 'app' TABLE 'dict_src')) LIFETIME(0) LAYOUT(HASHED())"
admin "SYSTEM RELOAD DICTIONARY app.empty_dict"
# A column named ttl is not a TTL, and a direct dictionary holds no elements by design.
admin "CREATE TABLE app.named_ttl (ttl DateTime) ENGINE = MergeTree ORDER BY ttl"
admin "CREATE DICTIONARY app.direct_dict (k UInt64, v String) PRIMARY KEY k SOURCE(CLICKHOUSE(DB 'app' TABLE 'dict_src')) LAYOUT(DIRECT())"
admin "SELECT dictGetOrDefault('app.direct_dict', 'v', toUInt64(1), '') FORMAT Null"
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

# The workload ran as the admin user. Read as the same user, its queries must stay in the results,
# while that user's own reads of system tables must be left out. system.contributors is read only here.
admin "SELECT count() FROM system.contributors FORMAT Null"
admin "SYSTEM FLUSH LOGS"
same_user="$("$CH" client --port "$TCP" -q "$(cat "$ROOT/queries/06_query_patterns.sql")" --format TSV)"
if ! printf '%s\n' "$same_user" | awk -F'\t' '$3 ~ /app\.events/ {found=1} END {exit !found}'; then
  echo "FAIL 06 run as the workload's user lost the workload"; failed=$((failed + 1))
elif printf '%s\n' "$same_user" | awk -F'\t' '$3 == "system.contributors" {found=1} END {exit !found}'; then
  echo "FAIL 06 run as the workload's user kept its own system-table reads"; failed=$((failed + 1))
else
  echo "ok   06 keeps the same user's workload and drops its own system-table reads"
fi
if printf '%s\n' "$same_user" | awk -F'\t' '$3 == "app.src" && $2 == "Select" {found=1} END {exit !found}'; then
  echo "FAIL 06 counted the assistant's tagged query on a user table"; failed=$((failed + 1))
else
  echo "ok   06 leaves out the assistant's tagged queries on user tables"
fi

# Failures before start have no tables; read as the same user they must stay (26).
same_user_errors="$("$CH" client --port "$TCP" -q "$(cat "$ROOT/queries/progress/26_errors_by_code.sql")" --format TSV)"
if printf '%s\n' "$same_user_errors" | awk -F'\t' '$1 == "UNKNOWN_TABLE" {found=1} END {exit !found}'; then
  echo "ok   26 keeps the same user's failures before start"
else
  echo "FAIL 26 run as the workload's user lost UNKNOWN_TABLE"; failed=$((failed + 1))
fi

# 12 must count app.copy as a target and not app.src, the table INSERT ... SELECT read.
targets="$("$CH" client --port "$TCP" --user sizing_reader --password "$PASS" -q "$(cat "$ROOT/queries/advisor/12_insert_shape.sql")" --format TSV | cut -f1)"
if printf '%s\n' "$targets" | grep -qx 'app.copy' && ! printf '%s\n' "$targets" | grep -qx 'app.src'; then
  echo "ok   12 counts the INSERT ... SELECT target and not its source"
else
  echo "FAIL 12 insert targets: $(printf '%s' "$targets" | tr '\n' ' ')"; failed=$((failed + 1))
fi

# 11 must not count a column named final as FINAL.
final_rows="$("$CH" client --port "$TCP" --user sizing_reader --password "$PASS" -q "$(cat "$ROOT/queries/advisor/11_query_efficiency.sql")" --format TSVWithNames)"
if printf '%s\n' "$final_rows" | awk -F'\t' 'NR == 1 {for (i = 1; i <= NF; i++) if ($i == "final_executions") c = i; next} c && $c > 0 {bad=1} END {exit bad || !c}'; then
  echo "ok   11 does not count a column named final as FINAL"
else
  echo "FAIL 11 counted FINAL in a query without FINAL"; failed=$((failed + 1))
fi

# 10 flags the TTL table, 27 lists the detached part, 13 lists the empty dictionary.
as_reader() { "$CH" client --port "$TCP" --user sizing_reader --password "$PASS" -q "$(cat "$ROOT/queries/$1")" --format TSVWithNames; }
if ! as_reader advisor/10_table_layout.sql | awk -F'\t' 'NR == 1 {for (i = 1; i <= NF; i++) if ($i == "has_ttl") c = i} NR > 1 && $2 == "with_ttl" && $c == 1 {found=1} END {exit !found}'; then
  echo "FAIL 10 did not flag the table with TTL"; failed=$((failed + 1))
else
  echo "ok   10 flags the table with TTL"
fi
if as_reader advisor/10_table_layout.sql | awk -F'\t' 'NR == 1 {for (i = 1; i <= NF; i++) if ($i == "has_ttl") c = i} NR > 1 && $2 == "named_ttl" && $c == 1 {found=1} END {exit !found}'; then
  echo "FAIL 10 flagged a column named ttl as TTL"; failed=$((failed + 1))
else
  echo "ok   10 does not flag a column named ttl"
fi
if ! as_reader progress/27_background_health.sql | awk -F'\t' '$1 == "detached part" && $2 ~ /^app\.copy/ {found=1} END {exit !found}'; then
  echo "FAIL 27 did not list the detached part"; failed=$((failed + 1))
else
  echo "ok   27 lists the detached part"
fi
if ! as_reader advisor/13_service_objects.sql | awk -F'\t' '$1 == "dictionary empty or failed" && $2 ~ /^app\.empty_dict/ {found=1} END {exit !found}'; then
  echo "FAIL 13 did not list the empty dictionary"; failed=$((failed + 1))
else
  echo "ok   13 lists the empty dictionary"
fi
if as_reader advisor/13_service_objects.sql | awk -F'\t' '$1 == "dictionary empty or failed" && $2 ~ /^app\.direct_dict/ {found=1} END {exit !found}'; then
  echo "FAIL 13 listed a direct dictionary as empty"; failed=$((failed + 1))
else
  echo "ok   13 leaves out a direct dictionary"
fi

# The least-privilege user must not be able to read user tables.
if "$CH" client --port "$TCP" --user sizing_reader --password "$PASS" -q 'SELECT count() FROM app.events' >/dev/null 2>&1; then
  echo "FAIL sizing_reader can read app.events"; failed=$((failed + 1))
else
  echo "ok   sizing_reader cannot read app.events"
fi

echo "$failed failed"
[ "$failed" -eq 0 ]
