-- Load-test window, every 10 seconds and replica: CPU used and CPU waited by ClickHouse threads,
-- against the replica's CPU limit, with running queries and tracked memory.
-- cpu_cores and cpu_wait_cores are averages over the 10 seconds (core-seconds / 10).
-- cpu_cores can stay below cpu_limit_cores while threads queue for a CPU, so judge saturation from cpu_wait_ratio.
-- container_cpu_cores is the CPU used by the whole container (CGroupUserTime + CGroupSystemTime, averaged over the 10 seconds);
-- compare it with cpu_limit_cores. A large container_system_cores is kernel time, for example from switching between many threads.
-- cpu_wait_ratio (CPU wait / CPU busy) is the ratio ClickHouse itself uses to detect CPU overload:
-- https://clickhouse.com/docs/concepts/features/configuration/settings/server-overload
-- queries_started, connections and the filesystem cache columns show whether load was spread evenly and whether the cache was cold;
-- the cache hit rate and S3 read wait follow the Cloud console's advanced dashboard:
-- https://clickhouse.com/docs/products/cloud/features/monitoring/cloud-console#advanced-dashboard
-- Replace the two window markers with the test's start and end in UTC, as in 30_window_query_breakdown.sql.
SELECT
    m.replica,
    m.t,
    m.cpu_cores,
    m.cpu_wait_cores,
    m.cpu_wait_ratio,
    c.container_cpu_cores,
    c.container_system_cores,
    l.cpu_limit_cores,
    m.max_running_queries,
    m.queries_started,
    m.queries_delayed_for_cpu_slots,
    c.memory_used_ratio,
    m.max_tcp_connections,
    m.max_http_connections,
    m.fs_cache_hit_rate,
    m.s3_read_wait_seconds,
    c.max_parts_in_partition,
    m.max_memory_tracked_bytes
FROM
(
    SELECT
        hostname AS replica,
        toStartOfInterval(event_time, INTERVAL 10 SECOND) AS t,
        round(sum(ProfileEvent_OSCPUVirtualTimeMicroseconds) / 10e6, 2) AS cpu_cores,
        round(sum(ProfileEvent_OSCPUWaitMicroseconds) / 10e6, 2) AS cpu_wait_cores,
        round(sum(ProfileEvent_OSCPUWaitMicroseconds) / nullIf(sum(ProfileEvent_OSCPUVirtualTimeMicroseconds), 0), 2) AS cpu_wait_ratio,
        max(CurrentMetric_Query) AS max_running_queries,
        sum(ProfileEvent_Query) AS queries_started,
        sum(ProfileEvent_ConcurrencyControlQueriesDelayed) AS queries_delayed_for_cpu_slots,
        max(CurrentMetric_TCPConnection) AS max_tcp_connections,
        max(CurrentMetric_HTTPConnection) AS max_http_connections,
        round(sum(ProfileEvent_CachedReadBufferReadFromCacheBytes)
              / nullIf(sum(ProfileEvent_CachedReadBufferReadFromCacheBytes) + sum(ProfileEvent_CachedReadBufferReadFromSourceBytes), 0), 3) AS fs_cache_hit_rate,
        round(sum(ProfileEvent_ReadBufferFromS3Microseconds) / 1e6, 2) AS s3_read_wait_seconds,
        max(CurrentMetric_MemoryTracking) AS max_memory_tracked_bytes
    FROM clusterAllReplicas('default', merge('system', '^metric_log'))
    WHERE event_date BETWEEN toDate(now() - INTERVAL 1 HOUR /*window_start*/) AND toDate(now() /*window_end*/)
      AND event_time >= now() - INTERVAL 1 HOUR /*window_start*/
      AND event_time < now() /*window_end*/
    GROUP BY replica, t
) AS m
LEFT JOIN
(
    SELECT hostname AS replica, max(value) AS cpu_limit_cores
    FROM clusterAllReplicas('default', merge('system', '^asynchronous_metric_log'))
    WHERE metric = 'CGroupMaxCPU'
      AND event_date BETWEEN toDate(now() - INTERVAL 1 HOUR /*window_start*/) AND toDate(now() /*window_end*/)
      AND event_time >= now() - INTERVAL 1 HOUR /*window_start*/
      AND event_time < now() /*window_end*/
    GROUP BY replica
) AS l ON m.replica = l.replica
LEFT JOIN
(
    SELECT
        hostname AS replica,
        toStartOfInterval(event_time, INTERVAL 10 SECOND) AS t,
        round(avgIf(value, metric = 'CGroupUserTime') + avgIf(value, metric = 'CGroupSystemTime'), 2) AS container_cpu_cores,
        round(avgIf(value, metric = 'CGroupSystemTime'), 2) AS container_system_cores,
        maxIf(value, metric = 'MaxPartCountForPartition') AS max_parts_in_partition,
        round(avgIf(value, metric = 'CGroupMemoryUsedWithoutPageCache') / nullIf(maxIf(value, metric = 'CGroupMemoryTotal'), 0), 3) AS memory_used_ratio
    FROM clusterAllReplicas('default', merge('system', '^asynchronous_metric_log'))
    WHERE metric IN ('CGroupUserTime', 'CGroupSystemTime', 'MaxPartCountForPartition', 'CGroupMemoryUsedWithoutPageCache', 'CGroupMemoryTotal')
      AND event_date BETWEEN toDate(now() - INTERVAL 1 HOUR /*window_start*/) AND toDate(now() /*window_end*/)
      AND event_time >= now() - INTERVAL 1 HOUR /*window_start*/
      AND event_time < now() /*window_end*/
    GROUP BY replica, t
) AS c ON m.replica = c.replica AND m.t = c.t
ORDER BY m.t, m.replica
SETTINGS skip_unavailable_shards = 1
