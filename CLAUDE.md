# CLAUDE.md — 冒険者ギルドRPG（Roblox）開発ルール

このファイルはAI（Claude Code等）が作業開始時に必ず読む。ここに書かれたルールは、個々の指示より優先する。

## 0. 最初に読むもの（この順番）

1. `docs/system/00_index.md` — システム仕様書の目次と読み方
2. `docs/decisions/INDEX.md` — 決定ID一覧（仕様の根拠）
3. 今回のフェイズの該当章（`docs/system/12_workflow.md` の「フェイズ別の参照先」）

## 1. 仕様の正（優先順位）

1. Notion「決定ログ」（`docs/decisions/INDEX.md` はそのスナップショット）
2. Notion「ゲーム仕様書」（各章）
3. 本リポジトリの `docs/system/`（システム仕様書）
4. Notion「企画概要書」

食い違いを見つけたら**実装せずに報告**する。自分で解釈して埋めない。

## 2. 絶対ルール（事故防止）

- **仕様にないものは作らない。** 必要だと思ったら、実装せずに「要確認（Q）」として報告する。
- **今回のフェイズの作業範囲外のファイルを変更しない。** 範囲は `docs/system/12_workflow.md` に従う。
- **数値をコードに直接書かない。** ゲームの数値・確率・コンテンツはすべて `src/data/` のマスターデータに置く（`docs/system/04_master_data.md`）。
- **`src/core/` から Roblox API・`os.time`・`math.random`・`Random` を使わない。** 時刻は `ctx.now`、乱数は `Rng` を引数で受け取る（`docs/system/08_rng_time.md`）。
- **計算式は `docs/system/06_formulas.md` のとおりに実装する。** 式を変える場合は先に仕様を変える。
- **用語は `docs/system/13_glossary.md` に従う。** 「前衛／後衛」「戦闘力」「パーティ最大HP」「編成ボーナス」「ダンジョン相性」「鍵付き宝箱」「見た目図鑑」は廃止された概念なので使わない。
- **マルチプレイ・オークションは実装しない**（D-065）。ただしデータ設計で将来の所有権移転を妨げない。他プレイヤーのパーティの表示（馬車・タップで読み取り専用の詳細）は M8 で作る（D-151）。協力・トレード・チャットなど、プレイヤー同士のやりとりは作らない。
- 既存のテストを消したり弱めたりしてテストを通さない。

## 3. コーディング規約

- 言語：Luau（`--!strict` を全ファイル先頭に付ける）。
- require は**文字列**で書き、変換せずに Roblox でもそのまま動かす（D-102、`docs/system/11_roblox_integration.md`）。
  - `src/core`・`src/data`・`tools`・`tests`（Lune でも動くコード）は `./`・`../`・`@self` だけを使う（例：`require("./Rng")`、フォルダの入口 `init.luau` から子は `require("@self/Constants")`）。
  - `src/server`・`src/client` から core・data を呼ぶときは `require("@game/ReplicatedStorage/Core/Game")` のように書く（Lune では動かないので、Lune でテストしたい処理は `src/core` に置く）。
- 命名：モジュールとファイルは PascalCase、関数・変数は camelCase、マスターデータのIDは snake_case（例：`job_warrior`）。
- 1モジュール1責務。`src/core/` のモジュールは状態を持たない（関数の集合）。
- フォーマットは StyLua、静的解析は selene。コミット前に `lune run tools/check` を通す。

## 4. テスト

- 仕様の各項目にテストを書き、テスト名に決定IDを含める（例：`"D-005 戦闘不能者を除いて被弾率を按分する"`）。
- 乱数を使う処理は固定シードでテストする。
- 実行：`lune run tools/test`（`docs/system/10_testing.md`）。

## 5. 作業の終わりに報告すること

- 実装した決定IDの一覧
- 追加・変更したファイル
- テスト結果
- 見つけた仕様の穴・食い違い（Q候補）

## 6. コミット

- 1コミット1目的。メッセージは日本語可。先頭に種別を付ける：`feat:` `fix:` `test:` `docs:` `data:`（マスターデータ変更）`refactor:` `chore:`。
- マスターデータの数値変更は `data:` で、変更理由（シミュレーション結果など）を本文に書く。
- コミット前に `git diff --cached --stat` で、入れるつもりのファイルだけが入っているか確かめる（削除や `.mcp.json` を混ぜない）。

## 7. 画面（UI）を作るとき（M8 以降）

- すべての画面はデザインシステム「Guild UI」（D-150）に従う。1画面ずつ決め方を変えない。中身はゲーム仕様書11章 §12 とデザインシステムの README・layout.md・icons-and-words.md。
- 文字に頼らない（D-148）、アイコンは1つ1つの意味（D-149）。画面の文言は英語ベース。
- 画面を見せる前に、デザインシステム README の「画面を作るときのチェックリスト」で自分で確かめる。既に作った画面と並べて、位置・語・色・入力がそろっているかを見る。
- 見本の数値はマスターデータと `docs/system/06_formulas.md` の式から出す。それらしい数字を手で置かない。

## 8. 作業環境の注意

- `lune` は Bash の PATH にない。PowerShell で `$env:Path = "$env:USERPROFILE\.rokit\bin;" + $env:Path` を付けて実行する。
- Notion に書いた日本語は、書いたあと読み返して誤字（変換ミス）を直す。
- 決定ID・Q番号を新しく振る前に、Notion の決定ログを検索して最大の番号を確かめる（INDEX.md だけを見て重複させない）。
