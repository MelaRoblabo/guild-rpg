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
| M7b | `ClaimInbox` | — | 受け取り箱の中身をまとめて受け取る（ゴールド・アイテム・宝箱の山・ユニーク）。受け取れないもの（所属枠・倉庫がいっぱいなど）は受け取り箱に残す（期限なし）。結果は `InboxClaimed`（gold・items・宝箱の山ごとの数・残った件数・blocked）と、加入したユニークごとの `UniqueJoined`。受け取れるものが無くても失敗にはしない | INBOX_EMPTY | D-164, D-176 |
| M7b | `ClaimFriendReward` | —（同じサーバーの友達の数はサーバーが数えて `ctx.friendCount` で渡す。クライアントからは受け取らない：M7b-5） | フレンドボタンの報酬（ゴールド、人数で少し増える・上限 friendRewardMaxFriends。式は06章 §20）。受け取り箱には入れず、その場で渡す。結果は `FriendReward`（gold・friendCount・nextAt・todayCount） | NO_FRIEND, DAILY_LIMIT, FRIEND_NOT_READY | D-157 |
| M7b | `GrantReferral` | role（"invitee" / "inviter"）, userId（招待した側なら招待された人）, deliveryId?（届け物の id） | 紹介の報酬（サーバー専用）を受け取り箱へ（source = "referral"、中身は referralRewards）。招待された側は1回だけ。招待した側の報酬は、相手が referralProgressCondition に届いたときに「届け物」として別の保存場所に置かれ、招待した側の次のログインで受け取り箱へ入れる（相手1人ごと・週の上限まで。他人のセーブを直接書き換えない）。受け取った届け物の id は `referral.claimedDeliveries` に記録し、同じ id は二度受け取らない。結果は `ReferralGranted`（role・userId・inboxUid） | ALREADY_CLAIMED, ALREADY_REWARDED, WEEKLY_LIMIT, INVALID_ROLE, INVALID_USER | D-157, D-180 |
| M7b | `DispatchEvent` | partyIndex, eventSlot | マップイベント（レアダンジョン・レイドボス）へ派遣。出発できるのは出てから mapEventWindowSeconds の間。レアダンジョンは1パーティ1回まで。レイドはダメージを出発時に計算する | EVENT_NOT_ACTIVE, EVENT_WINDOW_CLOSED, EVENT_ALREADY_JOINED, PARTY_BUSY, PARTY_EMPTY | D-152, D-179 |
| M7b | `BuyFromMerchant` | eventSlot, itemIndex | 旅の商人で買う。買えるのはイベントの出発と同じ3分間（mapEventWindowSeconds）。買った装備は `fromMerchant = true` で倉庫へ入り、自動売却・一括売却で売らない | EVENT_NOT_ACTIVE, EVENT_WINDOW_CLOSED, ALREADY_BOUGHT, NOT_ENOUGH_GOLD, WAREHOUSE_FULL | D-152, D-175, D-179 |
| M9 | `GrantPurchase` | productId | Robux購入の付与（サーバー専用） | — | 10章 |

- 受け取り箱へ入れたときのイベント：`QuestCompleted`（period・questId）、`QuestBonus`（period）、`LoginBonus`（day・cycle・uniqueId）、`PlaytimeReward`（minutes）。どれも `inboxUid` を持つ。
- クエストの進み具合（D-153）は、オンライン中のコマンドの結果（探索の出発・開封・雇用・トレーニング・踏破・転生）で数える。探索回数はオンライン中の出発（Dispatch・自動再派遣・DispatchEvent）で数える（D-179）。留守番の探索（`offline = true`）は数えない（D-161）。達成したらその報酬を受け取り箱へ入れる（D-164）。

## 3. advance（時間経過）

`Game.advance(state, ctx)` はコマンドではないが、すべてのコマンドの前に呼ぶ。

