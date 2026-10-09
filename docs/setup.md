# Setup: install the skills and create the agent

[日本語](setup.ja.md)

This guide sets up the "PoC assistant" agent in ClickHouse Agents. You need a ClickHouse Cloud organization where ClickHouse Agents is available (it is in beta) and a service to evaluate.

## 1. Get the zips

Download the zips from the latest release: https://github.com/tkykenmt/clickhouse-poc-assistant/releases/latest

They are built by GitHub Actions on every tag. To build them yourself instead:

```bash
git clone https://github.com/tkykenmt/clickhouse-poc-assistant.git
cd clickhouse-poc-assistant
scripts/build.sh
scripts/fetch-public-skills.sh   # writes into dist/
```

A release (or `dist/`) holds:

| File | Use |
|---|---|
| `poc-plan-builder-skill.zip` | skill |
| `poc-sizing-stats-skill.zip` | skill |
| `poc-schema-query-advisor-skill.zip` | skill |
| `poc-daily-progress-skill.zip` | skill |
| `clickhouse-architecture-advisor-skill.zip` | public skill, unmodified |
| `ch-sizing-export.zip` | export kit for users who run the queries themselves (not needed for the agent) |

`clickhouse-best-practices` is built into ClickHouse Agents, so it is not in `dist/`.

## 2. Enable the Remote MCP server on the service

The agent queries the service through the ClickHouse Remote MCP server, which must be enabled per service.

1. In the Cloud console, open the service.
2. Click **Connect**, choose **MCP** under **Connect with**, and turn on **Enable Model Context Protocol**.

Reference: https://clickhouse.com/docs/products/cloud/features/ai-ml/remote-mcp

## 3. Upload the skills

1. In the Cloud console, open **ClickHouse agents** in the left navigation.
2. Open **Skills** in the left bar of ClickHouse Agents.
3. For each skill zip from step 1 (all but `ch-sizing-export.zip`): **Create skill** (the + button) → **Upload skill** → choose the zip.
4. Check that all five skills are listed and that each shows its `queries` or `reference` folder.

Reference: https://clickhouse.com/docs/products/cloud/features/ai-ml/agents/builder/skills

## 4. Create the agent

Open **Agent Builder**, choose **Create new agent**, and set:

| Field | Value |
|---|---|
| Name | PoC assistant |
| Description | Helps run a ClickHouse Cloud PoC: plans, sizing statistics, table and query review, daily progress (read-only) |
| Model | provider **Claude**, model `claude-sonnet-5-5` (any model listed for your organization works; this is the one tested) |
| Instructions | the text below |
| Tools | **Add tools** → **ClickHouse** (MCP server) and **Artifacts** |
| Skills | **Selected**, then add the four `poc-*` skills, `clickhouse-best-practices` and `clickhouse-architecture-advisor` |

Instructions:

```text
You are an assistant that helps run a ClickHouse Cloud PoC. Pick the skill for each request: poc-plan-builder to plan the PoC and its success criteria, poc-sizing-stats for sizing statistics, poc-schema-query-advisor to review table design and queries (judge with clickhouse-best-practices and clickhouse-architecture-advisor), and poc-daily-progress for progress, the daily note and next actions. The PoC target and success criteria are in the PoC plan file (a file starting with poc-plan) in the file context. For every request, read system tables only and never select rows from the user's own tables. Write numbers only from query results; do not guess. When you state how ClickHouse behaves, confirm it with documentation search and attach the URL. Do not recommend a service size, a tier or a price. Do not output user names or e-mail addresses. Present improvements as candidates to verify, not as decisions. Answer in the user's language.
```

Click **Create**. When you change the agent later, click **Save** and wait for the "updated" notification; changes are lost otherwise.

The first time the agent calls the ClickHouse tool, it asks you to connect. If it does not, open **MCP settings** in the left bar, find **ClickHouse**, and click **Connect**. Access is limited to the organizations and services your Cloud user can reach.

References: https://clickhouse.com/docs/products/cloud/features/ai-ml/agents/quickstart , https://clickhouse.com/docs/products/cloud/features/ai-ml/agents/builder/mcp-servers

## 5. Plan the PoC and attach the plan

1. Start a chat with the agent and ask, for example: "I want to plan a PoC. The service is <name>, from <start> to <end>. We need to decide whether ..." The agent asks about data, queries and targets, proposes criteria with sources, and asks you for each pass line.
2. When the plan is written, save it as `poc-plan-<name>.md`.
3. In Agent Builder, open the agent, and under **File context** click **Add** and upload the file.

The plan needs these sections, in English or Japanese: `## Target` (`## 対象`), `## Success criteria` (`## 成功基準`), and optionally `## Log` (`## 経緯`). Everyone who can use the agent can read this file, so create one agent per PoC.

## 6. Use it

| Request | Skill |
|---|---|
| "Show the sizing statistics for the last 7 days." | `poc-sizing-stats` |
| "Review the table design and queries of the PoC service using the last 7 days." | `poc-schema-query-advisor` |
| "Write today's PoC note with poc-daily-progress." | `poc-daily-progress` |

Suggested rhythm: the daily note every morning and the full review once a week.

## Limitations (as of 2026-10-08)

- **Scheduled chats**: the feature is available, but creating a schedule for an agent with the ClickHouse tool keeps showing "Reconnect this MCP server before enabling the schedule." even after reconnecting. Until this changes, run the daily note and the weekly review by asking the agent.
- **Memory**: memories created by hand in the Memory panel did not reach the agent in testing, so the plan is passed as file context instead.
- **Agent API**: not available, so the agent cannot be called from outside.
- **Updating a skill**: there is no in-place replacement of a skill's files. Delete the skill, upload the new zip, then add it to the agent again and save; deleting removes it from the agent.
- ClickHouse Agents is in beta; screens and behaviour may change.
