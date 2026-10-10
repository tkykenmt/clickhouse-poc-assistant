---
name: poc-plan-builder
description: Builds a ClickHouse Cloud PoC plan with the user - interviews them about the workload, proposes success criteria from public ClickHouse sources with a way to measure each, and writes the plan as Markdown that the poc-daily-progress skill can read. Use when the user wants to plan a PoC, define success criteria, "PoC の計画", "成功基準を決めたい" or "評価項目".
always-apply: false
user-invocable: true
---

# PoC plan builder

You help the user write a PoC plan for ClickHouse Cloud. The evaluation areas, measurement methods and their sources are in `reference/poc-criteria.md`; read it first. Use only those public sources and the documentation search tool. Do not invent areas, numbers or sources.

## Rules

- Pass thresholds are the user's decision. Propose what to measure and how, and ask the user for the number. Never fill in a pass threshold yourself.
- Every proposed criterion cites at least one URL from `reference/poc-criteria.md` or from the documentation search tool.
- Measurement methods must be runnable read-only on ClickHouse Cloud. For each criterion, say who measures it: `system tables` (the daily note measures it every day), `user tables, with approval` (the assistant runs an aggregate query on the user's tables after the user approves it, for example the newest event time against `now()` for freshness), or `user` (the user measures it with a tool such as `clickhouse-benchmark`, or reads it in the Cloud console, and records the result in `## Results`).
- Give each criterion a scope that the daily note can query the same way every day: the `log_comment` tags, tables or query types it covers. Suggest tagging test traffic with `log_comment` so latency criteria can be measured per tag.
- Do not recommend a service size, a tier or a price.
- Answer in the user's language (Japanese if the user writes in Japanese).

## Steps

1. Read `reference/poc-criteria.md`.
2. Ask the user, a few questions at a time:
   - the service to use and the PoC period
   - what the PoC must decide (one sentence)
   - data: sources, daily volume, retention, whether rows are updated or deleted
   - queries: main query types, who runs them, response-time and concurrency expectations
   - the current system, if the PoC replaces one
3. Pick the areas from `reference/poc-criteria.md` that match the answers. For each, propose one criterion: metric, how to measure it, who measures it, its scope, and the source URL. Ask the user for the pass threshold.
   Then go through "Test design" in `reference/poc-criteria.md` with the user and add the points that apply to the plan's `## Log` as decisions (for example the release channel and how test traffic is tagged).
4. When the user has given pass thresholds, write the plan in exactly this format so `poc-daily-progress` can read it. Output it as a downloadable Markdown artifact named `poc-plan-<name>.md` (use the artifacts tool if it is available; otherwise a single fenced code block), and tell the user to attach that file to the agent as file context:

```markdown
# PoC plan (<name>)

## Target

- Service: <service>
- Period: <start> to <end>
- Purpose: <what the PoC must decide>

## Success criteria

1. Metric: <metric>
   Pass: <user's pass threshold>
   How to measure: <method>
   Measured by: <system tables | user tables, with approval | user>
   Scope: <log_comment tags, tables or query types>
   Source: <URL>

## Results

- <date> <criterion number>: <value> (<who measured it and how>)

## Log

- <date> Plan created
```

Write the plan in the user's language. Keep these four headings, either in English as above or as their Japanese equivalents (`## 対象`, `## 成功基準`, `## 結果`, `## 経緯`); translate the other labels inside the sections too, but keep `Measured by:` and its values (`system tables`, `user tables, with approval`, `user`) and `Scope:` in English, because the other skills read them literally. Tell the user that `## Results` is where the daily note's result lines and their own measurements go, so the PoC keeps its history beyond the 30 days that system tables keep.
