-- Query load per hour for SELECT and INSERT: count, peak queries per second, latency and CPU.
-- Aggregates per second first, so only one row per second and kind reaches the initiator.
SELECT
    toStartOfHour(second) AS hour,
    query_kind,
    sum(sec_queries) AS queries,
    sum(sec_errors) AS errors,
    max(sec_queries) AS peak_queries_per_second,
    round(quantilesMerge(0.5, 0.99)(duration_state)[1]) AS p50_ms,
    round(quantilesMerge(0.5, 0.99)(duration_state)[2]) AS p99_ms,
    round(sum(cpu_us) / 1e6, 1) AS cpu_seconds,
    sum(sec_read_rows) AS read_rows,
    sum(sec_written_rows) AS written_rows
FROM
(
    SELECT
        event_time AS second,
        query_kind,
        count() AS sec_queries,
        countIf(type = 'ExceptionWhileProcessing') AS sec_errors,
        quantilesStateIf(0.5, 0.99)(query_duration_ms, type = 'QueryFinish') AS duration_state,
        sum(ProfileEvents['UserTimeMicroseconds'] + ProfileEvents['SystemTimeMicroseconds']) AS cpu_us,
        sum(read_rows) AS sec_read_rows,
        sum(written_rows) AS sec_written_rows
    FROM clusterAllReplicas('default', merge('system', '^query_log'))
    WHERE type IN ('QueryFinish', 'ExceptionWhileProcessing')
      AND is_initial_query
      AND NOT (user = currentUser()  -- this connection's own reads of system tables; other queries of the same user stay (failures before start have no tables and stay)
               AND notEmpty(tables) AND arrayAll(t -> startsWith(t, 'system.') OR startsWith(lower(t), 'information_schema.')
                               OR t IN ('_table_function.clusterAllReplicas', '_table_function.merge'), tables))
      AND user NOT LIKE '%-internal'  -- ClickHouse Cloud's own monitoring users
      AND log_comment != 'poc-assistant'  -- queries the assistant ran on user tables with the user's approval
      AND query_kind IN ('Select', 'Insert')
      AND event_date >= today() - 30 /*days*/
    GROUP BY second, query_kind
)
GROUP BY hour, query_kind
ORDER BY hour, query_kind
SETTINGS skip_unavailable_shards = 1
