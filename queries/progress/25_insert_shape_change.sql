-- Insert shape per target table: last 24 hours against the 7 days before.
WITH now() - INTERVAL 1 DAY AS day_start
SELECT
    arrayJoin(tables) AS target_table,
    countIf(event_time >= day_start) AS inserts_24h,
    round(countIf(event_time < day_start) / 7) AS inserts_daily_avg_prev_7d,
    round(quantileIf(0.5)(written_rows, event_time >= day_start)) AS p50_rows_per_insert_24h,
    round(quantileIf(0.5)(written_rows, event_time < day_start)) AS p50_rows_per_insert_prev_7d,
    countIf(event_time >= day_start AND Settings['async_insert'] = '1') AS async_inserts_24h
FROM clusterAllReplicas('default', merge('system', '^query_log'))
WHERE type = 'QueryFinish'
  AND query_kind = 'Insert'
  AND is_initial_query
  AND user != currentUser()
  AND user NOT LIKE '%-internal'  -- ClickHouse Cloud's own monitoring users
  AND event_date >= today() - 8
  AND event_time >= now() - INTERVAL 8 DAY
GROUP BY target_table
HAVING target_table NOT LIKE 'system.%' AND target_table NOT LIKE '\_table\_function.%'
ORDER BY inserts_24h DESC
LIMIT 30
SETTINGS skip_unavailable_shards = 1
