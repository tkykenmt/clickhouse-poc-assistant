# 導入の手順：スキルの導入とエージェントの作成

[English](setup.md)

ClickHouse Agents にエージェント「PoC アシスタント」を作る手順です。
ClickHouse Agents（ベータ）を使える ClickHouse Cloud の組織と、評価に使うサービスが要ります。

## 1. zip を手に入れる

最新のリリースから zip を落とします：https://github.com/tkykenmt/clickhouse-poc-assistant/releases/latest

zip は、タグを打つたびに GitHub Actions が作ります。自分で作る場合は次のとおりです。

```bash
git clone https://github.com/tkykenmt/clickhouse-poc-assistant.git
cd clickhouse-poc-assistant
scripts/build.sh
scripts/fetch-public-skills.sh   # dist/ に書き出す
```

リリース（または `dist/`）には次のファイルがあります。

| ファイル | 用途 |
|---|---|
| `poc-plan-builder-skill.zip` | スキル |
| `poc-sizing-stats-skill.zip` | スキル |
| `poc-schema-query-advisor-skill.zip` | スキル |
| `poc-daily-progress-skill.zip` | スキル |
| `clickhouse-architecture-advisor-skill.zip` | 公開スキル（書き換えなし） |
| `ch-sizing-export.zip` | 利用者が自分でクエリを流すための一式（エージェントには不要） |

`clickhouse-best-practices` は ClickHouse Agents に組み込まれているので、`dist/` にはありません。

## 2. サービスで Remote MCP を有効にする

エージェントは ClickHouse の Remote MCP を通してサービスに問い合わせます。
Remote MCP はサービスごとに有効にします。

1. Cloud コンソールで対象のサービスを開きます。
2. **Connect** を押し、**Connect with** で **MCP** を選び、**Enable Model Context Protocol** をオンにします。

参考：https://clickhouse.com/docs/products/cloud/features/ai-ml/remote-mcp

## 3. スキルを上げる

1. Cloud コンソールの左のメニューから **ClickHouse agents** を開きます。
2. ClickHouse Agents の左のバーで **スキル** を開きます。
3. 手順 1 の zip ごとに（`ch-sizing-export.zip` を除く）、**スキルを作成**（＋）→ **スキルをアップロードする** → zip を選びます。
4. 5 つのスキルが並び、それぞれに `queries` か `reference` のフォルダーが付いていることを確かめます。

参考：https://clickhouse.com/docs/products/cloud/features/ai-ml/agents/builder/skills

## 4. エージェントを作る

**エージェントビルダー** を開き、**新しいエージェントを作成** を選んで、次の値を入れます。

| 項目 | 値 |
|---|---|
| 名前 | PoC アシスタント |
| 説明 | ClickHouse Cloud の PoC を手伝う。計画、サイジング用の統計、テーブル設計とクエリの見直し、日次の進捗（読み取りのみ） |
| モデル | プロバイダー **Claude**、モデル `claude-sonnet-5-5`（組織で選べるモデルなら動くはずですが、試したのはこのモデルです） |
| 指示文 | 下の文 |
| ツール | **ツールを追加** → **ClickHouse**（MCP サーバー）と **アーティファクト** |
| スキル | **Selected** にして、`poc-*` の 4 つ、`clickhouse-best-practices`、`clickhouse-architecture-advisor` を追加 |

指示文には次の英語の文を入れます。エージェントは利用者の言葉で答えます。

```text
You are an assistant that helps run a ClickHouse Cloud PoC. Pick the skill for each request: poc-plan-builder to plan the PoC and its success criteria, poc-sizing-stats for sizing statistics, poc-schema-query-advisor to review table design and queries (judge with clickhouse-best-practices and clickhouse-architecture-advisor), and poc-daily-progress for progress, the daily note and next actions. The PoC target and success criteria are in the PoC plan file (a file starting with poc-plan) in the file context. For every request, read system tables only and never select rows from the user's own tables. Write numbers only from query results; do not guess. When you state how ClickHouse behaves, confirm it with documentation search and attach the URL. Do not recommend a service size, a tier or a price. Do not output user names or e-mail addresses. Present improvements as candidates to verify, not as decisions. Answer in the user's language.
```

