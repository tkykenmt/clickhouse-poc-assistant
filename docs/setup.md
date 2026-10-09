# Setup: install the skills and create the agent

[日本語](setup.ja.md)

This guide sets up the "PoC assistant" agent in [ClickHouse Agents](https://clickhouse.com/docs/products/cloud/features/ai-ml/agents). You need a ClickHouse Cloud organization where ClickHouse Agents is available (it is in beta) and a service to evaluate.

## Quick start

1. Enable the Remote MCP server on the service ([step 1](#1-enable-the-remote-mcp-server-on-the-service)).
2. Download the six skill zips ([step 2](#2-download-the-skills)).
3. Upload each zip as a skill in ClickHouse Agents ([step 3](#3-upload-the-skills)).
4. Create the agent and paste the instructions ([step 4](#4-create-the-agent)).
5. Build the PoC plan with the agent and attach it ([step 5](#5-plan-the-poc-and-attach-the-plan)).
6. Ask for statistics, a review or the daily note ([step 6](#6-use-it)).

## 1. Enable the Remote MCP server on the service

The agent queries the service through the ClickHouse Remote MCP server, which must be enabled per service.

1. In the Cloud console, open the service.
2. Click **Connect**, choose **MCP** under **Connect with**, and turn on **Enable Model Context Protocol**.

Reference: https://clickhouse.com/docs/products/cloud/features/ai-ml/remote-mcp

## 2. Download the skills

Download from the latest release, one by one:

| Skill | Download |
|---|---|
| `poc-plan-builder` | [poc-plan-builder-skill.zip](https://github.com/tkykenmt/clickhouse-poc-assistant/releases/latest/download/poc-plan-builder-skill.zip) |
| `poc-sizing-stats` | [poc-sizing-stats-skill.zip](https://github.com/tkykenmt/clickhouse-poc-assistant/releases/latest/download/poc-sizing-stats-skill.zip) |
| `poc-schema-query-advisor` | [poc-schema-query-advisor-skill.zip](https://github.com/tkykenmt/clickhouse-poc-assistant/releases/latest/download/poc-schema-query-advisor-skill.zip) |
| `poc-load-test-review` | [poc-load-test-review-skill.zip](https://github.com/tkykenmt/clickhouse-poc-assistant/releases/latest/download/poc-load-test-review-skill.zip) |
| `poc-daily-progress` | [poc-daily-progress-skill.zip](https://github.com/tkykenmt/clickhouse-poc-assistant/releases/latest/download/poc-daily-progress-skill.zip) |
| `clickhouse-architecture-advisor` (public skill, unmodified) | [clickhouse-architecture-advisor-skill.zip](https://github.com/tkykenmt/clickhouse-poc-assistant/releases/latest/download/clickhouse-architecture-advisor-skill.zip) |

Or get all six at once as [poc-assistant-skills.zip](https://github.com/tkykenmt/clickhouse-poc-assistant/releases/latest/download/poc-assistant-skills.zip) (unzip it to get the six skill zips), or with the GitHub CLI:

```bash
gh release download -R tkykenmt/clickhouse-poc-assistant -p '*-skill.zip'
```

`clickhouse-best-practices` is built into ClickHouse Agents and needs no download. `ch-sizing-export.zip` in the release is the export kit for users who run the queries themselves; the agent does not need it. To build the zips from source instead, see [Build](../README.md#build).

## 3. Upload the skills

1. In the Cloud console, open **ClickHouse agents** in the left navigation.
2. Open **Skills** in the left bar of ClickHouse Agents.
3. For each skill zip: **Create skill** (+) → **Upload skill** → choose the zip. ClickHouse Agents takes one skill per upload.
4. Check that the six skills are listed.

Reference: https://clickhouse.com/docs/products/cloud/features/ai-ml/agents/builder/skills

## 4. Create the agent

Open **Agent Builder**, choose **Create new agent**, and set:

| Field | Value |
|---|---|
| Name | PoC assistant |
| Description | Helps run a ClickHouse Cloud PoC: plans, sizing statistics, table and query review, daily progress (read-only) |
| Model | provider **Claude**, model `claude-sonnet-5-5` (other listed models should work; this is the one tested) |
| Instructions | the text below |
| Tools | **Add tools** → **ClickHouse** (MCP server) and **Artifacts** |
| Skills | **Selected**, then add the five `poc-*` skills, `clickhouse-best-practices` and `clickhouse-architecture-advisor` |

Instructions:

```text
You are an assistant that helps run a ClickHouse Cloud PoC. Pick the skill for each request: poc-plan-builder to plan the PoC and its success criteria, poc-sizing-stats for sizing statistics, poc-schema-query-advisor to review table design and queries (judge with clickhouse-best-practices and clickhouse-architecture-advisor), poc-load-test-review to explain one load test (latency, CPU, reads, autoscaling), poc-load-test-review to explain one load test (latency, CPU, reads, autoscaling), and poc-daily-progress for progress, the daily note and next actions. The PoC target and success criteria are in the PoC plan file (a file starting with poc-plan) in the file context. For every request, read system tables only and never select rows from the user's own tables. Write numbers only from query results; do not guess. When you state how ClickHouse behaves, confirm it with documentation search and attach the URL. Do not recommend a service size, a tier or a price. Do not output user names or e-mail addresses. Present improvements as candidates to verify, not as decisions. Answer in the user's language.
```

Click **Create**. When you change the agent later, click **Save** and wait for the "updated" notification; otherwise the change can be lost.

The first time the agent calls the ClickHouse tool, it asks you to connect. If it does not, open **MCP settings** in the left bar, find **ClickHouse**, and click **Connect**. The agent sees only the organizations and services your Cloud user can access.

The queries leave out the connection's own reads of system tables but keep every other query of the same database user, so the PoC workload is counted even if it runs as the same user as the agent or an export.

References: https://clickhouse.com/docs/products/cloud/features/ai-ml/agents/quickstart , https://clickhouse.com/docs/products/cloud/features/ai-ml/agents/builder/mcp-servers

## 5. Plan the PoC and attach the plan

1. Start a chat with the agent and ask, for example: "I want to plan a PoC. The service is <name>, from <start> to <end>. We need to decide whether ..." The agent asks about data, queries and targets, proposes criteria with sources, and asks you for each pass threshold.
2. The agent outputs the plan as `poc-plan-<name>.md`. Download it.
3. In Agent Builder, open the agent, and under **File context** click **Add** and upload the file. Click **Save**.

The plan needs the sections `## Target` and `## Success criteria`, and optionally `## Log` (the Japanese headings `## 対象`, `## 成功基準` and `## 経緯` also work). Everyone who can use the agent can read this file, so create one agent per PoC.

## 6. Use it

| Request | Skill |
|---|---|
| "Show the sizing statistics for the last 7 days." | `poc-sizing-stats` |
| "Review the table design and queries of the PoC service using the last 7 days." | `poc-schema-query-advisor` |
| "Review the load test from 10:00 to 10:20 JST today. It used Locust with 10, 25, 50 and 100 users." | `poc-load-test-review` |
| "Write today's PoC note with poc-daily-progress." | `poc-daily-progress` |

Suggested rhythm: the daily note every morning and the full review once a week.

## Upgrading to a new release

Skills cannot be replaced in place, and deleting a skill removes it from the agent. For each skill that changed:

1. Download the new zip.
2. In **Skills**, open the skill and delete it.
3. Upload the new zip.
4. In Agent Builder, open the agent, add the skill again under **Skills**, and click **Save**. Wait for the "updated" notification.

## Limitations (as of 2026-10-08)

- **Scheduled chats**: the feature is available, but creating a schedule for an agent with the ClickHouse tool keeps showing "Reconnect this MCP server before enabling the schedule." even after reconnecting. Until this changes, ask the agent for the daily note and the weekly review.
- **Memory**: memories created by hand in the Memory panel did not reach the agent in testing, so the plan is passed as file context instead.
- **Agent API**: not available, so the agent cannot be called from outside.
- ClickHouse Agents is in beta; screens and behaviour may change.
