-- Insert shape per table: batch size, frequency and async inserts. Basis for ingestion advice.
SELECT
    arrayJoin(tables) AS target_table,
    count() AS inserts,
    round(count() / greatest(dateDiff('second', min(event_time), max(event_time)), 1), 3) AS inserts_per_second,
    round(quantile(0.5)(written_rows)) AS p50_rows_per_insert,
    round(quantile(0.1)(written_rows)) AS p10_rows_per_insert,
    countIf(Settings['async_insert'] = '1') AS async_inserts,
    round(avg(query_duration_ms)) AS avg_ms
FROM clusterAllReplicas('default', merge('system', '^query_log'))
WHERE type = 'QueryFinish'
  AND is_initial_query
  AND user NOT LIKE '%-internal'
  AND query_kind = 'Insert'
  AND event_date >= today() - 30 /*days*/
GROUP BY target_table
HAVING target_table NOT LIKE 'system.%' AND target_table NOT LIKE '\_table\_function.%'
ORDER BY inserts DESC
LIMIT 50
SETTINGS skip_unavailable_shards = 1
