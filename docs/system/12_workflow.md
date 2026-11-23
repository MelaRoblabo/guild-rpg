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
| M7 Roblox統合 | 03, 05, 08, 11 | `src/server`、`src/client`、`src/core/{Protocol,CommandText}`（新規）、`tools/cli`（書式の解析を CommandText へ移す）、`tools/check`、`default.project.json`、`selene.toml`、`rokit.toml`、`tests/`、`docs/system/11`・`12` | Roblox 上で M2〜M5b の全コマンドがデバッグ画面から実行でき、再参加で状態が戻る（11章 §7）。`lune run tools/check` が通る |
| M7b 追加仕様（D-152〜D-168、元は提案 P-001〜P-017） | 決定ログ D-152〜D-168、Notion「追加仕様（P-001〜P-017）の影響と修正リスト」、ゲーム仕様書の改訂後の各章 | `docs/system/`、`src/core`、`src/data`、`tools/cli`、`tools/autoplay`、`tools/sim`、`tests/`、`src/server`（M7b-5。例外：M7b-2 で PlayerSessions の移行呼び出しに master を渡す1行） | 決定 D-152〜D-168 がテストつきで動く。派遣費のテストは廃止に合わせて消す（弱めるのではなく仕様の廃止）。自動プレイで暦日数の目標（ライト約70日・コア約30日・ヘビー約15日）に合う。`lune run tools/check` が通る |
| M8 UI設計・実装 | ゲーム仕様書11章 | M8 の実装に入る前に決める | 11章の画面が Roblox 上で動く（詳細は M8 の開始時に決める）。M7b の間は止める（受け取り箱・休息ボーナス・イベントで画面が変わるため） |
| M8-FX 演出（M8 と並行。D-147） | ゲーム仕様書11章 §8、D-140〜D-146 | `src/core`（演出を選ぶ処理を新規）、`src/data`（演出の表を新規）、`src/client`（演出の再生役・確認ツール）、`tools/sim`、`tests/` | 演出の選択がテスト（信頼度どおり・確定演出が外れない・降格しない）を通る。確認ツールで全演出を再生できる。100個あたりの平均時間が上限以内。点滅が1秒3回以内 |

### M7 の進め方

| 段階 | 内容 | 状態 |
| --- | --- | --- |
| M7-0 | ツール更新と require 方式の検証（D-102） | 済 |
| M7-1 | 11章・12章の詳細化（保存・通信・クライアント） | 済 |
| M7-2 | 保存：`SessionLock`（純粋）＋ DataStore の読み書き・定期保存・退出時保存 | 済（Studio で新規・復元・ロック喪失・ロック待ち・期限切れの引き継ぎを確認） |
| M7-3 | サーバー権限と通信：`Protocol`（検証・要約・差分 D-103）、Remotes、プレイヤーのセッション、定期の時間経過 | 済（Studio で全体取得・差分・検証・送りすぎの制限・帰還の通知・取りこぼしからの再同期を確認） |
| M7-4 | デバッグ画面：`CommandText` の切り出し、状態一覧と入力欄 | 済 |
| M7-5 | 確認：Studio で全コマンド・再参加・オフライン帰還、`tools/check` | 済（`docs/reports/M7_validation.md`） |

### M7b の進め方

影響と修正リスト（Notion）の行番号を「#」で示す。上から順に進め、各段階でテストを足す。

| 段階 | 内容 | 状態 |
| --- | --- | --- |
| M7b-0 | 決定ログへの起票（D-152〜D-168）、古い決定・INDEX・提案の表の更新 | 済 |
| M7b-1 | 仕様書の改訂：ゲーム仕様書（01・02・04・05・06・08・11・13・14・15章）、企画書（§1・§11・§16.8）、`docs/system`（03・04・05・06・07・09・13） | 済（要確認22件の回答待ち：Notion「M7b-1 で出た要確認（推奨案つき）」） |
| M7b-2 | 土台：日・週の区切り（#6-1）、派遣費の廃止（#5-4）、自動売却の初期値と一括売却（#4-1〜4-5）、宝箱の山の鍵とセーブの移行（#3-1・#8-1） | 済（サーバーの移行呼び出しに master を渡す1行は、v5 のセーブを読めなくなるのを防ぐため M7b-2 で直した） |
| M7b-3 | 時間の進み方：留守中の進行と休息ボーナス（#5-1・5-2）、日替わりの特性（#5-3） | 済（要確認：途中ログインの抜け道） |
| M7b-4 | 報酬：クエスト、ログインボーナス、プレイ時間、受け取り箱、今週の訪問者、専用ギフト、特別な宝箱、マップイベント・レイド・商人（#1・#2・#3・#5-5） | 未 |
| M7b-5 | Roblox 側：最後に保存した時刻と二重計算の防止、フレンドの判定、通知（#11） | 未 |
| M7b-6 | 経済の再調整：自動プレイに1日の流れと新しい入手先を入れ、暦日数の目標に合わせる（#5-6・#7・#14-1） | 未 |

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
