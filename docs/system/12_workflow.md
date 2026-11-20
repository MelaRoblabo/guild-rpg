# 12 開発の進め方

ゲーム仕様書13章「開発フェイズ計画」を、リポジトリでの作業手順に落としたもの。

## 1. フェイズ別の参照先と作業範囲

作業範囲外のファイルは変更しない（CLAUDE.md）。

| フェイズ | 参照する仕様 | 変更してよい場所 | 完了条件 |
| --- | --- | --- | --- |
| M0 基盤 | 02, 04, 08, 10 | ルートの設定、`src/core/{Rng,Types,MasterData}`、`src/data/Constants`、`tools/test`、`tools/check`、`tests/` | `lune run tools/check` が通る。壊れたマスターデータで起動が止まる |
| M1 探索コア | 06, 07, 09§2 | `src/core/{Formulas,Combat,Events,Expedition}`、`src/data/{Dungeons,Monsters,Jobs,Gifts,Modifiers,EquipmentBases,Rarities}`、`tools/sim`、`tests/` | 4ダンジョンの統計レポートが出る。Q-003/Q-004 の暫定値をレポートで提案 |
| M2 最小ループ | 03, 05（M2行）, 09§1 | `src/core/{Game,Party,Inventory,Chest,Growth,Migration}`、`src/data/{Items,LootTables,StarterSet}`、`tools/cli`、`tests/` | CLIで仮想1時間遊べる。最初の宝箱が1分以内 |
| M3 雇用・面接 | 05（M3行）, ゲーム仕様書02・07章 | `src/core/{Hiring,Appearance}`、`src/data/{Appearances,Names,Uniques}`、`tools/cli`、`tests/` | 雇用フロー全体がCLIで動く |
| M4 成長・転生・転職 | 05（M4行）, 06§8-9 | `src/core/{Rebirth,JobChange,Appearance,Growth}`、`tools/cli`、`tests/` | 転生・転職・見た目変更が仕様どおり |
| M5 ギルド・経済 | 05（M5行）, 06§10 | `src/core/{Guild,Game}`、`src/data/{GuildLevels,Expansions}`、`tools/cli`、`tools/autoplay`、`tests/` | 複数パーティ・自動再派遣・倉庫満杯時の停止・オフライン復帰 |
| M6 検証・調整 | 09§3-4 | `src/data/`（数値のみ）、`tools/autoplay`、`out/` | 企画書§14の検証項目に回答。仮の数値を決定ログで確定 |

## 2. 1回の作業の流れ（AI）

1. `CLAUDE.md` → `00_index.md` → 該当章を読む。
2. 作業計画（触るファイル、実装する決定ID、書くテスト）を先に示す。
3. テスト → 実装 → `lune run tools/check`。
4. 報告（実装した決定ID、変更ファイル、テスト結果、Q候補）。

## 3. 仕様の変更と同期

- 仕様の変更は必ず Notion の決定ログから始める（新しい D-xxx を起票）。
- `docs/decisions/INDEX.md` は Notion の決定ログを書き写したスナップショット。決定が増えたら同期作業として更新する（`docs:` コミット）。
- システム仕様書（本書）を変えるときは、根拠の決定IDを書く。

## 4. ブランチとコミット

- `main` は常に `tools/check` が通る状態。
- 作業はフェイズ単位のブランチ（例：`m1-expedition-core`）で行い、完了条件を満たしたら `main` へマージ。
- コミットの種別は CLAUDE.md §6。
