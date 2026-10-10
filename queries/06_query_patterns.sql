-- Query patterns (literals stripped): executions, latency, rows read, memory and CPU.
-- Contains no query text. Patterns are identified by normalized_query_hash.
SELECT
    toString(normalized_query_hash) AS query_hash,
    query_kind,
    arrayStringConcat(any(tables), ' ') AS query_tables,
    uniqExact(user) AS users,
    count() AS executions,
    countIf(type = 'ExceptionWhileProcessing') AS errors,
    round(quantileIf(0.5)(query_duration_ms, type = 'QueryFinish')) AS p50_ms,
    round(quantileIf(0.9)(query_duration_ms, type = 'QueryFinish')) AS p90_ms,
    round(quantileIf(0.99)(query_duration_ms, type = 'QueryFinish')) AS p99_ms,
    round(avg(read_rows)) AS avg_read_rows,
    round(avg(read_bytes)) AS avg_read_bytes,
    round(avg(written_rows)) AS avg_written_rows,
    max(memory_usage) AS max_memory_bytes,
    round(sum(ProfileEvents['UserTimeMicroseconds'] + ProfileEvents['SystemTimeMicroseconds']) / 1e6, 1) AS total_cpu_seconds,
    round(avg(ProfileEvents['UserTimeMicroseconds'] + ProfileEvents['SystemTimeMicroseconds']) / 1e3, 1) AS avg_cpu_ms,
    min(event_time) AS first_seen,
    max(event_time) AS last_seen
FROM clusterAllReplicas('default', merge('system', '^query_log'))
WHERE type IN ('QueryFinish', 'ExceptionWhileProcessing')
  AND is_initial_query
  AND NOT (user = currentUser()  -- this connection's own reads of system tables; other queries of the same user stay (failures before start have no tables and stay)
           AND notEmpty(tables) AND arrayAll(t -> startsWith(t, 'system.') OR startsWith(lower(t), 'information_schema.')
                           OR t IN ('_table_function.clusterAllReplicas', '_table_function.merge'), tables))
  AND user NOT LIKE '%-internal'  -- ClickHouse Cloud's own monitoring users
  AND query_kind != 'Explain'  -- EXPLAIN runs, for example the assistant's estimates before asking for approval
  AND log_comment != 'poc-assistant'  -- queries the assistant ran on user tables with the user's approval
  AND event_date >= today() - 30 /*days*/
GROUP BY query_hash, query_kind
ORDER BY total_cpu_seconds DESC
LIMIT 100
SETTINGS skip_unavailable_shards = 1
