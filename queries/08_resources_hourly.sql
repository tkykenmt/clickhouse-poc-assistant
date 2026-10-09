-- Resource use per hour and replica: running queries, merges, memory, CPU and rows.
SELECT
    toStartOfHour(event_time) AS hour,
    hostname AS replica,
    max(CurrentMetric_Query) AS max_running_queries,
    max(CurrentMetric_Merge) AS max_running_merges,
    max(CurrentMetric_MemoryTracking) AS max_memory_tracked_bytes,
    round(sum(ProfileEvent_OSCPUVirtualTimeMicroseconds) / 1e6, 1) AS cpu_seconds,
    sum(ProfileEvent_SelectedRows) AS selected_rows,
    sum(ProfileEvent_InsertedRows) AS inserted_rows,
    sum(ProfileEvent_InsertedBytes) AS inserted_bytes
FROM clusterAllReplicas('default', merge('system', '^metric_log'))
WHERE event_date >= today() - 30 /*days*/
GROUP BY hour, replica
ORDER BY hour, replica
SETTINGS skip_unavailable_shards = 1
