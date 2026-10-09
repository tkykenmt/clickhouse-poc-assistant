-- Query load per hour for SELECT and INSERT: count, peak queries per second, latency and CPU.
SELECT
    toStartOfHour(event_time) AS hour,
    query_kind,
    count() AS queries,
    countIf(type = 'ExceptionWhileProcessing') AS errors,
    max(per_second) AS peak_queries_per_second,
    round(quantile(0.5)(query_duration_ms)) AS p50_ms,
    round(quantile(0.99)(query_duration_ms)) AS p99_ms,
    round(sum(ProfileEvents['UserTimeMicroseconds'] + ProfileEvents['SystemTimeMicroseconds']) / 1e6, 1) AS cpu_seconds,
    sum(read_rows) AS read_rows,
    sum(written_rows) AS written_rows
FROM
(
    SELECT
        event_time, query_kind, type, query_duration_ms, ProfileEvents, read_rows, written_rows,
        count() OVER (PARTITION BY query_kind, event_time) AS per_second
    FROM clusterAllReplicas('default', merge('system', '^query_log'))
    WHERE type IN ('QueryFinish', 'ExceptionWhileProcessing')
      AND is_initial_query
      AND user != currentUser()
      AND user NOT LIKE '%-internal'  -- ClickHouse Cloud's own monitoring users
      AND query_kind IN ('Select', 'Insert')
      AND event_date >= today() - 30 /*days*/
)
GROUP BY hour, query_kind
ORDER BY hour, query_kind
SETTINGS skip_unavailable_shards = 1
