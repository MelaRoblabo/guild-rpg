# システム仕様書 目次

ゲーム仕様書（Notion）を、実装できる粒度に落とした設計図。AIが素早く読めるよう、1章1テーマで短く保つ。

| 章 | 内容 | 主に使うフェイズ |
| --- | --- | --- |
| [01_architecture](01_architecture.md) | 全体構成、層、データの流れ、決定論 | 全部 |
| [02_directory](02_directory.md) | フォルダ構成と各フォルダの責務 | 全部 |
| [03_state_model](03_state_model.md) | プレイヤー状態（セーブデータ）の型 | M2〜 |
| [04_master_data](04_master_data.md) | マスターデータの形式・検証・初期値 | M0〜 |
| [05_commands](05_commands.md) | 操作（コマンド）の一覧と入出力 | M2〜 |
| [06_formulas](06_formulas.md) | 計算式の一覧（決定ID付き） | M1〜 |
| [07_expedition_engine](07_expedition_engine.md) | 探索の計算手順と探索ログの形式 | M1 |
| [08_rng_time](08_rng_time.md) | 乱数と時刻の扱い | M0〜 |
| [09_cli_sim_autoplay](09_cli_sim_autoplay.md) | テキスト版・シミュレーター・自動プレイ | M1〜M6 |
| [10_testing](10_testing.md) | テストの書き方と実行 | 全部 |
| [11_roblox_integration](11_roblox_integration.md) | Roblox組み込みの方針（M7） | M7 |
| [12_workflow](12_workflow.md) | フェイズの進め方、作業範囲、仕様の同期 | 全部 |
| [13_glossary](13_glossary.md) | 用語と英語名（コード上の名前） | 全部 |

## 読み方

- 決定ID（`D-xxx`）は仕様の根拠。`docs/decisions/INDEX.md` で一行要約を引ける。
- 「（仮）」は仮採用の数値。マスターデータに置き、M6で調整する。
- 未決事項は `Q-xxx`。未決のまま実装が必要になったら、作業を止めて報告する。
