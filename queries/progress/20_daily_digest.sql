-- Last 24 hours against the daily average of the 7 days before: ingest, queries, latency, errors.
WITH
    now() - INTERVAL 1 DAY AS day_start,
    now() - INTERVAL 8 DAY AS base_start
SELECT
    query_kind,
    countIf(event_time >= day_start) AS last_24h,
    round(countIf(event_time < day_start) / 7) AS daily_avg_prev_7d,
    countIf(event_time >= day_start AND type = 'ExceptionWhileProcessing') AS errors_last_24h,
    round(quantileIf(0.99)(query_duration_ms, event_time >= day_start)) AS p99_ms_last_24h,
    round(quantileIf(0.99)(query_duration_ms, event_time < day_start)) AS p99_ms_prev_7d,
    sumIf(written_rows, event_time >= day_start) AS written_rows_last_24h,
    round(sumIf(written_rows, event_time < day_start) / 7) AS written_rows_daily_avg_prev_7d
FROM clusterAllReplicas('default', merge('system', '^query_log'))
WHERE type IN ('QueryFinish', 'ExceptionWhileProcessing')
  AND is_initial_query
  AND user != currentUser()
  AND user NOT LIKE '%-internal'  -- ClickHouse Cloud's own monitoring users
  AND query_kind IN ('Select', 'Insert')
  AND event_date >= toDate(base_start)
  AND event_time >= base_start
GROUP BY query_kind
ORDER BY query_kind
SETTINGS skip_unavailable_shards = 1
