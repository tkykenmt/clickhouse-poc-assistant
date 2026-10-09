# 導入の手順：スキルの導入とエージェントの作成

[English](setup.md)

[ClickHouse Agents](https://clickhouse.com/docs/products/cloud/features/ai-ml/agents) にエージェント「PoC アシスタント」を作る手順です。
ClickHouse Agents（ベータ）を使える ClickHouse Cloud の組織と、評価に使うサービスが必要です。

## 手順の一覧

1. サービスで Remote MCP を有効にする（[1](#1-サービスで-remote-mcp-を有効にする)）
2. スキルの zip をダウンロードする（[2](#2-スキルをダウンロードする)）
3. zip を 1 つずつスキルとしてアップロードする（[3](#3-スキルをアップロードする)）
4. エージェントを作り、指示文を貼る（[4](#4-エージェントを作る)）
5. エージェントと PoC の計画を作り、エージェントに添付する（[5](#5-poc-の計画を作って添付する)）
6. 統計、見直し、日次のまとめを頼む（[6](#6-使う)）

## 1. サービスで Remote MCP を有効にする

エージェントは、ClickHouse の Remote MCP を通してサービスにクエリを実行します。
Remote MCP はサービスごとに有効にします。

1. Cloud コンソールで対象のサービスを開きます。
2. **Connect** を押し、**Connect with** で **MCP** を選び、**Enable Model Context Protocol** をオンにします。

参考：https://clickhouse.com/docs/products/cloud/features/ai-ml/remote-mcp

## 2. スキルをダウンロードする

最新のリリースから 1 つずつダウンロードします。

| スキル | ダウンロード |
|---|---|
| `poc-plan-builder` | [poc-plan-builder-skill.zip](https://github.com/tkykenmt/clickhouse-poc-assistant/releases/latest/download/poc-plan-builder-skill.zip) |
| `poc-sizing-stats` | [poc-sizing-stats-skill.zip](https://github.com/tkykenmt/clickhouse-poc-assistant/releases/latest/download/poc-sizing-stats-skill.zip) |
| `poc-schema-query-advisor` | [poc-schema-query-advisor-skill.zip](https://github.com/tkykenmt/clickhouse-poc-assistant/releases/latest/download/poc-schema-query-advisor-skill.zip) |
| `poc-load-test-review` | [poc-load-test-review-skill.zip](https://github.com/tkykenmt/clickhouse-poc-assistant/releases/latest/download/poc-load-test-review-skill.zip) |
| `poc-daily-progress` | [poc-daily-progress-skill.zip](https://github.com/tkykenmt/clickhouse-poc-assistant/releases/latest/download/poc-daily-progress-skill.zip) |
| `clickhouse-architecture-advisor`（公開スキル、変更なし） | [clickhouse-architecture-advisor-skill.zip](https://github.com/tkykenmt/clickhouse-poc-assistant/releases/latest/download/clickhouse-architecture-advisor-skill.zip) |

全部まとめた [poc-assistant-skills.zip](https://github.com/tkykenmt/clickhouse-poc-assistant/releases/latest/download/poc-assistant-skills.zip) もあります（展開すると上の表の zip が出てきます）。GitHub CLI なら次の 1 行です。

```bash
gh release download -R tkykenmt/clickhouse-poc-assistant -p '*-skill.zip'
```

`clickhouse-best-practices` は ClickHouse Agents に組み込まれているので、ダウンロードは不要です。
リリースにある `ch-sizing-export.zip` は、ユーザーが自分でクエリを実行するための一式で、エージェントには使いません。
ソースから zip を作る場合は、[README の作り方](../README.ja.md#作り方)を見てください。

## 3. スキルをアップロードする

1. Cloud コンソールの左のメニューから **ClickHouse agents** を開きます。
2. ClickHouse Agents の左のバーで **スキル** を開きます。
3. zip ごとに、**スキルを作成**（＋）→ **スキルをアップロードする** → zip を選びます。1 回のアップロードで入るスキルは 1 つです。
4. 上の表のスキルがすべて一覧に並んだことを確かめます。

参考：https://clickhouse.com/docs/products/cloud/features/ai-ml/agents/builder/skills

## 4. エージェントを作る

**エージェントビルダー** を開き、**新しいエージェントを作成** を選んで、次の値を入れます。

| 項目 | 値 |
|---|---|
| 名前 | PoC アシスタント |
| 説明 | ClickHouse Cloud の PoC を手伝う。計画、サイジング用の統計、テーブル設計とクエリの見直し、日次の進捗（読み取りのみ） |
| モデル | プロバイダー **Claude**、モデル `claude-sonnet-5-5`（一覧にあるほかのモデルでも動くはずですが、検証したのはこのモデルです） |
| 指示文 | 下の英語の文 |
| ツール | **ツールを追加** → **ClickHouse**（MCP サーバー）と **アーティファクト** |
| スキル | **Selected** にして、`poc-*` のスキルすべて、`clickhouse-best-practices`、`clickhouse-architecture-advisor` を追加 |

指示文には、次の英語の文を貼ります。エージェントはユーザーの言葉で答えます。

```text
You are an assistant that helps run a ClickHouse Cloud PoC. Pick the skill for each request: poc-plan-builder to plan the PoC and its success criteria, poc-sizing-stats for sizing statistics, poc-schema-query-advisor to review table design and queries (judge with clickhouse-best-practices and clickhouse-architecture-advisor), poc-load-test-review to explain one load test (latency, CPU, reads, autoscaling), and poc-daily-progress for progress, the daily note and next actions. The PoC target and success criteria are in the PoC plan file (a file starting with poc-plan) in the file context. For every request, read system tables. Query the user's own tables only to confirm a finding, after showing the queries with their EXPLAIN ESTIMATE and getting the user's approval; return aggregates, not rows. Write numbers only from query results; do not guess. When you state how ClickHouse behaves, confirm it with documentation search and attach the URL. Do not recommend a service size, a tier or a price. Do not output user names or e-mail addresses. Present improvements as candidates to verify, not as decisions. Answer in the user's language.
```

<details>
<summary>指示文の日本語訳（参考。貼るのは上の英語の文）</summary>

あなたは ClickHouse Cloud の PoC を手伝うアシスタントです。依頼に応じてスキルを使い分けます。PoC の計画と成功基準づくりは poc-plan-builder、サイジング用の統計は poc-sizing-stats、テーブル設計とクエリの見直しは poc-schema-query-advisor（判断は clickhouse-best-practices と clickhouse-architecture-advisor に従う）、1 回の負荷試験の振り返り（レイテンシ、CPU、読み取り、オートスケール）は poc-load-test-review、進捗と日次のまとめとネクストアクションは poc-daily-progress です。PoC の対象と成功基準は、ファイルのコンテキストにある PoC 計画（poc-plan で始まるファイル）に書いてあります。どの依頼でも、system テーブルを読みます。ユーザーのテーブルにクエリを流すのは、見つけたことを確かめるときだけで、クエリと EXPLAIN ESTIMATE の見込みを示してユーザーの了承を得てからにします。返すのは集計で、行そのものは返しません。数字はクエリの結果だけから書き、推測しません。ClickHouse の振る舞いを述べるときは、ドキュメント検索で確かめて URL を付けます。サービスの規模、ティア、金額の推奨はしません。ユーザー名やメールアドレスは出しません。改善の案は、決定ではなく確かめる候補として出します。ユーザーの言葉で答えます。

</details>

**作成** を押します。あとで変えるときは **保存** を押し、「正常に更新されました」の表示が出るまで待ってください。表示を待たないと、変更が消えることがあります。

初めて ClickHouse のツールを使うときに、接続を求められます。求められない場合は、左のバーの **MCP設定** で **ClickHouse** を探し、**接続** を押します。エージェントから見えるのは、Cloud のユーザーがアクセスできる組織とサービスだけです。

クエリは、この接続自身による system テーブルの読み取りを除きますが、同じ DB ユーザーのほかのクエリは残します。PoC の負荷をエージェントや書き出しと同じ DB ユーザーで流しても、負荷は数えられます。エージェントがユーザーのテーブルに流すクエリには `log_comment = 'poc-assistant'` を付けるので、数えられません。接続が設定を変えられないときは数えられ、エージェントがそのことを書きます。

参考：https://clickhouse.com/docs/products/cloud/features/ai-ml/agents/quickstart 、https://clickhouse.com/docs/products/cloud/features/ai-ml/agents/builder/mcp-servers

## 5. PoC の計画を作って添付する

1. エージェントとのチャットで、たとえば「PoC の計画を作りたい。サービスは <名前>、期間は <開始> から <終了>。決めたいのは …」と頼みます。エージェントはデータ、クエリ、目標を聞き、出典つきで成功基準の案を出し、合格ラインを聞き返します。
2. エージェントが計画を `poc-plan-<名前>.md` として出力するので、ダウンロードします。
3. エージェントビルダーでエージェントを開き、**ファイルのコンテキスト** の **追加** からファイルをアップロードし、**保存** を押します。

計画には `## 対象` と `## 成功基準` の見出しが必要で、`## 経緯` は任意です（英語の `## Target`、`## Success criteria`、`## Log` でも読めます）。
エージェントを使える人は全員このファイルを読めるので、PoC ごとにエージェントを分けます。

## 6. 使う

| 頼み方 | スキル |
|---|---|
| 「直近 7 日のサイジング用の統計を出してください」 | `poc-sizing-stats` |
| 「PoC 計画のサービスのテーブル設計とクエリを、直近 7 日の記録で見直してください」 | `poc-schema-query-advisor` |
| 「今日の 10:00〜10:20（JST）の負荷試験を振り返ってください。Locust で利用者 10、25、50、100 人の段階です」 | `poc-load-test-review` |
| 「poc-daily-progress で今日の PoC のまとめを書いてください」 | `poc-daily-progress` |

日次のまとめは毎朝、総点検は週に 1 回を目安にします。

## 新しいリリースへの入れ替え

スキルはその場で差し替えられず、スキルを削除するとエージェントからも外れます。変わったスキルごとに、次の順で入れ替えます。

1. 新しい zip をダウンロードします。
2. **スキル** でそのスキルを開いて削除します。
3. 新しい zip をアップロードします。
4. エージェントビルダーでエージェントを開き、**スキル** にもう一度追加して **保存** を押します。「正常に更新されました」の表示を待ちます。

## 制約（2026-10-08 時点）

- **定期実行（Scheduled chats）**：機能はありますが、ClickHouse のツールを付けたエージェントで予定を作ると、再接続したあとも「Reconnect this MCP server before enabling the schedule.」が出続けます。変わるまでは、日次のまとめと週次の総点検はエージェントに頼んで実行します。
- **メモリ**：メモリの画面で手で作った項目は、検証では会話に渡りませんでした。そのため、計画はファイルのコンテキストで渡します。
- **Agent API**：使えないので、外からエージェントを呼べません。
- ClickHouse Agents はベータなので、画面や動きが変わることがあります。
