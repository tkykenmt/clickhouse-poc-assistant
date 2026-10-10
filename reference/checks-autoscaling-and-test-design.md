# Checks: autoscaling and test design

Each check names the columns it reads, the rule, and the public source of the rule. The URLs have been checked; cite them as they are.

## Why autoscaling did or did not react

- **Columns**: `cpu_limit_cores` over the window (`queries/loadtest/31_window_cpu_10s.sql`), `uptime_seconds` (`queries/01_service.sql`).
- **Rule**: explain only from these sources, not from guesses. The documentation gives the CPU band: target utilization 53%, scale up above 75% and scale down below 37.5% of the allocated CPU, with the recommended size = peak CPU usage ÷ 0.53. CPU is smoothed with a 10-minute rolling median per replica, which is described only in the ClickHouse blog, so cite it as the blog (section "Smoothing out transient spikes"). Scaling is make-before-break. A step much shorter than 10 minutes moves the 10-minute median little. The autoscaler's decisions and the service's minimum and maximum size are not visible from system tables; say so and point to the console.
- **Source**: https://clickhouse.com/docs/products/cloud/features/autoscaling/scaling-recommendations , https://clickhouse.com/blog/smarter-auto-scaling , https://clickhouse.com/docs/products/cloud/features/autoscaling/make-before-break

## How to compare two runs

- **Columns**: `p50_ratio`, `p99_ratio`, `read_rows_ratio`, `avg_cpu_ms_a`/`_b`, `executions_a`/`_b`, `query_cache_read_share_a`/`_b`, `condition_cache_hit_share_a`/`_b`, `fs_cache_hit_rate_a`/`_b`, `avg_peak_threads_a`/`_b`, `errors_a`/`_b` (`queries/loadtest/32_compare_windows.sql`).
- **Rule**: a comparison is fair only when the two runs had the same load, the same cache conditions and one change between them. If `query_cache_read_share`, `condition_cache_hit_share` or `fs_cache_hit_rate` differs between the runs, or the number of executions differs a lot under a closed-loop tool, say that the ratio mixes the change with that difference. A NULL `fs_cache_hit_rate` means the run read nothing through the filesystem cache, so that column tells nothing about fairness. If `30` shows inserts or other heavy patterns in only one of the windows, the runs did not have the same conditions. With few executions of short queries, p99 is set by one or two runs; say so. Change one thing at a time and use the median of repeated runs after warm-up. To find where the time went in each run, run `30` for both windows.
- **Source**: https://clickhouse.com/docs/guides/clickhouse/performance-and-monitoring/isolate-query-bottlenecks

## How to run the next test

- **Rule**: fix the size (minimum = maximum) when measuring capacity; hold each step well beyond the 10-minute smoothing window when observing autoscaling; use an open-loop rate when the question is whether a rate can be sustained; tag each step with `log_comment` so `query_log` can be filtered by step; measure cold and warm runs separately and keep cache conditions the same between compared runs.
- **Source**: https://clickhouse.com/docs/products/cloud/features/autoscaling/vertical , https://clickhouse.com/docs/reference/settings/session-settings/log#log_comment , https://clickhouse.com/docs/guides/clickhouse/performance-and-monitoring/isolate-query-bottlenecks
