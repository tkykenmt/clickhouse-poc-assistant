# clickhouse-poc-assistant

[English](README.md)

ClickHouse Cloud の PoC（概念実証）を手伝うツールをまとめたリポジトリです。
役割ごとにスキルを分け、[ClickHouse Agents](https://clickhouse.com/docs/products/cloud/features/ai-ml/agents) のエージェント「PoC アシスタント」が依頼に応じて使い分けます。
どのツールも **system テーブルだけ** を読み、ユーザーのテーブルの行は読みません。

| スキル | 役割 |
|---|---|
| `poc-plan-builder` | ユーザーにワークロードを聞き、成功基準の案を測り方と公開資料の出典つきで出し、PoC 計画を Markdown で書き出す。合格ラインはユーザーが決める |
| `poc-sizing-stats` | サイジング用の統計（保存量、圧縮率、投入の量とピーク、クエリの量、1 回あたりの重さ）を集め、要約と CSV にする |
| `poc-schema-query-advisor` | テーブル設計、クエリの型、投入の形を見て、改善の候補を最大 5 件、根拠のルールかドキュメントと確かめ方つきで出す |
| `poc-load-test-review` | 負荷試験の時間帯を見て、レイテンシの内訳（CPU、CPU の空き待ち、I/O）、レプリカの CPU が足りていたか、読んだ行数と返した行数の差、オートスケールが動いた・動かなかった理由を、根拠のドキュメントつきで書く |
| `poc-daily-progress` | 日次のまとめ。直近 24 時間の変化、成功基準ごとの状況、変化したテーブルとクエリへの助言（最大 3 件）、ネクストアクションを書く。エージェントに添付した PoC 計画を読む |

公開スキル [ClickHouse/agent-skills](https://github.com/ClickHouse/agent-skills)（Apache-2.0）の 2 つを、変更せずに使います。
`clickhouse-best-practices`（ClickHouse Agents に組み込み）と `clickhouse-architecture-advisor` です。

**導入：** [最新のリリース](https://github.com/tkykenmt/clickhouse-poc-assistant/releases/latest)から zip をダウンロードし、[docs/setup.ja.md](docs/setup.ja.md) の手順に従います。

## 構成

| 場所 | 中身 |
|---|---|
| `queries/` | サイジング用の SQL（01〜08）。ほかのツールはすべてここを正本にする |
| `queries/optional/` | クエリの文面の例を含む SQL。既定では使わない |
| `queries/advisor/` | アドバイザー用の SQL（10〜12） |
| `queries/progress/` | 日次のまとめ用の SQL（20〜28。22 以降は変化を拾い、26〜28 はエラー、バックグラウンドの処理、非同期 INSERT の書き出しを見る） |
| `queries/loadtest/` | 負荷試験の時間帯を見る SQL（30〜31） |
| `reference/poc-criteria.md` | PoC の評価の観点と測り方。出典は公開資料（ClickHouse のドキュメントと clickhouse.com/blog の事例）だけ |
| `reference/checks-*.md` | 動いているサービスを見る観点。分野ごとに 1 ファイル（CPU と同時実行、読み取りとクエリ、INSERT とパーツ、エラーとバックグラウンドの処理、オートスケールと試験の組み方、Cloud のサービス）。観点ごとに、読む列、判断の基準、公開の出典を書く。同梱の設計のルール（`clickhouse-best-practices`）はテーブルと INSERT の作り方を扱い、こちらはワークロードが動き出してから見るものを扱う |
| `clickhouse-agents/skills/` | スキル（スキルごとの `SKILL.md`） |
| `export/` | ユーザーが自分で統計を書き出すための一式（`export.sh`（bash と curl）か SQL コンソールで実行） |
| `scripts/build.sh` | スキルの zip と書き出しの一式を `dist/` に作る |
| `scripts/fetch-public-skills.sh` | 公開スキルを、コミットを固定して変更せずに取得し、ライセンスと一緒に zip にする |
| `scripts/bundle.sh` | スキルの zip をまとめて `dist/poc-assistant-skills.zip` にする |
| `scripts/test-queries.sh` | 使い捨てのローカルの ClickHouse サーバーで、最小権限の DB ユーザーとして全クエリを実行する |
| `.github/workflows/build.yml` | CI とリリース（下記） |
| `docs/` | 導入の手順 |
| `LICENSE` | Apache-2.0。どの zip にも写しを入れる。公開スキルの zip には ClickHouse/agent-skills のライセンスを入れる |

## 作り方

GitHub Actions が、push とプルリクエストのたびに次を実行します。SQL の構文の確認、使い捨てのサーバーでの全クエリの実行（`scripts/test-queries.sh`）、ShellCheck、zip の作成です。`v*` のタグを push すると、zip がリリースに載ります。手元で作る場合は次のとおりです。

```bash
scripts/build.sh                # dist/ch-sizing-export.zip と dist/<スキル名>-skill.zip
scripts/fetch-public-skills.sh  # dist/clickhouse-architecture-advisor-skill.zip
scripts/bundle.sh               # dist/poc-assistant-skills.zip
scripts/test-queries.sh         # PATH に clickhouse のバイナリが必要
```

スキルの zip には、`SKILL.md`、ライセンス、そこに名前が書かれたファイル（`queries/...sql`、`reference/...md`）だけが入ります。同梱した参照ファイルが名前を挙げた参照ファイルも入ります。
エージェントはフォルダーの中身を一覧できないので、スキルが使うファイルはすべて `SKILL.md` に書きます。
書かれたファイルが無いと、ビルドは失敗します。

## クエリの決まり

- 読むのは system テーブルだけです。
- ClickHouse Cloud ではログがレプリカごとにあるので、`clusterAllReplicas('default', merge('system', '^<table>'))` で読みます。
- `query_log` からは、この接続自身による system テーブルの読み取り（`currentUser()` のクエリのうち、`tables` が空でなく、`system.*`、`information_schema.*`、`clusterAllReplicas`、`merge` だけのもの。開始前に失敗したクエリは `tables` が空なので残す）と、ClickHouse Cloud の監視用の DB ユーザー（名前が `-internal` で終わるもの）を除きます。除かないと、検証では SELECT の件数の大半が監視のクエリでした。接続している DB ユーザーのほかのクエリは残すので、負荷を同じ DB ユーザーで流しても数えられます。エージェント自身がその接続でユーザーのテーブルに流したクエリも数えられます。
- 必要なパーティションだけを読むよう、`event_time` に加えて `event_date` でも絞ります。
- ユーザー名は出さず、数だけを出します。`normalized_query_hash` は桁が落ちないよう `toString` で文字列にします。
- 期間は `30 /*days*/`、負荷試験の時間帯は `now() - INTERVAL 1 HOUR /*window_start*/` と `now() /*window_end*/` と書きます。ツールがこれらの印を置き換えます。
- compact parts だけで保存されている小さなテーブルは、マージされるまで圧縮後の容量が 0 と出ます。

## 確認の状況（2026-10-09 時点）

- ClickHouse 26.7 と 26.8 で、最小権限の DB ユーザーとして全クエリが通ります（`scripts/test-queries.sh`）。ClickHouse Cloud（26.6）の検証用サービスでも、全クエリがエラーなく動きます。
- `poc-plan-builder` と `poc-sizing-stats` は、検証用のサービスで最後まで動きました。`reference/checks-*.md` を加えたあと、`poc-schema-query-advisor`、`poc-daily-progress`、`poc-load-test-review` を ClickHouse Agents 経由で検証用のサービスに対してもう一度動かし、新しい観点が使われることを確かめました。`poc-load-test-review` は、検証用のサービスに 4 段階の負荷をかけ、ClickHouse Agents 経由で ClickHouse Cloud（26.6）上で最後まで動きました（`log_comment` による段階ごとの集計、上限に達したコンテナの CPU、CPU 待ち、パーツごとの読み取り行数）。1 回は、ドキュメントの検索を繰り返したあとにモデル側のエラーで止まりました。スキルには、記載済みの URL を検索し直さないよう書き足しました。
- 日次のまとめの「変化だけの助言」は、変化ではなく続いている状態（小さい INSERT など）を拾うことがあります。
- 使っていないもの：ClickHouse Agents のメモリ（手で作ったメモリが検証では会話に渡らなかった）、定期実行（ClickHouse のツールを付けたエージェントで予定を作ると、MCP の再接続を求められ続けた）、Agent API（使えない）。日次のまとめと週次の総点検は、エージェントに頼んで実行します。
