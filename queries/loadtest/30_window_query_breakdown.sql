-- Load-test window, per minute and query pattern: where the time goes (CPU, waiting for CPU, I/O wait)
-- and how much each query reads compared with what it returns. Ten busiest patterns per minute.
-- Rows are also split by log_comment, so a load tool that tags each step (for example log_comment = 'step_c8') can be read per step.
-- Replace the two window markers with the test's start and end in UTC, for example
-- toDateTime('2026-10-09 08:57:50', 'UTC') /*window_start*/.
SELECT
    toStartOfMinute(event_time) AS minute,
    log_comment,
    toString(normalized_query_hash) AS query_hash,
    query_kind,
    arrayStringConcat(any(tables), ' ') AS query_tables,
    count() AS executions,
    countIf(type = 'ExceptionWhileProcessing') AS errors,
    arrayStringConcat(topKIf(3)(errorCodeToName(exception_code), exception_code != 0), ' ') AS top_errors,
    round(quantile(0.5)(query_duration_ms)) AS p50_ms,
    round(quantile(0.99)(query_duration_ms)) AS p99_ms,
    round(avg(ProfileEvents['OSCPUVirtualTimeMicroseconds']) / 1e3, 1) AS avg_cpu_ms,
    round(avg(ProfileEvents['OSCPUWaitMicroseconds']) / 1e3, 1) AS avg_cpu_wait_ms,
    round(sum(ProfileEvents['OSCPUWaitMicroseconds']) / nullIf(sum(ProfileEvents['OSCPUVirtualTimeMicroseconds']), 0), 2) AS cpu_wait_ratio,
    round(avg(ProfileEvents['OSIOWaitMicroseconds']) / 1e3, 1) AS avg_io_wait_ms,
    round(sum(ProfileEvents['CachedReadBufferReadFromCacheBytes'])
          / nullIf(sum(ProfileEvents['CachedReadBufferReadFromCacheBytes']) + sum(ProfileEvents['CachedReadBufferReadFromSourceBytes']), 0), 3) AS fs_cache_hit_rate,
    round(avg(ProfileEvents['ReadBufferFromS3Microseconds']) / 1e3, 1) AS avg_s3_read_ms,
    round(avg(ProfileEvents['DelayedInsertsMilliseconds']), 1) AS avg_delayed_insert_ms,
    sum(ProfileEvents['DuplicatedInsertedBlocks'] + ProfileEvents['DuplicatedAsyncInserts']) AS duplicated_blocks,
    round(countIf(query_cache_usage = 'Read') / count(), 3) AS query_cache_read_share,
    round(countIf(ProfileEvents['QueryConditionCacheHits'] > 0) / count(), 3) AS condition_cache_hit_share,
    round(avg(ProfileEvents['ConcurrencyControlWaitMicroseconds']) / 1e3, 1) AS avg_cpu_slot_wait_ms,
    sum(ProfileEvents['RejectedInserts']) AS rejected_inserts,
    round(avg(ProfileEvents['SelectedParts']), 1) AS avg_selected_parts,
    round(avg(ProfileEvents['SelectedMarks']), 1) AS avg_selected_marks,
    round(avg(read_rows)) AS avg_read_rows,
    round(avg(result_rows), 1) AS avg_result_rows,
    round(avg(peak_threads_usage), 1) AS avg_peak_threads,
    max(memory_usage) AS max_memory_bytes
FROM clusterAllReplicas('default', merge('system', '^query_log'))
WHERE type IN ('QueryFinish', 'ExceptionWhileProcessing')
  AND is_initial_query
  AND NOT (user = currentUser()  -- this connection's own reads of system tables; other queries of the same user stay
           AND arrayAll(t -> startsWith(t, 'system.') OR startsWith(lower(t), 'information_schema.')
                           OR t IN ('_table_function.clusterAllReplicas', '_table_function.merge'), tables))
  AND user NOT LIKE '%-internal'  -- ClickHouse Cloud's own monitoring users
  AND query_kind IN ('Select', 'Insert')
  AND event_date BETWEEN toDate(now() - INTERVAL 1 HOUR /*window_start*/) AND toDate(now() /*window_end*/)
  AND event_time >= now() - INTERVAL 1 HOUR /*window_start*/
  AND event_time < now() /*window_end*/
GROUP BY minute, log_comment, query_hash, query_kind
ORDER BY minute, executions DESC
LIMIT 10 BY minute
SETTINGS skip_unavailable_shards = 1
