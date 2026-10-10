# ClickHouse Cloud サイジング用の統計の書き出し

[English](README.md)

ClickHouse Cloud のサービスから、構成と費用の見積もりに使う統計を CSV で書き出すためのクエリ集です。

読むのは system テーブルだけです。
あなたのテーブルの行は読みません。
クエリの文面は、既定では書き出しません。

## 書き出す内容

| ファイル | 内容 | 見積もりでの使いどころ |
|---|---|---|
| `01_service` | レプリカごとのバージョン、稼働時間、CPU とメモリの上限 | 現在の構成 |
| `02_tables` | テーブルごとの行数、圧縮前後の容量、パーツ数、パーティション数、データの時間の範囲（パーティションキーが時刻のとき）、並び替えキー | 保存量と圧縮率 |
| `03_columns` | 列ごとの型、圧縮方式、圧縮前後の容量（大きい順に 2,000 列まで） | 圧縮率の内訳 |
| `04_ingest_daily` | 日ごと、テーブルごとの投入の行数と容量 | 1 日の投入量 |
| `05_ingest_hourly` | 時間ごとの投入の行数と容量（全テーブルの合計） | 投入のピーク |
| `06_query_patterns` | クエリの型ごとの実行回数、応答時間（p50、p90、p99）、読んだ行数、メモリ、CPU 時間（上位 100 件） | クエリの重さ |
| `07_query_load_hourly` | 時間ごとの SELECT と INSERT の数、1 秒あたりの最大数、応答時間、CPU 時間 | クエリの頻度とピーク |
| `08_resources_hourly` | 時間ごと、レプリカごとの実行中のクエリとマージの最大数、メモリ、CPU 時間 | リソースの使い方 |
| `optional/09_query_patterns_with_text`（任意） | `06` に、型ごとのクエリの文面の例（先頭 300 文字）を 1 件ずつ加えたもの | クエリの中身の確認 |

クエリの型は `normalized_query_hash` で分けます。値だけが違うクエリは、同じ型にまとまります。
ClickHouse Cloud が監視のために実行するクエリ（名前が `-internal` で終わる DB ユーザーのもの）と、書き出し用の DB ユーザー自身による system テーブルの読み取りは除きます。
ユーザー名は書き出さず、型ごとのユーザーの数だけを書き出します。

`09` の文面には、WHERE 句の値などがそのまま入ります。
データの取り扱いの規定で問題がない場合に限り、`--with-query-text` を付けて書き出してください。

compact parts だけで保存されている小さなテーブルは、マージされるまで圧縮後の容量が 0 と出ます（圧縮率も出ません）。

## 期間

既定では直近 30 日を対象にします。
system テーブルの記録は最長 30 日程度で消えるため、それより前の分は書き出せません。
PoC の負荷がかかった期間を含むように、書き出す日を決めてください。

## 手順

### 1. 読み取り専用の DB ユーザーを作る

管理者の DB ユーザーで、SQL コンソールから `setup_user.sql` を実行します。
パスワードは書き換えてください。

```sql
CREATE USER IF NOT EXISTS sizing_reader IDENTIFIED BY '<パスワード>';
GRANT SHOW DATABASES, SHOW TABLES, SHOW COLUMNS, SHOW DICTIONARIES ON *.* TO sizing_reader;
GRANT SELECT ON system.* TO sizing_reader;
GRANT REMOTE ON *.* TO sizing_reader;
GRANT CREATE TEMPORARY TABLE ON *.* TO sizing_reader;
```

この DB ユーザーは書き出しにだけ使ってください。この DB ユーザー自身による system テーブルの読み取りは結果から除きますが、ほかのクエリは残します。

`SHOW` の権限が欠けると、エラーにならずにあなたのテーブルが結果から抜けます。
`02_tables.csv` に対象のテーブルが並んでいるかを確かめてください。

### 2. 書き出す

`bash` と `curl` がある環境（macOS、Linux）で実行します。
接続先は、Cloud コンソールの **Connect** に表示される HTTPS のエンドポイント（ポート 8443）です。

```bash
export CH_URL="https://<サービスのホスト名>:8443"
export CH_USER="sizing_reader"
read -rs CH_PASSWORD; export CH_PASSWORD   # パスワードを入力（画面には表示されない）
./export.sh                        # 直近 30 日
./export.sh 14                     # 直近 14 日
./export.sh --with-query-text      # 直近 30 日、文面の例も書き出す
```

`sizing_export_<日時>.tar.gz` ができます。
パスワードはコマンドラインではなく、標準入力で curl に渡します。
失敗したクエリは、エラーの内容を `<クエリ名>.error.txt` としてアーカイブに入れ、スクリプトは終了コード 1 で終わります。
中の CSV は表計算ソフトで開いて、内容を確かめてから共有してください。

SQL コンソールで 1 本ずつ実行し、結果の右上の **•••** から **Download as CSV** で保存しても、同じものが得られます。
期間を変えるときは、クエリの中の `30 /*days*/` の数字を書き換えます。

### 3. 後片付け

書き出しが終わったら、DB ユーザーを削除します。

```sql
DROP USER sizing_reader;
```

## 実行の影響

- クエリは system テーブルを読むので、サービスに負荷がかかります。利用の少ない時間帯に実行してください。
- 休止中のサービスに接続すると、サービスが起動します。
- `clusterAllReplicas` で全レプリカの記録を読みます。応答しないレプリカは飛ばします（`skip_unavailable_shards = 1`）。

## 参考

- ClickHouse Cloud での system テーブルの読み方：https://clickhouse.com/docs/products/cloud/features/monitoring/system-tables
- `system.query_log`：https://clickhouse.com/docs/reference/system-tables/query_log
- より詳しい診断（障害の調査向け）には、ClickHouse の公開ツール clickhouse-diagnostics もあります：https://github.com/ClickHouse/clickhouse-diagnostics
