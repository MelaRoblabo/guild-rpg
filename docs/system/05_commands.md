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
| M2 | `Dispatch` | partyIndex, dungeonId | 派遣。探索ログを確定（出発時の日替わりの特性を当てる：D-156）。派遣費は廃止（D-163） | PARTY_BUSY, PARTY_EMPTY, DUNGEON_LOCKED | D-026, D-071, D-156, D-163 |
| M2 | `SetAutoRepeat` | partyIndex, dungeonId? | 自動再派遣の設定・解除 | — | 01章 |
| M2 | `OpenChests` | pileKey, count?（省略時 chestBatchOpen＝100） | 指定した宝箱の山（普通は dungeonId、特別は `special:<種類>`）から、残り数で重み付けして1つずつ引いて開ける。開けた装備は自動売却の設定で売り、売却用アイテムは常に売る（D-167）。結果は1つの `ChestsOpened` イベント：`normal`（演出なし、開けた順）と `special`（演出あり、レアリティの低い順）、`remaining` | PILE_NOT_FOUND, NO_CHEST, WAREHOUSE_FULL, INVALID_COUNT | D-015, D-084, D-087, D-089, D-166, D-167 |
| M2 | `Sell` | equipmentUids / itemId+count | 売却 | ITEM_LOCKED, ITEM_EQUIPPED | 06章 |
| M2 | `SetLock` | uid, locked | 保護の切り替え | — | 02章 |
| M3 | `HireStart` | — | 雇用費を払い候補を抽選 | NOT_ENOUGH_GOLD, ROSTER_FULL, SESSION_EXISTS | 02章 |
| M3 | `HirePick` | candidateIndex | 面接する候補を選び初回抽選 | — | 02章 |
| M3 | `HireReroll` | — | 引き直し（無料回数→チケット）。今回の結果が「前回」になり、それより前の結果は消える | NO_TICKET | 02章, D-086 |
| M3 | `HireChoose` | "previous" / "current" | 採用する結果を選んで雇用確定 | — | 02章 |
| M3 | `HireCancel` | — | 雇用を中止（雇用費は戻らない） | — | 02章 |
| M3 | `Rename` | adventurerUid, name | 名前変更（ユニーク不可） | UNIQUE_CANNOT_RENAME | 02章 |
| M3 | `Dismiss` | adventurerUid | 冒険者を解雇（保護中・探索中は不可） | ADVENTURER_LOCKED | Q-020 |
| M4 | `RebirthStart` | adventurerUid, useKeepPotion | 転生費用を払い、見た目を決めて転生を開始 | LEVEL_NOT_AT_CAP, NOT_ENOUGH_GOLD | 07章, D-080 |
| M4 | `RebirthReroll` | — | 加算分の引き直し（HireReroll と同じく直前の結果だけ残す） | NO_TICKET | 07章, D-086 |
| M4 | `RebirthChoose` | "previous" / "current" | 結果を確定 | — | 07章 |
| M4 | `ChangeJob` | adventurerUid, jobId | 転職ポーションを使う | NO_POTION, UNIQUE_JOB_RESTRICTED | 03章 |
| M4 | `ChangeAppearance` | adventurerUid | 見た目変更ポーションで抽選 | NO_POTION, UNIQUE_CANNOT_CHANGE | 07章 |
| M4 | `ChangeAppearanceChoose` | "previous" / "current" | 見た目を選ぶ（どちらでも1個消費） | — | 07章 |
| M5 | `BuyExpansion` | expansionId | 拡張を購入（パーティ枠・雇用候補枠・所属枠・倉庫・トレーニング場） | NOT_ENOUGH_GOLD, GUILD_LEVEL_TOO_LOW, DUNGEON_NOT_CLEARED | 08章, D-075, D-077 |
| M5 | `SetAutoSell` | enabled, maxRarity, keepModified? | 自動売却の設定（初期値はオン：D-167） | — | 06章, D-167 |
| M5b | `Train` | adventurerUid, sessions | トレーニング。最大 sessions 回、1回ごとに費用を払って経験値を得る。上限レベルかゴールド切れで止まる（払った回数分だけ行う） | TRAINING_CAP, NOT_ENOUGH_GOLD, ADVENTURER_ON_EXPEDITION, ADVENTURER_IN_REBIRTH, INVALID_COUNT | D-076, D-077 |
| M7b | `BulkSell` | equipmentUids（開封結果に出た装備） | 開封結果のうち「今の装備より弱い」もの（06章 §17）を全部売る。修飾語つき・保護中・装備中・商人で買ったもの・補助は対象外 | NOTHING_TO_SELL | D-120, D-167 |
| M7b | `ClaimInbox` | — | 受け取り箱の中身をまとめて受け取る（ゴールド・アイテム・宝箱の山・ユニーク）。受け取れないもの（所属枠・倉庫がいっぱいなど）は受け取り箱に残す（期限なし） | INBOX_EMPTY | D-164, D-176 |
| M7b | `ClaimFriendReward` | friendCount（サーバーが判定した同じサーバーの友達の数） | フレンドボタンの報酬（ゴールド、人数で少し増える・上限 friendRewardMaxFriends）。受け取り箱には入れない | FRIEND_NOT_READY, NO_FRIEND, DAILY_LIMIT | D-157 |
| M7b | `GrantReferral` | role（"invitee" / "inviter"）, userId | 紹介の報酬（サーバー専用）。招待された側は1回だけ。招待した側の報酬は、相手が referralProgressCondition に届いたときに「届け物」として別の保存場所に置かれ、招待した側の次のログインでこのコマンドで受け取り箱へ入れる（週の上限まで。他人のセーブを直接書き換えない）。届け物の保存の詳細は M7b-5 | ALREADY_REWARDED, WEEKLY_LIMIT | D-157, D-180 |
| M7b | `DispatchEvent` | partyIndex, eventSlot | マップイベント（レアダンジョン・レイドボス）へ派遣。出発できるのは出てから mapEventWindowSeconds の間。レアダンジョンは1パーティ1回まで。レイドはダメージを出発時に計算する | EVENT_NOT_ACTIVE, EVENT_WINDOW_CLOSED, EVENT_ALREADY_JOINED, PARTY_BUSY, PARTY_EMPTY | D-152, D-179 |
| M7b | `BuyFromMerchant` | eventSlot, itemIndex | 旅の商人で買う。買えるのはイベントの出発と同じ3分間（mapEventWindowSeconds）。買った装備は `fromMerchant = true` で倉庫へ入り、自動売却・一括売却で売らない | EVENT_NOT_ACTIVE, EVENT_WINDOW_CLOSED, ALREADY_BOUGHT, NOT_ENOUGH_GOLD, WAREHOUSE_FULL | D-152, D-175, D-179 |
| M9 | `GrantPurchase` | productId | Robux購入の付与（サーバー専用） | — | 10章 |

