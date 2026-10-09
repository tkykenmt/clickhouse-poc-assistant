-- Insert shape per table: frequency, rows and parts per insert, async inserts, attached views, delays and deduplication.
-- Rows per insert come from the parts each insert wrote (part_log NewPart grouped by query_id): query_log written_rows
-- also counts rows written by attached materialized views. For async inserts a part is written per flush, so the
-- figures describe the flushes. async_inserts_without_wait counts wait_for_async_insert = 0 (the Settings map holds only changed settings).
SELECT
    q.target_table AS target_table,
    q.inserts AS inserts,
    q.inserts_per_second AS inserts_per_second,
    p.p50_rows_per_insert AS p50_rows_per_insert,
    p.p10_rows_per_insert AS p10_rows_per_insert,
    p.avg_parts_per_insert AS avg_parts_per_insert,
    p.max_parts_per_insert AS max_parts_per_insert,
    q.async_inserts AS async_inserts,
    q.async_inserts_without_wait AS async_inserts_without_wait,
    q.max_attached_views AS max_attached_views,
    q.avg_delayed_insert_ms AS avg_delayed_insert_ms,
    q.duplicated_blocks AS duplicated_blocks,
    q.avg_ms AS avg_ms
FROM
(
    SELECT
        -- Only tables named before any SELECT are targets: INSERT ... SELECT also lists the tables it reads.
        arrayJoin(arrayFilter(t -> positionCaseInsensitive(
            substring(query, 1, if(positionCaseInsensitive(query, 'SELECT') > 0, positionCaseInsensitive(query, 'SELECT'), length(query))),
            splitByChar('.', t)[-1]) > 0, tables)) AS target_table,
        count() AS inserts,
        round(count() / greatest(dateDiff('second', min(event_time), max(event_time)), 1), 3) AS inserts_per_second,
        countIf(Settings['async_insert'] = '1') AS async_inserts,
        countIf(Settings['async_insert'] = '1' AND Settings['wait_for_async_insert'] = '0') AS async_inserts_without_wait,
        max(length(views)) AS max_attached_views,
        round(avg(ProfileEvents['DelayedInsertsMilliseconds']), 1) AS avg_delayed_insert_ms,
        sum(ProfileEvents['DuplicatedInsertedBlocks'] + ProfileEvents['DuplicatedAsyncInserts']) AS duplicated_blocks,
        round(avg(query_duration_ms)) AS avg_ms
    FROM clusterAllReplicas('default', merge('system', '^query_log'))
    WHERE type = 'QueryFinish'
      AND is_initial_query
      AND NOT (user = currentUser()  -- this connection's own reads of system tables; other queries of the same user stay (failures before start have no tables and stay)
               AND notEmpty(tables) AND arrayAll(t -> startsWith(t, 'system.') OR startsWith(lower(t), 'information_schema.')
                               OR t IN ('_table_function.clusterAllReplicas', '_table_function.merge'), tables))
      AND user NOT LIKE '%-internal'  -- ClickHouse Cloud's own monitoring users
      AND log_comment != 'poc-assistant'  -- queries the assistant ran on user tables with the user's approval
      AND query_kind = 'Insert'
      AND event_date >= today() - 30 /*days*/
    GROUP BY target_table
    HAVING target_table NOT LIKE 'system.%' AND target_table NOT LIKE '\_table\_function.%'
) AS q
LEFT JOIN
(
    SELECT
        target_table,
        round(quantile(0.5)(rows)) AS p50_rows_per_insert,
        round(quantile(0.1)(rows)) AS p10_rows_per_insert,
        round(avg(parts), 2) AS avg_parts_per_insert,
        max(parts) AS max_parts_per_insert
    FROM
    (
        SELECT concat(database, '.', table) AS target_table, query_id, sum(rows) AS rows, count() AS parts
        FROM clusterAllReplicas('default', merge('system', '^part_log'))
        WHERE event_type = 'NewPart'
          AND error = 0                                -- deduplicated retries are logged with an error
          AND query_id != ''                           -- background writers such as Buffer tables
          AND NOT startsWith(partition_id, 'patch-')   -- patch parts of lightweight updates
          AND event_date >= today() - 30 /*days*/
          AND database NOT IN ('system', 'INFORMATION_SCHEMA', 'information_schema')
        GROUP BY target_table, query_id
    )
    GROUP BY target_table
) AS p ON q.target_table = p.target_table
ORDER BY inserts DESC
LIMIT 50
SETTINGS skip_unavailable_shards = 1, join_use_nulls = 1
