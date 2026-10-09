-- Query patterns with index and read efficiency, heaviest first. Basis for query advice.
-- sample_query is one raw query text per pattern (literals included); it stays inside this conversation.
SELECT
    toString(normalized_query_hash) AS query_hash,
    query_kind,
    arrayStringConcat(any(tables), ' ') AS tables,
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
    round(avg(ProfileEvents['UserTimeMicroseconds'] + ProfileEvents['SystemTimeMicroseconds']) / 1e3, 1) AS avg_cpu_ms,
    round(sum(ProfileEvents['UserTimeMicroseconds'] + ProfileEvents['SystemTimeMicroseconds']) / 1e6, 1) AS total_cpu_seconds
FROM clusterAllReplicas('default', merge('system', '^query_log'))
WHERE type = 'QueryFinish'
  AND is_initial_query
  AND user != currentUser()
  AND user NOT LIKE '%-internal'  -- ClickHouse Cloud's own monitoring users
  AND query_kind = 'Select'
  AND event_date >= today() - 30 /*days*/
GROUP BY query_hash, query_kind
ORDER BY total_cpu_seconds DESC
LIMIT 30
SETTINGS skip_unavailable_shards = 1
