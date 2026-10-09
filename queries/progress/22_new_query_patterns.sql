-- SELECT patterns first seen in the last 24 hours (within the last 8 days), heaviest first.
-- sample_query contains literal values; it stays inside this conversation.
SELECT
    toString(normalized_query_hash) AS query_hash,
    arrayStringConcat(any(tables), ' ') AS query_tables,
    leftUTF8(any(query), 1000) AS sample_query,
    min(event_time) AS first_seen,
    count() AS executions,
    round(quantile(0.99)(query_duration_ms)) AS p99_ms,
    round(avg(read_rows)) AS avg_read_rows,
    round(avg(result_rows)) AS avg_result_rows,
    round(avg(ProfileEvents['SelectedMarks']) / nullIf(avg(ProfileEvents['SelectedMarksTotal']), 0), 3) AS marks_read_ratio,
    max(memory_usage) AS max_memory_bytes,
    round(sum(ProfileEvents['UserTimeMicroseconds'] + ProfileEvents['SystemTimeMicroseconds']) / 1e6, 1) AS total_cpu_seconds
FROM clusterAllReplicas('default', merge('system', '^query_log'))
WHERE type = 'QueryFinish'
  AND query_kind = 'Select'
  AND is_initial_query
  AND NOT (user = currentUser()  -- this connection's own reads of system tables; other queries of the same user stay
           AND arrayAll(t -> startsWith(t, 'system.') OR startsWith(lower(t), 'information_schema.')
                           OR t IN ('_table_function.clusterAllReplicas', '_table_function.merge'), tables))
  AND user NOT LIKE '%-internal'  -- ClickHouse Cloud's own monitoring users
  AND event_date >= today() - 8
  AND event_time >= now() - INTERVAL 8 DAY
GROUP BY query_hash
HAVING first_seen >= now() - INTERVAL 1 DAY
ORDER BY total_cpu_seconds DESC
LIMIT 10
SETTINGS skip_unavailable_shards = 1
