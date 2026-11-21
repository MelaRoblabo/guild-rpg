# M7 Roblox統合の確認（2026-11-21）

11章 §7 の確認方法にそって、M7 の完了条件（Roblox 上で M2〜M5b の全コマンドがデバッグ画面から実行でき、再参加で状態が戻る。`lune run tools/check` が通る）を確かめた。

環境：Rojo 7.7.1、Lune 0.11.1、selene 0.32.0。Studio のプレイス「冒険者ギルド」（D-100）、Studio MCP でプレイテストを操作。

## 1. 結果のまとめ

| 項目 | 結果 |
| --- | --- |
| `lune run tools/check` | ✅ 成功（テスト208件、selene の luau・roblox 両方で指摘なし） |
| 全コマンド（05章 M2〜M5b の24種類） | ✅ クライアントから送り、すべてサーバーに届いた（下の表） |
| 再参加で状態が戻る | ✅（§3） |
| オフライン中の帰還 | ✅ 参加時の通知に `ExpeditionReturned`・`LevelUp` が入った（M7-4） |
| 二重ログインの防止 | ✅ ロック喪失での切断、有効なロックでの待機とキック、期限切れロックの引き継ぎ（M7-2） |
| 差分の通知と再同期 | ✅ 差分を当てた手元の要約がサーバーの全体と一致。取りこぼしから再同期（M7-3） |
| 要約と差分の大きさ | 記録した（§4） |

## 2. 全コマンド

クライアント（Client データモデル）から、テキスト版と同じ書式を `CommandText.parse` でコマンドにして `Remotes.Command` に送った。デバッグ画面の入力欄と同じ経路。

| 書式 | type | 結果 |
| --- | --- | --- |
| `repeat 1 off` / `repeat 1 dng_graveyard` | SetAutoRepeat | OK |
| `party 1 4 -` / `party 1 4 adv_13` | SetPartySlot | OK |
| `unequip adv_1 weapon` | Unequip | OK |
| `equip adv_1 eq_4` | Equip | OK |
| `lock eq_4` / `unlock eq_4` | SetLock | OK |
| `open dng_graveyard` | OpenChests | OK |
| `sell eq_22` / `sell item itm_bone_fragment 1` | Sell | OK |
| `hire` / `pick 1` / `reroll` / `choose cur` / `cancel` | HireStart / HirePick / HireReroll / HireChoose / HireCancel | OK（HirePick は M7-4 の画面確認で OK） |
| `rename adv_1 …` | Rename | OK |
| `dismiss adv_26` | Dismiss | OK |
| `autosell on 1 keep` / `autosell off` | SetAutoSell | OK |
| `train adv_5 1` | Train | OK |
| `go 1 dng_graveyard` | Dispatch | OK |
| `rebirth adv_1` | RebirthStart | ゲームの規則どおりのエラー `LEVEL_NOT_AT_CAP` |
| `rb-reroll` / `rb-choose prev` | RebirthReroll / RebirthChoose | `NO_SESSION` |
| `jobchange adv_1 job_knight` | ChangeJob | `NO_POTION` |
| `looks adv_1` / `looks-choose cur` | ChangeAppearance / ChangeAppearanceChoose | `NO_POTION` / `NO_SESSION` |
| `expand exp_roster` | BuyExpansion | `GUILD_LEVEL_TOO_LOW` |

- `BAD_REQUEST`・`SERVER_ERROR`・`NOT_READY` は0件。最後に `Sync` の全体と、差分を当てた手元の要約が一致した。
- 転生・転職・見た目変更・拡張は、テスト用のセーブデータで前提（レベル上限・ポーション・ギルドレベル）がそろわず、ゲームの規則どおりのエラーまでを確認した。成功時の処理は core のテスト（Lune）で確認済み。Roblox 上での成功の確認は、前提をそろえたセーブデータで行うのが望ましい（未実施）。

## 3. 再参加での復元

1. 名前を変え（`ケンショウ`）、トレーニングをしてすぐ停止（60秒の定期保存より前）。
2. DataStore の記録：名前・所持金（378G）が保存され、ロックは解放済み。
3. 再参加：0.1秒で読み込み、名前・所持金・冒険者数・自動売却の設定が戻った。名前を戻して停止 → 保存された。

## 4. 要約と差分の大きさ（自動プレイ greedy・seed 1・72時間の状態）

測定スクリプト（一時的なもの。リポジトリには入れていない）：自動プレイと同じ進め方で72時間回し、`Protocol.view`・`Protocol.diff` を JSON にした大きさを測った。

| 項目 | 大きさ |
| --- | --- |
| 要約の全体（1時間／24時間／48時間／72時間） | 20KB／43KB／48KB／54KB |
| 72時間の時点 | 冒険者20人、装備82個、探索中5 |
| 帰還1回（時間経過）の差分（最後の2時間・304回） | 中央値 0.5KB、90% 0.9KB、最大 1.5KB |
| 帰還後の管理（複数のコマンド：再出発など）の差分 | 中央値 8.5KB、最大 18KB |
| 保護の切り替え1回 | 57バイト |
| 雇用の開始1回 | 0.9KB |

- 全体を送るのは参加時と再同期だけ（D-103）。毎回全体を送っていたら、終盤は1回 54KB になっていた。
- 差分で大きいのは、出発のたびに探索ログ（1件 約8KB）を丸ごと送ること。倉庫を満杯（装備1000個）まで溜めるプレイでは、全体が数百KBになる見込み（参加時のみ）。必要になったら、探索ログを再生に要る部分だけにする・倉庫を分けて送るなどを検討する。

## 5. 確認中に見つけて直したこと

| 内容 | 対応 |
| --- | --- |
| **サーバー終了時に保存されないことがある（データが消える）**：プレイ停止時、退出時の保存が終わる前に BindToClose が戻り、サーバーが閉じていた。直前の変更が失われ、古いロックが残って次の参加がキックされた | `PlayerSessions` で処理中の読み込み・保存を数え、BindToClose はそれが0になるまで待つ（最大25秒）。終了中に読み込みが終わったプレイヤーはロックを解放して終える。修正後、変更直後の停止で保存・解放されることを2回確認 |
| Rojo がファイルの変更を1回取りこぼした（OneDrive 内のフォルダ） | 11章に「プレイテストの前に Studio 側が最新か確かめる」を追記（M7-3） |
| デバッグ画面：失敗の印が表示されない／応答待ちの間に入力できない | 「NG」に変更、先に入力欄へ戻す（M7-4） |
| テキスト版のシナリオ `one_hour.txt` の `open all`（D-089 でダンジョンごとの開封に変わったときの更新漏れ） | `open dng_graveyard` などに修正。シナリオ全体が通ることを確認 |

## 6. 残っていること（M8 以降・Q 候補）

- 転生・転職・見た目変更・拡張の成功を Roblox 上で確かめる（前提をそろえたセーブデータを用意する方法を決める）。
- 開発中のセーブデータが本番の DataStore に入っている（D-100）。公開前の扱いを M9 までに決める。
- 全体が大きくなる場合（倉庫満杯）の対策は、必要になったら検討する（§4）。