日本語の訳：

```text
あなたは ClickHouse Cloud の PoC を手伝うアシスタントです。依頼に応じてスキルを使い分けます。PoC の計画と成功基準づくりは poc-plan-builder、サイジング用の統計は poc-sizing-stats、テーブル設計とクエリの見直しは poc-schema-query-advisor（判断は clickhouse-best-practices と clickhouse-architecture-advisor に従う）、進捗と日次のまとめとネクストアクションは poc-daily-progress です。PoC の対象と成功基準は、ファイルのコンテキストにある PoC 計画（poc-plan で始まるファイル）に書いてあります。どの依頼でも、読むのは system テーブルだけで、利用者のテーブルの行は読みません。数字は問い合わせの結果だけから書き、推測しません。ClickHouse の振る舞いを述べるときは、ドキュメント検索で確かめて URL を付けます。構成、ティア、金額の推奨はしません。利用者名やメールアドレスは出しません。改善の案は、決定ではなく確かめる候補として出します。利用者の言葉で答えます。
```

**作成** を押します。あとで変えるときは **保存** を押し、「正常に更新されました」の表示が出るまで待ってください。表示を待たないと、変更が消えることがあります。

初めて ClickHouse のツールを使うときに、接続を求められます。求められない場合は、左のバーの **MCP設定** で **ClickHouse** を探し、**接続** を押します。見えるのは、Cloud の利用者がアクセスできる組織とサービスだけです。

参考：https://clickhouse.com/docs/products/cloud/features/ai-ml/agents/quickstart 、https://clickhouse.com/docs/products/cloud/features/ai-ml/agents/builder/mcp-servers

## 5. PoC の計画を作って付ける

1. エージェントとのチャットで、たとえば「PoC の計画を作りたい。サービスは <名前>、期間は <開始> から <終了>。決めたいのは …」と頼みます。エージェントはデータ、問い合わせ、目標を聞き、出典つきで成功基準の案を出し、合格ラインを聞き返します。
2. 計画ができたら `poc-plan-<名前>.md` として保存します。
3. エージェントビルダーでエージェントを開き、**ファイルのコンテキスト** の **追加** からファイルを上げます。

計画には次の見出しが要ります（日本語か英語）。`## 対象`（`## Target`）、`## 成功基準`（`## Success criteria`）、任意で `## 経緯`（`## Log`）です。
エージェントを使える人は全員このファイルを読めるので、PoC ごとにエージェントを分けます。

## 6. 使う

| 頼み方 | スキル |
|---|---|
| 「直近 7 日のサイジング用の統計を出してください」 | `poc-sizing-stats` |
| 「PoC 計画のサービスのテーブル設計とクエリを、直近 7 日の記録で見直してください」 | `poc-schema-query-advisor` |
| 「poc-daily-progress で今日の PoC のまとめを書いてください」 | `poc-daily-progress` |

日次のまとめは毎朝、総点検は週に 1 回を目安にします。

## 制約（2026-10-08 時点）

- **定期実行（Scheduled chats）**：機能はありますが、ClickHouse のツールを付けたエージェントで予定を作ると、再接続したあとも「Reconnect this MCP server before enabling the schedule.」が出続けます。変わるまでは、日次のまとめと週次の総点検はエージェントに頼んで流します。
- **メモリ**：メモリの画面で手で作った項目は、試験では会話に渡りませんでした。そのため、計画はファイルのコンテキストで渡します。
- **Agent API**：使えないので、外からエージェントを呼べません。
- **スキルの更新**：スキルのファイルをその場で差し替える方法はありません。スキルを消して新しい zip を上げ直し、エージェントに付け直して保存します。スキルを消すとエージェントから外れます。
- ClickHouse Agents はベータなので、画面や動きが変わることがあります。
