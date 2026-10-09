-- Insert shape per target table: last 24 hours against the 7 days before.
-- Rows per insert come from the parts each insert wrote (part_log NewPart grouped by query_id), not from
-- query_log written_rows, which also counts rows written by attached materialized views.
WITH now() - INTERVAL 1 DAY AS day_start
SELECT
    q.target_table AS target_table,
    q.inserts_24h AS inserts_24h,
    q.inserts_daily_avg_prev_7d AS inserts_daily_avg_prev_7d,
    p.p50_rows_per_insert_24h AS p50_rows_per_insert_24h,
    p.p50_rows_per_insert_prev_7d AS p50_rows_per_insert_prev_7d,
    q.async_inserts_24h AS async_inserts_24h,
    q.async_inserts_without_wait_24h AS async_inserts_without_wait_24h
FROM
(
    SELECT
        arrayJoin(tables) AS target_table,
        countIf(event_time >= day_start) AS inserts_24h,
        round(countIf(event_time < day_start) / 7) AS inserts_daily_avg_prev_7d,
        countIf(event_time >= day_start AND Settings['async_insert'] = '1') AS async_inserts_24h,
        countIf(event_time >= day_start AND Settings['async_insert'] = '1' AND Settings['wait_for_async_insert'] = '0') AS async_inserts_without_wait_24h
    FROM clusterAllReplicas('default', merge('system', '^query_log'))
    WHERE type = 'QueryFinish'
      AND query_kind = 'Insert'
      AND is_initial_query
      AND NOT (user = currentUser()  -- this connection's own reads of system tables; other queries of the same user stay
               AND arrayAll(t -> startsWith(t, 'system.') OR startsWith(lower(t), 'information_schema.')
                               OR t IN ('_table_function.clusterAllReplicas', '_table_function.merge'), tables))
      AND user NOT LIKE '%-internal'  -- ClickHouse Cloud's own monitoring users
      AND event_date >= today() - 8
      AND event_time >= now() - INTERVAL 8 DAY
    GROUP BY target_table
    HAVING target_table NOT LIKE 'system.%' AND target_table NOT LIKE '\_table\_function.%'
) AS q
LEFT JOIN
(
    SELECT
        target_table,
        round(quantileIf(0.5)(rows, last_time >= day_start)) AS p50_rows_per_insert_24h,
        round(quantileIf(0.5)(rows, last_time < day_start)) AS p50_rows_per_insert_prev_7d
    FROM
    (
        SELECT concat(database, '.', table) AS target_table, query_id, sum(rows) AS rows, max(event_time) AS last_time
        FROM clusterAllReplicas('default', merge('system', '^part_log'))
        WHERE event_type = 'NewPart'
          AND event_date >= today() - 8
          AND event_time >= now() - INTERVAL 8 DAY
          AND database NOT IN ('system', 'INFORMATION_SCHEMA', 'information_schema')
        GROUP BY target_table, query_id
    )
    GROUP BY target_table
) AS p ON q.target_table = p.target_table
ORDER BY inserts_24h DESC
LIMIT 30
SETTINGS skip_unavailable_shards = 1
