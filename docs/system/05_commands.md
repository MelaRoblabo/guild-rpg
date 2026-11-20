# 05 コマンド一覧

プレイヤーの操作はすべてコマンドとして `Game.execute(state, command, ctx)` に渡す。CLI・自動プレイヤー・Robloxサーバーは同じコマンドを使う。

## 1. 共通の形

```lua
command = { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }
result  = { ok = true, events = { ... } }          -- 成功
result  = { ok = false, error = "PARTY_BUSY" }      -- 失敗（state は不変）
```

- エラーコードは大文字スネークケース。CLIとUIは表示文言に変換する。
- 乱数を使うコマンドは、`state.seed` と `state.rngCounter` から乱数を作り、使ったら `rngCounter` を進める（08章）。

## 2. 一覧

| フェイズ | type | 引数 | 内容 | 主なエラー | 根拠 |
| --- | --- | --- | --- | --- | --- |
| M2 | `SetPartySlot` | partyIndex, slot(1-4), adventurerUid? | 隊列に配置／外す | PARTY_BUSY, ADVENTURER_IN_OTHER_PARTY | D-035 |
| M2 | `Equip` | adventurerUid, equipmentUid | 装備する（職業制限を確認） | JOB_CANNOT_EQUIP, ADVENTURER_ON_EXPEDITION | 06章 |
| M2 | `Unequip` | adventurerUid, slot | 外す | WAREHOUSE_FULL | 06章 |
| M2 | `Dispatch` | partyIndex, dungeonId | 派遣。探索ログを確定 | PARTY_BUSY, PARTY_EMPTY, DUNGEON_LOCKED | D-026 |
| M2 | `SetAutoRepeat` | partyIndex, dungeonId? | 自動再派遣の設定・解除 | — | 01章 |
| M2 | `OpenChests` | chestUids（"all"可） | 宝箱を開ける。中身をここで抽選 | WAREHOUSE_FULL | D-015 |
| M2 | `Sell` | equipmentUids / itemId+count | 売却 | ITEM_LOCKED, ITEM_EQUIPPED | 06章 |
| M2 | `SetLock` | uid, locked | 保護の切り替え | — | 02章 |
| M3 | `HireStart` | — | 雇用費を払い候補を抽選 | NOT_ENOUGH_GOLD, ROSTER_FULL, SESSION_EXISTS | 02章 |
| M3 | `HirePick` | candidateIndex | 面接する候補を選び初回抽選 | — | 02章 |
| M3 | `HireReroll` | keep?（"previous"/"current"、省略時は合計値の高い方） | 引き直し（無料回数→チケット）。keep を比較の基準に残す | NO_TICKET | 02章, D-073 |
| M3 | `HireChoose` | "previous" / "current" | 採用する結果を選んで雇用確定 | — | 02章 |
| M3 | `HireCancel` | — | 雇用を中止（雇用費は戻らない） | — | 02章 |
| M3 | `Rename` | adventurerUid, name | 名前変更（ユニーク不可） | UNIQUE_CANNOT_RENAME | 02章 |
| M3 | `Dismiss` | adventurerUid | 冒険者を解雇（保護中・探索中は不可） | ADVENTURER_LOCKED | Q-020 |
| M4 | `RebirthStart` | adventurerUid, useKeepPotion | 見た目を決めて転生を開始 | LEVEL_NOT_AT_CAP | 07章 |
| M4 | `RebirthReroll` | keep? | 加算分の引き直し（keep は HireReroll と同じ） | NO_TICKET | 07章, D-073 |
| M4 | `RebirthChoose` | "previous" / "current" | 結果を確定 | — | 07章 |
| M4 | `ChangeJob` | adventurerUid, jobId | 転職ポーションを使う | NO_POTION, UNIQUE_JOB_RESTRICTED | 03章 |
| M4 | `ChangeAppearance` | adventurerUid | 見た目変更ポーションで抽選 | NO_POTION, UNIQUE_CANNOT_CHANGE | 07章 |
| M4 | `ChangeAppearanceChoose` | "previous" / "current" | 見た目を選ぶ（どちらでも1個消費） | — | 07章 |
| M5 | `BuyExpansion` | expansionId | 拡張を購入 | NOT_ENOUGH_GOLD, GUILD_LEVEL_TOO_LOW | 08章 |
| M5 | `SetAutoSell` | enabled, maxRarity | 自動売却の設定 | — | 06章 |
| M9 | `GrantPurchase` | productId | Robux購入の付与（サーバー専用） | — | 10章 |

## 3. advance（時間経過）

`Game.advance(state, ctx)` はコマンドではないが、すべてのコマンドの前に呼ぶ。

1. `returnAt <= ctx.now` の探索を帰還時刻の古い順に処理し、報酬を反映する。
2. 自動再派遣が有効で、`ctx.online == true`、倉庫が満杯でない、宝箱保管が上限未満なら、帰還時刻を出発時刻として次の探索を確定する。これを `ctx.now` に追いつくまで繰り返す。
3. `ctx.online == false`（オフラインからの復帰時）は 1 だけ行う（企画書§16.8 案A）。

## 4. 読み取り用関数（状態を変えない）

`Game.query.*` として、表示に必要な計算済みの値を返す。例：冒険者の実効ステータス、パーティの合計攻撃力・技巧合計・移動時間、探索の現在位置（ログ再生）、攻略ヒント。UIとCLIは計算をここに任せ、自前で式を持たない。
