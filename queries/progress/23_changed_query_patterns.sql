-- SELECT patterns seen both in the last 24 hours and the 7 days before, with the change in latency, rows read and memory.
-- Sorted by the largest p99 ratio; the skill decides what counts as a notable change.
WITH now() - INTERVAL 1 DAY AS day_start
SELECT
    toString(normalized_query_hash) AS query_hash,
    arrayStringConcat(any(tables), ' ') AS tables,
    leftUTF8(any(query), 1000) AS sample_query,
    countIf(event_time >= day_start) AS executions_24h,
    countIf(event_time < day_start) AS executions_prev_7d,
    round(quantileIf(0.99)(query_duration_ms, event_time >= day_start)) AS p99_ms_24h,
    round(quantileIf(0.99)(query_duration_ms, event_time < day_start)) AS p99_ms_prev_7d,
    round(avgIf(read_rows, event_time >= day_start)) AS avg_read_rows_24h,
    round(avgIf(read_rows, event_time < day_start)) AS avg_read_rows_prev_7d,
    maxIf(memory_usage, event_time >= day_start) AS max_memory_24h,
    maxIf(memory_usage, event_time < day_start) AS max_memory_prev_7d,
    round(p99_ms_24h / nullIf(p99_ms_prev_7d, 0), 2) AS p99_ratio,
    round(avg_read_rows_24h / nullIf(avg_read_rows_prev_7d, 0), 2) AS read_rows_ratio
FROM clusterAllReplicas('default', merge('system', '^query_log'))
WHERE type = 'QueryFinish'
  AND query_kind = 'Select'
  AND is_initial_query
  AND user != currentUser()
  AND user NOT LIKE '%-internal'  -- ClickHouse Cloud's own monitoring users
  AND event_date >= today() - 8
  AND event_time >= now() - INTERVAL 8 DAY
GROUP BY query_hash
HAVING executions_24h > 0 AND executions_prev_7d > 0
ORDER BY p99_ratio DESC NULLS LAST
LIMIT 15
SETTINGS skip_unavailable_shards = 1
