# Checks: CPU, waiting and concurrency

Each check names the columns it reads, the rule, and the public source of the rule. Apply a check only when its columns are in the results you ran, and report it only when the numbers show it. The URLs have been checked; cite them as they are.

## Did latency come from work or from waiting?

- **Columns**: `avg_cpu_ms`, `avg_cpu_wait_ms`, `avg_io_wait_ms`, `p50_ms` of the same `query_hash` across minutes or steps (`queries/loadtest/30_window_query_breakdown.sql`).
- **Rule**: `OSCPUWaitMicroseconds` is the time a thread was ready to run but waiting to be scheduled; `OSIOWaitMicroseconds` is the time it waited for I/O. If `p50_ms` rises while `avg_cpu_ms` stays about the same and `avg_cpu_wait_ms` rises, the query did not get heavier; it waited for a CPU. If `avg_io_wait_ms` rises instead, look at storage reads.
- **Source**: https://clickhouse.com/docs/reference/system-tables/events

## Did the replicas run out of CPU?

- **Columns**: `cpu_wait_ratio`, `container_cpu_cores`, `container_system_cores`, `cpu_cores`, `cpu_limit_cores` per replica and 10 seconds (`queries/loadtest/31_window_cpu_10s.sql`, `queries/01_service.sql`).
- **Rule**: `cpu_wait_ratio` (CPU wait ÷ CPU busy) is the ratio ClickHouse itself uses to detect CPU overload. `container_cpu_cores` (`CGroupUserTime` + `CGroupSystemTime`) is the CPU used by the whole container; compare it with `cpu_limit_cores`. Do not judge from `cpu_cores` alone: it can stay below the limit while the container is at it. A rising `container_system_cores` while user time does not rise is kernel time. The Cloud console's advanced dashboard shows CPU wait per replica.
- **Source**: https://clickhouse.com/docs/concepts/features/configuration/settings/server-overload , https://clickhouse.com/docs/reference/system-tables/asynchronous_metrics#cgroupusertime , https://clickhouse.com/docs/products/cloud/features/monitoring/cloud-console#advanced-dashboard

## How many threads did each query use?

- **Columns**: `avg_peak_threads` (`30`).
- **Rule**: it can exceed `max_threads`: reads from storage run on a separate reader pool, and those threads count for the query. Many concurrent queries with many threads each means many threads queue for few cores.
- **Source**: https://clickhouse.com/docs/integrations/connectors/data-ingestion/AWS/integrating-s3-with-clickhouse#read--writes , https://clickhouse.com/docs/reference/settings/session-settings/max-threads

## Did the achieved rate fall short of the target?

- **Columns**: `executions` per minute or per `log_comment` (`30`).
- **Rule**: with a closed-loop tool (a fixed number of users that each wait for the previous response), an achieved rate below the target means the service could not take more of that query. As an estimate (Little's law, general queueing arithmetic, not a ClickHouse feature), the mean response time is about users ÷ achieved rate; compare it with `p50_ms`. With an open-loop tool (a fixed sending rate), a shortfall means the tool or the network limited the rate.
- **Source**: general queueing arithmetic; say so.

## Was the load spread across replicas?

- **Columns**: `queries_started`, `max_tcp_connections`, `max_http_connections` per replica (`31`).
- **Rule**: long-lived connections stay on the replicas that existed when they were opened, and adding replicas does not help while load is uneven. HTTP connections are short-lived by default; native-protocol clients should cap the connection lifetime at about 30 seconds.
- **Source**: https://clickhouse.com/docs/products/cloud/features/autoscaling/horizontal-autoscaling#configure-your-clients , https://clickhouse.com/docs/products/cloud/features/autoscaling/horizontal-autoscaling#load-distribution

## Why did queries fail?

- **Columns**: `top_errors`, `errors` (`30`), `max_running_queries` (`31`).
- **Rule**: `TOO_MANY_SIMULTANEOUS_QUERIES` means the limit of 1000 concurrent queries per replica was reached. For any other code, look it up with the documentation search tool before explaining it.
- **Source**: https://clickhouse.com/docs/products/cloud/reference/architecture#concurrency-limits

## Did queries get fewer CPU slots than they asked for?

- **Columns**: `queries_delayed_for_cpu_slots` per replica (`31`); `avg_cpu_slot_wait_ms` (`30`).
- **Rule**: when many concurrent queries with several threads each use all CPU slots, the server is in the overload state. `ConcurrencyControlQueriesDelayed` counts queries that got fewer slots than requested because of this pressure (a contention indicator): they still run, with fewer threads. `ConcurrencyControlWaitMicroseconds` is time spent waiting on CPU resource requests of workload scheduling; it stays at 0 when no CPU workload is defined, so a 0 there does not contradict a high delayed count. Read the delayed count together with `cpu_wait_ratio`.
- **Source**: https://clickhouse.com/docs/reference/system-tables/events , https://clickhouse.com/docs/concepts/features/configuration/server-config/workload-scheduling

## Was memory under pressure?

- **Columns**: `memory_used_ratio` (`CGroupMemoryUsedWithoutPageCache` ÷ `CGroupMemoryTotal`) per replica (`31`); `max_memory_bytes` per pattern (`30`, `queries/advisor/11_query_efficiency.sql`); `MEMORY_LIMIT_EXCEEDED` in `top_errors` or in `queries/progress/26_errors_by_code.sql`.
- **Rule**: a ratio approaching 1 means memory pressure (ClickHouse blog). The values without page cache exclude the userspace page cache, which is evicted when memory is needed. For `MEMORY_LIMIT_EXCEEDED`, the usual causes are large joins and aggregations on high-cardinality keys; the remedies are spilling to disk (`max_bytes_before_external_group_by`, `max_bytes_before_external_sort`), a smaller right-hand table or another join algorithm, or more memory.
- **Source**: https://clickhouse.com/blog/monitor-and-scale-clickhouse-cloud-with-clickhousectl (blog) , https://clickhouse.com/docs/reference/system-tables/asynchronous_metrics , https://clickhouse.com/docs/resources/support-center/knowledge-base/performance-optimization/memory-limit-exceeded-for-query