1. `returnAt <= ctx.now` の探索を帰還時刻の古い順に処理し、報酬を反映する。レイドへの派遣は到着時刻にダメージを入れ、HP を超えたら参加したパーティごとに1つレアな宝箱を受け取り箱へ入れる（D-152, D-164, D-179）。
2. 自動再派遣が有効で、`ctx.online == true`、倉庫が満杯でないなら、帰還時刻を出発時刻として次の探索を確定する。これを `ctx.now` に追いつくまで繰り返す。倉庫が満杯なら WAREHOUSE_FULL で停止する（派遣費の不足による停止は D-163 で削除）。
3. `ctx.online == false`（ログイン時の留守の計算）は留守番（D-161、06章 §13）を行う。
   - 留守の始まり＝`state.lastSavedAt`。ログアウト時に出ていた探索はふつうに帰還させる。
   - 自動再派遣のパーティは、帰還時刻から留守番の探索（時間 × `offlineTimeMult`、`offline = true`）を続ける。帰還時刻が `lastSavedAt + offlineMaxSeconds` を超える探索は出さない（6時間までに全員帰還して終わる）。留守中は倉庫がいっぱいでも止めない（D-172）。
   - 6時間より前にログインしたときは、まだ帰っていない留守番の探索をログインの時点（`ctx.now`）で帰還させる。持ち帰るのは、探索ログの時間の流れに沿ってその時点までに終わったフロアの分の経験値・ゴールド・宝箱・アイテムだけ（その時点で撤退したのと同じ。踏破していなければ確定宝箱など踏破の報酬は出さない。全フロアを終えて帰りの移動中ならログのとおり全部）。戻ったときは全員ギルドで待機（D-172, D-186）。
   - 休息ボーナスを貯める（06章 §14）。
   - 留守中にしないこと：マップイベント・商人・雇用・転生・トレーニング・プレイ時間報酬・クエストの数え上げ（D-161）。
   - 同じ留守を二重に計算しない。基準の `lastSavedAt` の書き込みとセッションロックはサーバー側（11章、M7b-5）。
4. `ctx.online == true` のときは、1〜2 のあとで、日・週の切り替え（06章 §11）を見て、クエストの入れ替え・ログインボーナスの前進（その日の最初のオンラインの advance で1日分）・プレイ時間のリセットを行う（D-153〜D-155, D-168）。プレイ時間は前回のオンラインの advance からの経過秒を足し（ログイン直後の最初の advance は足さない）、段階に届いたら報酬を受け取り箱へ（D-154）。休息ボーナスの残りはオンラインの経過秒だけ減らす（探索しているかは問わない。06章 §14、D-173）。

## 3a. 届け物（サーバーの呼び口：D-180）

`Game.grantDelivery(state, delivery, ctx) -> (boolean, events)`。delivery = `{ id, kind, fromUserId, at, data? }`。
別の保存場所（サーバーが M7b-5 で持つ）から届いた物を受け取り箱へ入れる。`kind = "referral"` は紹介で招待した側への報酬で、`GrantReferral`（role = "inviter", userId = fromUserId, deliveryId = id）を実行する。

- 同じ id の届け物は二度受け取らない（`referral.claimedDeliveries`）。サーバーが「保存してから届け物を消す」間に落ちて同じ届け物がもう一度来ても、何も変えずに false を返す。
- 戻り値の boolean は「状態を変えたか」。false（受け取り済み・同じ相手でもう受け取った・週の上限・知らない種類・形の違うもの）のときも、サーバーは届け物を消してよい。
- 招待された側の「招待した人へ届け物を書いた」印は `Friend.inviterDelivered(state)` / `Friend.markInviterDelivered(state)` で読み書きする（書くきっかけの判定はサーバー：M7b-5）。

## 3b. ツール用の時間の操作

- 時刻を日単位で進めるのはツール（CLI・自動プレイヤー）の仮想時計の操作で、core のコマンドではない（09章）。core は渡された `ctx.now` を使うだけ（08章, D-168）。

## 4. 読み取り用関数（状態を変えない）

`Game.query.*` として、表示に必要な計算済みの値を返す。例：未開封の宝箱の山ごとの数（`chestsByPile`。レアリティは返さない：D-087, D-166）、今日・明日の日替わりの特性（`dailyTraits`：D-156）、今のマップイベントと予告（`mapEvent`：D-152）、今週の訪問者と出現率（`weeklyVisitor`：D-158。uniqueId・候補1人あたりの chance・candidateSlots・owned・nextWeekAt）、フレンドボタンの状態（`friend`：D-157。nextAt・todayCount・dailyCap・今押したときの gold・押せない理由 blocker）、留守番の見込み（`offlineForecast`：D-161, D-162）、休息ボーナスの残り、冒険者の実効ステータス、トレーニングの見積もり（`trainingQuote`・`trainingSessionCost`）、転生費用（`rebirthCost`）、パーティの合計攻撃力・技巧合計・移動時間、探索の現在位置（ログ再生）、攻略ヒント。受け取り箱の中身（`inbox`。宝箱は山ごとの数）、今日・今週のクエスト（`quests`）、ログインボーナスのカレンダー（`loginCalendar`）、今日のプレイ時間（`playtime`）。UIとCLIは計算をここに任せ、自前で式を持たない。
