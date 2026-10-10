-- Two runs compared per query pattern: run A (for example before a change) and run B (after it).
-- Replace the four markers with the start and end of each run in UTC, for example toDateTime('2026-10-09 08:57:50', 'UTC') /*a_start*/.
-- Compare only runs with the same load (users or rate) and the same cache conditions: query_cache_read_share shows
-- results served from the query cache, fs_cache_hit_rate shows a cold or warm filesystem cache.
-- Ratios are B / A; NULL when the pattern ran in only one of the runs.
-- Latency percentiles count finished queries only; failed queries are in errors_a and errors_b.
WITH
    now() - INTERVAL 2 HOUR /*a_start*/ AS a_start,
    now() - INTERVAL 1 HOUR /*a_end*/ AS a_end,
    now() - INTERVAL 1 HOUR /*b_start*/ AS b_start,
    now() /*b_end*/ AS b_end
SELECT
    query_hash,
    any(run_tables) AS query_tables,
    sumIf(executions, run = 'A') AS executions_a,
    sumIf(executions, run = 'B') AS executions_b,
    anyIf(toNullable(p50_ms), run = 'A') AS p50_ms_a,
    anyIf(toNullable(p50_ms), run = 'B') AS p50_ms_b,
    round(p50_ms_b / nullIf(p50_ms_a, 0), 2) AS p50_ratio,
    anyIf(toNullable(p99_ms), run = 'A') AS p99_ms_a,
    anyIf(toNullable(p99_ms), run = 'B') AS p99_ms_b,
    round(p99_ms_b / nullIf(p99_ms_a, 0), 2) AS p99_ratio,
    anyIf(toNullable(avg_cpu_ms), run = 'A') AS avg_cpu_ms_a,
    anyIf(toNullable(avg_cpu_ms), run = 'B') AS avg_cpu_ms_b,
    anyIf(toNullable(avg_read_rows), run = 'A') AS avg_read_rows_a,
    anyIf(toNullable(avg_read_rows), run = 'B') AS avg_read_rows_b,
    round(avg_read_rows_b / nullIf(avg_read_rows_a, 0), 2) AS read_rows_ratio,
    anyIf(toNullable(avg_selected_marks), run = 'A') AS avg_selected_marks_a,
    anyIf(toNullable(avg_selected_marks), run = 'B') AS avg_selected_marks_b,
    anyIf(toNullable(query_cache_read_share), run = 'A') AS query_cache_read_share_a,
    anyIf(toNullable(query_cache_read_share), run = 'B') AS query_cache_read_share_b,
    anyIf(toNullable(fs_cache_hit_rate), run = 'A') AS fs_cache_hit_rate_a,
    anyIf(toNullable(fs_cache_hit_rate), run = 'B') AS fs_cache_hit_rate_b,
    anyIf(toNullable(condition_cache_hit_share), run = 'A') AS condition_cache_hit_share_a,
    anyIf(toNullable(condition_cache_hit_share), run = 'B') AS condition_cache_hit_share_b,
    anyIf(toNullable(avg_peak_threads), run = 'A') AS avg_peak_threads_a,
    anyIf(toNullable(avg_peak_threads), run = 'B') AS avg_peak_threads_b,
    sumIf(errors, run = 'A') AS errors_a,
    sumIf(errors, run = 'B') AS errors_b
FROM
(
    SELECT
        if(event_time >= b_start AND event_time < b_end, 'B', 'A') AS run,
        toString(normalized_query_hash) AS query_hash,
        arrayStringConcat(any(tables), ' ') AS run_tables,
        count() AS executions,
        countIf(type = 'ExceptionWhileProcessing') AS errors,
        round(quantileIf(0.5)(query_duration_ms, type = 'QueryFinish')) AS p50_ms,
        round(quantileIf(0.99)(query_duration_ms, type = 'QueryFinish')) AS p99_ms,
        round(avg(ProfileEvents['OSCPUVirtualTimeMicroseconds']) / 1e3, 1) AS avg_cpu_ms,
        round(avg(read_rows)) AS avg_read_rows,
        round(avg(ProfileEvents['SelectedMarks']), 1) AS avg_selected_marks,
        round(countIf(query_cache_usage = 'Read') / count(), 3) AS query_cache_read_share,
        round(countIf(ProfileEvents['QueryConditionCacheHits'] > 0) / count(), 3) AS condition_cache_hit_share,
        round(avg(peak_threads_usage), 1) AS avg_peak_threads,
        round(sum(ProfileEvents['CachedReadBufferReadFromCacheBytes'])
              / nullIf(sum(ProfileEvents['CachedReadBufferReadFromCacheBytes']) + sum(ProfileEvents['CachedReadBufferReadFromSourceBytes']), 0), 3) AS fs_cache_hit_rate
    FROM clusterAllReplicas('default', merge('system', '^query_log'))
    WHERE type IN ('QueryFinish', 'ExceptionWhileProcessing')
      AND is_initial_query
      AND NOT (user = currentUser()  -- this connection's own reads of system tables; other queries of the same user stay (failures before start have no tables and stay)
               AND notEmpty(tables) AND arrayAll(t -> startsWith(t, 'system.') OR startsWith(lower(t), 'information_schema.')
                               OR t IN ('_table_function.clusterAllReplicas', '_table_function.merge'), tables))
      AND user NOT LIKE '%-internal'  -- ClickHouse Cloud's own monitoring users
      AND log_comment != 'poc-assistant'  -- queries the assistant ran on user tables with the user's approval
      AND query_kind = 'Select'
      AND event_date BETWEEN toDate(least(a_start, b_start)) - 1 AND toDate(greatest(a_end, b_end)) + 1  -- a day either side: event_date is in the server time zone
      AND ((event_time >= a_start AND event_time < a_end) OR (event_time >= b_start AND event_time < b_end))
    GROUP BY run, query_hash
)
GROUP BY query_hash
ORDER BY executions_a + executions_b DESC
LIMIT 30
SETTINGS skip_unavailable_shards = 1
