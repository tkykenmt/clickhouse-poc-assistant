-- Query patterns with index and read efficiency, heaviest first. Basis for query advice.
-- sample_query is one raw query text per pattern (literals included); it stays inside this conversation.
SELECT
    toString(normalized_query_hash) AS query_hash,
    query_kind,
    arrayStringConcat(any(tables), ' ') AS query_tables,
    leftUTF8(any(query), 1000) AS sample_query,
    count() AS executions,
    round(quantile(0.5)(query_duration_ms)) AS p50_ms,
    round(quantile(0.99)(query_duration_ms)) AS p99_ms,
    round(avg(read_rows)) AS avg_read_rows,
    round(avg(result_rows)) AS avg_result_rows,
    round(avg(ProfileEvents['SelectedParts'])) AS avg_selected_parts,
    round(avg(ProfileEvents['SelectedMarks'])) AS avg_selected_marks,
    round(avg(ProfileEvents['SelectedMarksTotal'])) AS avg_total_marks,
    round(avg(ProfileEvents['SelectedMarks']) / nullIf(avg(ProfileEvents['SelectedMarksTotal']), 0), 3) AS marks_read_ratio,
    max(memory_usage) AS max_memory_bytes,
    countIf(ProfileEvents['ExternalAggregationWritePart'] > 0) AS spilled_group_by_executions,
    countIf(ProfileEvents['ExternalJoinWritePart'] > 0 OR ProfileEvents['JoinSpillingHashJoinSwitchedToGraceJoin'] > 0) AS spilled_join_executions,
    countIf(Settings['enable_analyzer'] = '0' OR Settings['allow_experimental_analyzer'] = '0') AS old_analyzer_executions,
    arrayStringConcat(arrayDistinct(flatten(groupArray(projections))), ' ') AS projections_used,
    round(avg(ProfileEvents['FilteringMarksWithSecondaryKeysMicroseconds']) / 1e3, 1) AS avg_skip_index_ms,
    round(countIf(query_cache_usage = 'Read') / count(), 3) AS query_cache_read_share,
    max(has(used_aggregate_functions, 'uniqExact')) AS uses_uniq_exact,
    countIf(Settings['final'] = '1' OR match(query, '(?i)\\b(FROM|JOIN)\\s+[^\\s()]+(\\s+(AS\\s+)?\\w+)?\\s+FINAL\\b')) AS final_executions,
    round(avg(length(columns))) AS avg_columns_read,
    round(avg(read_bytes)) AS avg_read_bytes,
    round(avg(ProfileEvents['UserTimeMicroseconds'] + ProfileEvents['SystemTimeMicroseconds']) / 1e3, 1) AS avg_cpu_ms,
    round(sum(ProfileEvents['UserTimeMicroseconds'] + ProfileEvents['SystemTimeMicroseconds']) / 1e6, 1) AS total_cpu_seconds
FROM clusterAllReplicas('default', merge('system', '^query_log'))
WHERE type = 'QueryFinish'
  AND is_initial_query
  AND NOT (user = currentUser()  -- this connection's own reads of system tables; other queries of the same user stay (failures before start have no tables and stay)
           AND notEmpty(tables) AND arrayAll(t -> startsWith(t, 'system.') OR startsWith(lower(t), 'information_schema.')
                           OR t IN ('_table_function.clusterAllReplicas', '_table_function.merge'), tables))
  AND user NOT LIKE '%-internal'  -- ClickHouse Cloud's own monitoring users
  AND query_kind = 'Select'
  AND event_date >= today() - 30 /*days*/
GROUP BY query_hash, query_kind
ORDER BY total_cpu_seconds DESC
LIMIT 30
SETTINGS skip_unavailable_shards = 1
