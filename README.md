# clickhouse-poc-assistant

[日本語](README.ja.md)

Tools that help run a ClickHouse Cloud proof of concept (PoC). The work is split into skills, and one agent in [ClickHouse Agents](https://clickhouse.com/docs/products/cloud/features/ai-ml/agents) ("PoC assistant") picks the right skill for each request. Everything reads **system tables only** and never selects rows from the user's own tables.

| Skill | What it does |
|---|---|
| `poc-plan-builder` | Interviews the user about the workload, proposes success criteria with a measurement method and a public source for each, and writes the PoC plan as Markdown. Pass lines are left to the user. |
| `poc-sizing-stats` | Collects sizing statistics (storage, compression, ingest volume and peaks, query load, per-query cost) and writes a summary plus CSV-ready tables. |
| `poc-schema-query-advisor` | Reviews table design, query patterns and insert shape, and proposes up to five improvement candidates with the rule or documentation page behind each and a way to verify it. |
| `poc-daily-progress` | Daily note: what changed in the last 24 hours, where each success criterion stands, advice limited to tables and queries that changed (at most three items), and next actions. Reads the PoC plan attached to the agent. |

Two public skills from [ClickHouse/agent-skills](https://github.com/ClickHouse/agent-skills) (Apache-2.0) are used unmodified: `clickhouse-best-practices` (built into ClickHouse Agents) and `clickhouse-architecture-advisor`.

To install the skills and create the agent, see [docs/setup.md](docs/setup.md).

## Repository layout

| Path | Contents |
|---|---|
| `queries/` | Sizing queries (01–08). The single source for every tool below. |
| `queries/optional/` | A query that includes sample query text. Not run by default. |
| `queries/advisor/` | Queries for the advisor (10–12). |
| `queries/progress/` | Queries for the daily note (20–25; 22 onwards pick up changes). |
| `reference/poc-criteria.md` | PoC evaluation areas and how to measure each, with public sources only (ClickHouse docs and customer stories on clickhouse.com/blog). |
| `clickhouse-agents/skills/` | The skills (`SKILL.md` per skill). |
| `export/` | A kit for users who export the statistics themselves with `export.sh` (bash and curl) or the SQL console. |
| `scripts/build.sh` | Builds the zips into `dist/`. |
| `scripts/fetch-public-skills.sh` | Downloads public skills unmodified at a pinned commit and zips them into `dist/`. |
| `docs/` | Setup guide. |
| `LICENSE` | Apache-2.0. The public skill zip carries its own Apache-2.0 license from ClickHouse/agent-skills. |

## Build

GitHub Actions (`.github/workflows/build.yml`) checks the SQL syntax and builds the zips on every push, and publishes them to a release when a `v*` tag is pushed. To build locally:

```bash
scripts/build.sh                # dist/ch-sizing-export.zip and dist/<skill>-skill.zip
scripts/fetch-public-skills.sh  # dist/clickhouse-architecture-advisor-skill.zip
```

Each skill zip contains its `SKILL.md` and exactly the files it names (`queries/...sql`, `reference/...md`). The agent cannot list folders, so every file a skill uses is named in its `SKILL.md`; the build fails if a named file is missing.

## Query conventions

- Read system tables only.
- On ClickHouse Cloud, logs are per replica: read them with `clusterAllReplicas('default', merge('system', '^<table>'))`.
- From `query_log`, exclude the exporting user (`currentUser()`) and ClickHouse Cloud's own monitoring users (names ending in `-internal`). Without this, monitoring queries dominated the SELECT counts in testing.
- Do not output user names; output counts. Output `normalized_query_hash` as a string (`toString`) so no digits are lost.
- Write the period as `30 /*days*/`; tools replace this marker.

## Status (as of 2026-10-08)

- All queries pass on ClickHouse 26.7 as a least-privilege user. Queries 01–08 and the advisor and daily queries pass on ClickHouse Cloud (26.6) through ClickHouse Agents. `queries/optional/` is syntax-checked only.
- All four skills ran end to end on a test service.
- The daily note's change-only advice sometimes also reports a standing condition (for example small inserts) rather than only changes.
- Not used: ClickHouse Agents memory (manually created memories did not reach the agent in testing), scheduled chats (creating a schedule for an agent with the ClickHouse tool kept asking to reconnect the MCP server), and the Agent API (not available). Run the daily note and weekly review by asking the agent.