- クエストの進み具合（D-153）は、オンライン中のコマンドの結果（探索の出発・開封・雇用・トレーニング・踏破・転生）で数える。探索回数はオンライン中の出発（Dispatch・自動再派遣・DispatchEvent）で数える（D-179）。留守番の探索（`offline = true`）は数えない（D-161）。達成したらその報酬を受け取り箱へ入れる（D-164）。

## 3. advance（時間経過）

`Game.advance(state, ctx)` はコマンドではないが、すべてのコマンドの前に呼ぶ。

1. `returnAt <= ctx.now` の探索を帰還時刻の古い順に処理し、報酬を反映する。レイドへの派遣は到着時刻にダメージを入れ、HP を超えたら参加したパーティごとに1つレアな宝箱を受け取り箱へ入れる（D-152, D-164, D-179）。
2. 自動再派遣が有効で、`ctx.online == true`、倉庫が満杯でないなら、帰還時刻を出発時刻として次の探索を確定する。これを `ctx.now` に追いつくまで繰り返す。倉庫が満杯なら WAREHOUSE_FULL で停止する（派遣費の不足による停止は D-163 で削除）。
3. `ctx.online == false`（ログイン時の留守の計算）は留守番（D-161、06章 §13）を行う。
   - 留守の始まり＝`state.lastSavedAt`。ログアウト時に出ていた探索はふつうに帰還させる。
   - 自動再派遣のパーティは、帰還時刻から留守番の探索（時間 × `offlineTimeMult`、`offline = true`）を続ける。帰還時刻が `lastSavedAt + offlineMaxSeconds` を超える探索は出さない（6時間までに全員帰還して終わる）。留守中は倉庫がいっぱいでも止めない（D-172）。
   - 6時間より前にログインしたときは、まだ帰っていない留守番の探索をログインの時点（`ctx.now`）で帰還させる。結果は出発時に決まっているので、ログの報酬をそのまま受け取る。戻ったときは全員ギルドで待機（D-172）。
   - 休息ボーナスを貯める（06章 §14）。
   - 留守中にしないこと：マップイベント・商人・雇用・転生・トレーニング・プレイ時間報酬・クエストの数え上げ（D-161）。
   - 同じ留守を二重に計算しない。基準の `lastSavedAt` の書き込みとセッションロックはサーバー側（11章、M7b-5）。
4. `ctx.online == true` のときは、日・週の切り替え（06章 §11）を見て、クエストの入れ替え・ログインボーナスの前進（その日の最初のオンラインの advance で1日分）・プレイ時間のリセットを行う（D-153〜D-155, D-168）。プレイ時間は前回のオンラインの advance からの経過秒を足し（ログイン直後の最初の advance は足さない）、段階に届いたら報酬を受け取り箱へ（D-154）。休息ボーナスの残りはオンラインの経過秒だけ減らす（探索しているかは問わない。06章 §14、D-173）。

## 3b. ツール用の時間の操作

- 時刻を日単位で進めるのはツール（CLI・自動プレイヤー）の仮想時計の操作で、core のコマンドではない（09章）。core は渡された `ctx.now` を使うだけ（08章, D-168）。

## 4. 読み取り用関数（状態を変えない）

`Game.query.*` として、表示に必要な計算済みの値を返す。例：未開封の宝箱の山ごとの数（`chestsByPile`。レアリティは返さない：D-087, D-166）、今日・明日の日替わりの特性（`dailyTraits`：D-156）、今のマップイベントと予告（`mapEvent`：D-152）、今週の訪問者と出現率（`weeklyVisitor`：D-158）、留守番の見込み（`offlineForecast`：D-161, D-162）、休息ボーナスの残り、冒険者の実効ステータス、トレーニングの見積もり（`trainingQuote`・`trainingSessionCost`）、転生費用（`rebirthCost`）、パーティの合計攻撃力・技巧合計・移動時間、探索の現在位置（ログ再生）、攻略ヒント。UIとCLIは計算をここに任せ、自前で式を持たない。
