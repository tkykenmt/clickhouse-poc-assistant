# clickhouse-poc-assistant

[日本語](README.ja.md)

Tools that help run a ClickHouse Cloud proof of concept (PoC). The work is split into skills, and one agent in [ClickHouse Agents](https://clickhouse.com/docs/products/cloud/features/ai-ml/agents) ("PoC assistant") picks the right skill for each request. Everything reads **system tables**. The advisor, load-test and daily skills query the user's own tables only to confirm a finding, after the user approves the queries, and return aggregates rather than rows; the sizing skill and the export kit never do.

| Skill | What it does |
|---|---|
| `poc-plan-builder` | Interviews the user about the workload, proposes success criteria with a measurement method and a public source for each, and writes the PoC plan as Markdown. Pass thresholds are left to the user. |
| `poc-sizing-stats` | Collects sizing statistics (storage, compression, ingest volume and peaks, query load, per-query cost) and writes a summary plus CSV-ready tables. |
| `poc-schema-query-advisor` | Reviews table design, query patterns and insert shape, and proposes up to five improvement candidates with the rule or documentation page behind each and a way to verify it. |
| `poc-load-test-review` | Reviews one load test window: where latency went (CPU, waiting for CPU, I/O), whether the replicas ran out of CPU, rows read against rows returned, and why autoscaling did or did not react, with the documentation behind each point. Also compares two runs before and after a change. |
| `poc-daily-progress` | Daily note: what changed in the last 24 hours, where each success criterion stands, advice limited to tables and queries that changed (at most three items), and next actions. Reads the PoC plan attached to the agent and outputs result lines to paste into the plan's `## Results`. |
| `poc-summary` | Weekly or final PoC summary for the people who decide: each criterion over the whole PoC with its evidence and weekly trend, what changed, open risks and next steps. Uses system tables and the plan's `## Results` for weeks older than 30 days. |

Two public skills from [ClickHouse/agent-skills](https://github.com/ClickHouse/agent-skills) (Apache-2.0) are used unmodified: `clickhouse-best-practices` (built into ClickHouse Agents) and `clickhouse-architecture-advisor`.

**To install:** download the zips from the [latest release](https://github.com/tkykenmt/clickhouse-poc-assistant/releases/latest) and follow [docs/setup.md](docs/setup.md).

## Repository layout

| Path | Contents |
|---|---|
| `queries/` | Sizing queries (01–08). The single source for every tool below. |
| `queries/optional/` | A query that includes sample query text. Not run by default. |
| `queries/advisor/` | Queries for the advisor (10–13). |
| `queries/progress/` | Queries for the daily note (20–28; 22 onwards pick up changes, 26–28 cover errors, background work and async insert flushes). |
| `queries/loadtest/` | Queries for one load-test window (30–31) and for comparing two runs (32). |
| `reference/poc-criteria.md` | PoC evaluation areas and how to measure each, with public sources only (ClickHouse docs and customer stories on clickhouse.com/blog). |
| `reference/checks-*.md` | Checks for a running service, one file per area (CPU and concurrency, reads and queries, inserts and parts, errors and background work, autoscaling and test design, the Cloud service). Each check names the columns it reads, the rule and its public source. The bundled design rules (`clickhouse-best-practices`) cover how to build tables and inserts; these cover what to look at once a workload runs. |
| `clickhouse-agents/skills/` | The skills (`SKILL.md` per skill). |
| `export/` | A kit for users who export the statistics themselves with `export.sh` (bash and curl) or the SQL console. |
| `scripts/build.sh` | Builds the skill zips and the export kit into `dist/`. |
| `scripts/fetch-public-skills.sh` | Downloads public skills unmodified at a pinned commit and zips them into `dist/`, with their license. |
| `scripts/bundle.sh` | Bundles all skill zips into `dist/poc-assistant-skills.zip`. |
| `scripts/test-queries.sh` | Runs every query on a throwaway local ClickHouse server as a least-privilege user. |
| `.github/workflows/build.yml` | CI and releases (see below). |
| `docs/` | Setup guide. |
| `LICENSE` | Apache-2.0. Every zip carries a copy; the public skill zip carries the ClickHouse/agent-skills license. |

## Build

GitHub Actions runs on every push and pull request: it checks the SQL syntax, runs every query on a throwaway server (`scripts/test-queries.sh`), runs ShellCheck, and builds the zips. Pushing a `v*` tag publishes them to a release. To build locally:

```bash
scripts/build.sh                # dist/ch-sizing-export.zip and dist/<skill>-skill.zip
scripts/fetch-public-skills.sh  # dist/clickhouse-architecture-advisor-skill.zip
scripts/bundle.sh               # dist/poc-assistant-skills.zip
scripts/test-queries.sh         # needs a clickhouse binary on PATH
```

Each skill zip contains its `SKILL.md`, the license, and exactly the files the skill names (`queries/...sql`, `reference/...md`). The agent cannot list folders, so every file a skill uses is named in its `SKILL.md`; the build fails if a named file is missing. Reference files that a shipped reference file names are shipped too.

## Query conventions

- Read system tables only. (Queries that the skills run on user tables with the user's approval are written in the conversation, not stored here; they carry `log_comment = 'poc-assistant'`, and every `query_log` query here leaves them out.)
- On ClickHouse Cloud, logs are per replica: read them with `clusterAllReplicas('default', merge('system', '^<table>'))`.
- From `query_log`, exclude this connection's own reads of system tables (queries by `currentUser()` whose `tables` are not empty and are only `system.*`, `information_schema.*`, `clusterAllReplicas` and `merge`; queries that failed before they started have no `tables` and are kept) and ClickHouse Cloud's own monitoring users (names ending in `-internal`). Without this, monitoring queries dominated the SELECT counts in testing. Other queries of the connected user are kept, so a workload that runs as the same database user is still counted; queries that the agent runs on user tables with `log_comment = 'poc-assistant'` are left out, and any other query on user tables over that connection is counted.
- Filter on `event_date` as well as `event_time` so only the needed partitions are read.
- Do not output user names; output counts. Output `normalized_query_hash` as a string (`toString`) so no digits are lost.
- Write the period as `30 /*days*/`, and a load-test window as `now() - INTERVAL 1 HOUR /*window_start*/` and `now() /*window_end*/`; tools replace these markers.
- Small tables stored only in compact parts report 0 compressed bytes until they are merged.
- The advisor, load-test and daily skills may write further read-only queries on system tables to confirm a finding, with the same filters, and show them as their own in the output. The sizing skill runs only the listed queries, so its numbers can be reproduced.

## Status (as of 2026-10-10)

- All queries pass on ClickHouse 26.7 and 26.8 as a least-privilege user (`scripts/test-queries.sh`), and all of them run without errors on a ClickHouse Cloud (26.6) test service.
- `poc-plan-builder` and `poc-sizing-stats` ran end to end on a test service. After the `reference/checks-*.md` files were added, `poc-schema-query-advisor`, `poc-daily-progress` and `poc-load-test-review` ran end to end again through ClickHouse Agents on a test service and used the new checks. `poc-load-test-review` ran end to end on ClickHouse Cloud (26.6) through ClickHouse Agents against a four-step load test on a test service (per-step split by `log_comment`, container CPU at the limit, CPU wait, rows read per part). One run stopped with a model-provider error after repeated documentation searches; the skill now tells the agent not to search again for the URLs it already lists.
- Added in v0.3.0 and so far tested only locally, not yet through ClickHouse Agents: `queries/advisor/13_service_objects.sql`, `queries/loadtest/32_compare_windows.sql`, the `poc-summary` skill, the plan's `## Results` section, and queries on user tables with the user's approval. Besides `scripts/test-queries.sh`, an agent followed the shipped skill files literally against a local server (read-only connections that reject and accept query-level settings); v0.3.1 fixes what those runs found.
- Added in v0.3.2 and tested only locally: checks taken from official troubleshooting and knowledge-base pages (what stops while the service is idle, `TIMEOUT_EXCEEDED`, empty or failed dictionaries, detached parts, the async insert flush wait, `TOO_MANY_PARTS` and load-balancer timeouts on long `INSERT ... SELECT`, TTL timing, sorting keys on an expression, memory held outside queries), with new rows in `13` and `27` and `has_ttl` in `10`. The export user now also gets `SHOW DICTIONARIES`.
- The daily note's change-only advice sometimes also reports a standing condition (for example small inserts) rather than only changes.
- Not used: ClickHouse Agents memory (manually created memories did not reach the agent in testing), scheduled chats (creating a schedule for an agent with the ClickHouse tool kept asking to reconnect the MCP server), and the Agent API (not available). Ask the agent for the daily note and the weekly review.
