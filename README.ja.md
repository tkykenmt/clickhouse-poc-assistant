# clickhouse-poc-assistant

[English](README.md)

ClickHouse Cloud の PoC（概念実証）を手伝う道具をまとめたリポジトリです。
役割ごとにスキルを分け、[ClickHouse Agents](https://clickhouse.com/docs/products/cloud/features/ai-ml/agents) のエージェント「PoC アシスタント」が依頼に応じて使い分けます。
どの道具も **system テーブルだけ** を読み、利用者のテーブルの行は読みません。

| スキル | 役割 |
|---|---|
| `poc-plan-builder` | 利用者にワークロードを聞き、成功基準の案を測り方と公開資料の出典つきで出し、PoC 計画を Markdown で書き出す。合格ラインは利用者が決める |
| `poc-sizing-stats` | サイジング用の統計（保存量、圧縮率、投入の量とピーク、問い合わせの量、1 回あたりの重さ）を集め、要約と CSV にする |
| `poc-schema-query-advisor` | テーブル設計、問い合わせの型、投入の形を見て、改善の候補を最大 5 件、根拠のルールかドキュメントと確かめ方つきで出す |
| `poc-daily-progress` | 日次のまとめ。直近 24 時間の変化、成功基準ごとの状況、変化したテーブルと問い合わせへの助言（最大 3 件）、次の手を書く。エージェントに付けた PoC 計画を読む |

公開スキル [ClickHouse/agent-skills](https://github.com/ClickHouse/agent-skills)（Apache-2.0）の 2 つを、書き換えずに使います。
`clickhouse-best-practices`（ClickHouse Agents に組み込み）と `clickhouse-architecture-advisor` です。

スキルの導入とエージェントの作り方は [docs/setup.ja.md](docs/setup.ja.md) にあります。

## 構成

| 場所 | 中身 |
|---|---|
| `queries/` | サイジング用の SQL（01〜08）。ほかの道具はすべてここを正本にする |
| `queries/optional/` | 問い合わせの文面の例を含む SQL。既定では使わない |
| `queries/advisor/` | アドバイザー用の SQL（10〜12） |
| `queries/progress/` | 日次のまとめ用の SQL（20〜25。22 以降は変化を拾う） |
| `reference/poc-criteria.md` | PoC の評価の観点と測り方。出典は公開資料（ClickHouse のドキュメントと clickhouse.com/blog の事例）だけ |
| `clickhouse-agents/skills/` | スキル（スキルごとの `SKILL.md`） |
| `export/` | 利用者が自分で統計を書き出すための一式（`export.sh`（bash と curl）か SQL コンソールで実行） |
| `scripts/build.sh` | 配布用の zip を `dist/` に作る |
| `scripts/fetch-public-skills.sh` | 公開スキルを、コミットを固定して書き換えずに取得し、zip にする |
| `docs/` | 導入の手順 |
| `LICENSE` | Apache-2.0。公開スキルの zip には、ClickHouse/agent-skills の Apache-2.0 のライセンスを同梱する |

## 作り方

GitHub Actions（`.github/workflows/build.yml`）が、push のたびに SQL の構文を確かめて zip を作り、`v*` のタグを打つとリリースに載せます。手元で作る場合は次のとおりです。

```bash
scripts/build.sh                # dist/ch-sizing-export.zip と dist/<スキル名>-skill.zip
scripts/fetch-public-skills.sh  # dist/clickhouse-architecture-advisor-skill.zip
```

スキルの zip には、`SKILL.md` と、そこに名前が書かれたファイル（`queries/...sql`、`reference/...md`）だけが入ります。
エージェントはフォルダーの中身を一覧できないので、スキルが使うファイルはすべて `SKILL.md` に書きます。
書かれたファイルが無いと、ビルドは失敗します。

## クエリの決まり

- 読むのは system テーブルだけです。
- ClickHouse Cloud ではログがレプリカごとにあるので、`clusterAllReplicas('default', merge('system', '^<table>'))` で読みます。
- `query_log` からは、書き出しを実行している利用者（`currentUser()`）と、ClickHouse Cloud の監視用の利用者（名前が `-internal` で終わるもの）を除きます。除かないと、試験では SELECT の件数の大半が監視の問い合わせでした。
- 利用者名は出さず、数だけを出します。`normalized_query_hash` は桁が落ちないよう `toString` で文字列にします。
- 期間は `30 /*days*/` と書きます。道具がこの印を置き換えます。

## 確認の状況（2026-10-08 時点）

- ClickHouse 26.7 で、最小権限の利用者として全クエリが通ります。ClickHouse Cloud（26.6）では、ClickHouse Agents 経由で 01〜08、アドバイザー用、日次のまとめ用のクエリが通ります。`queries/optional/` は構文の確認までです。
- 4 つのスキルは、検証用のサービスで最後まで動きました。
- 日次のまとめの「変化だけの助言」は、変化ではなく続いている状態（小さい INSERT など）を拾うことがあります。
- 使っていないもの：ClickHouse Agents のメモリ（手で作ったメモリが試験で会話に渡らなかった）、定期実行（ClickHouse のツールを付けたエージェントで予定を作ると、MCP の再接続を求められ続けた）、Agent API（使えない）。日次のまとめと週次の総点検は、エージェントに頼んで流します。
