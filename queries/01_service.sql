-- Service shape: one row per replica with version, uptime and resource limits.
SELECT
    hostName() AS replica,
    version() AS version,
    uptime() AS uptime_seconds,
    maxIf(value, metric = 'CGroupMaxCPU') AS cpu_limit_cores,
    maxIf(value, metric = 'CGroupMemoryTotal') AS memory_limit_bytes,
    maxIf(value, metric = 'NumberOfTables') AS tables_on_replica
FROM clusterAllReplicas('default', system.asynchronous_metrics)
GROUP BY replica
ORDER BY replica
SETTINGS skip_unavailable_shards = 1
