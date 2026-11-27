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
| M2 | `SetPartySlot` | partyIndex, slot(1-4), adventurerUid? | 隊列に配置／外す。リーダーが外れたらリーダーの記録を消す（次はいちばん前の人） | PARTY_BUSY, ADVENTURER_IN_OTHER_PARTY | D-035, D-271 |
| M8 | `SetPartyLeader` | partyIndex, adventurerUid | パーティのリーダーを決める（アイコンと名前だけ。探索中も可）。リーダーは `Party.leader`（leaderUid がいなければいちばん前の人） | PARTY_NOT_FOUND, ADVENTURER_NOT_IN_PARTY | D-271 |
| M2 | `Equip` | adventurerUid, equipmentUid | 装備する（職業制限を確認） | JOB_CANNOT_EQUIP, ADVENTURER_ON_EXPEDITION | 06章 |
| M2 | `Unequip` | adventurerUid, slot | 外す | WAREHOUSE_FULL | 06章 |
| M2 | `Dispatch` | partyIndex, dungeonId | 派遣。探索ログを確定（出発時の日替わりの特性を当てる：D-156）。派遣費は廃止（D-163）。パーティが開けていない宝箱（haul）を持っていたら受け取り箱へ移す（`HaulToInbox`：D-302。DispatchEvent も同じ） | PARTY_BUSY, PARTY_EMPTY, DUNGEON_LOCKED | D-026, D-071, D-156, D-163 |
| M2 | `SetAutoRepeat` | partyIndex, dungeonId? | 自動再派遣の設定・解除 | — | 01章 |
| M2 | `OpenChests` | pileKey, count?（省略時 chestBatchOpen＝100） | 指定した宝箱の山（普通は dungeonId、特別は `special:<種類>`）から、残り数で重み付けして1つずつ引いて開ける。開けた装備は自動売却の設定で売り、売却用アイテムは常に売る（D-167）。初めて開ける宝箱（`stats.firstChestOpenedAt` がないセーブの最初の1箱）には、パーティ1の誰かの今の装備より強い装備を1つ足す（`LootTables.firstChest` のレアリティ・グレード・枠。自動売却しない。結果の `firstUpgrade` にその uid：D-246 ①）。結果は1つの `ChestsOpened` イベント：`normal`（演出なし、開けた順）と `special`（演出あり、レアリティの低い順）、`remaining` | PILE_NOT_FOUND, NO_CHEST, WAREHOUSE_FULL, INVALID_COUNT | D-015, D-084, D-087, D-089, D-166, D-167, D-246 ① |
| M2 | `Sell` | equipmentUids / itemId+count | 売却 | ITEM_LOCKED, ITEM_EQUIPPED | 06章 |
| M2 | `SetLock` | uid, locked | 保護の切り替え | — | 02章 |
| M3 | `HireStart` | — | 雇用費を払い候補を抽選 | NOT_ENOUGH_GOLD, ROSTER_FULL, SESSION_EXISTS | 02章 |
| M8 | `HireRerollCandidates` | — | 面接の前（候補を選ぶ前）に、雇用費と同じ額（`hireCost`：D-311）を払って候補を全員引き直す。面接の無料の引き直し回数は変わらない | NO_SESSION, ALREADY_PICKED, NOT_ENOUGH_GOLD | D-310 |
| M3 | `HirePick` | candidateIndex | 面接する候補を選び初回抽選 | — | 02章 |
| M3 | `HireReroll` | — | 引き直し（無料回数→チケット）。今回の結果が「前回」になり、それより前の結果は消える | NO_TICKET | 02章, D-086 |
| M3 | `HireChoose` | "previous" / "current" | 採用する結果を選んで雇用確定。職業の hireEquipment（コモン+0・アイテムレベル1の3点）を付けて来る（D-266） | — | 02章, D-266 |
| M3 | `HireCancel` | — | 雇用を中止（雇用費は戻らない） | — | 02章 |
| M3 | `Rename` | adventurerUid, name | 名前変更（ユニーク不可） | UNIQUE_CANNOT_RENAME | 02章 |
| M3 | `Dismiss` | adventurerUid | 冒険者を解雇（保護中・探索中は不可） | ADVENTURER_LOCKED | Q-020 |
| M4 | `RebirthStart` | adventurerUid | 転生費用を払って転生を開始（見た目は確定の後に選ぶ：D-230） | LEVEL_NOT_AT_CAP, NOT_ENOUGH_GOLD | 07章, D-080, D-230 |
| M4 | `RebirthReroll` | — | 加算分の引き直し（HireReroll と同じく直前の結果だけ残す） | NO_TICKET | 07章, D-086 |
| M4 | `RebirthChoose` | "previous" / "current" | 結果を確定し、新しい見た目を引く（ユニークは固定） | — | 07章, D-230 |
| M8 | `RebirthAppearanceChoose` | "previous" / "current" | 転生の見た目を選ぶ（current＝新しい見た目、previous＝見た目維持ポーションを1個使って前の見た目）。確定の後の1回だけ | NO_SESSION, NO_POTION | D-230 |
| M4 | `ChangeJob` | adventurerUid, jobId | 転職ポーションを使う | NO_POTION, UNIQUE_JOB_RESTRICTED | 03章 |
| M4 | `ChangeAppearance` | adventurerUid | 見た目変更ポーションで抽選 | NO_POTION, UNIQUE_CANNOT_CHANGE | 07章 |
| M4 | `ChangeAppearanceChoose` | "previous" / "current" | 見た目を選ぶ（どちらでも1個消費） | — | 07章 |
| M5 | `BuyExpansion` | expansionId | 拡張を購入（パーティ枠・雇用候補枠・所属枠・倉庫・トレーニング場） | NOT_ENOUGH_GOLD, GUILD_LEVEL_TOO_LOW, DUNGEON_NOT_CLEARED | 08章, D-075, D-077 |
| M8 | `UnlockDungeon` | dungeonId | ゴールドでダンジョンを先に解放する（前のダンジョンが解放済みのとき。金額は unlockGold）。踏破での無料解放はそのまま | DUNGEON_NOT_FOUND, DUNGEON_ALREADY_UNLOCKED, DUNGEON_PREV_LOCKED, NOT_ENOUGH_GOLD | D-279 |
| M5 | `SetAutoSell` | enabled, maxRarity, keepModified? | 自動売却の設定（初期値はオン：D-167） | — | 06章, D-167 |
| M8 | `AutoEquip` | partyIndex, adventurerUid? | adventurerUid を渡すとそのパーティのその人の分だけ（パーティに入れた瞬間：D-266）。自動装備（06章 §24）：隊列1番から順に、倉庫の品と本人の今の装備から、武器は攻撃力補正、防具は最後の行き先の攻撃の種類の割合で重み付けした防御が一番高いものに付け替える。補助・修飾語は見ない。他の冒険者が付けている品は使わない。前の装備は倉庫へ。提案は `Game.query.autoEquipPlan`（同じ計算）。結果は `AutoEquipped`（partyIndex・changes） | PARTY_NOT_FOUND, PARTY_BUSY, ADVENTURER_NOT_IN_PARTY, NOTHING_TO_CHANGE | D-120, D-231 ⑨, D-235 ③, D-266 |
| M8 | `SetSettings` | musicVolume?, soundVolume?（0〜volumeSteps）, chestAnimation?, lessFlashing?, returnToast?, cutIns?, otherCarts? | 設定（S-61）を `settings.prefs` に保存する。送った項目だけ変わる。保存がなければ `StarterSet.preferences` の初期値。`Game.query.preferences` で読む。イベントなし | INVALID_VOLUME | D-117, D-145, D-237 ③ |
| M8 | `SetGuideStep` | step（1〜99） | 初回の誘導（D-244 ①）の済んだ段の数を `settings.guideStep` に保存する（設定と一緒にサーバーへ：D-117）。小さい数は無視（戻らない）。段の中身（馬車→Go→宝箱ボタン→Open All→Equip→Quests：D-246 ②）は画面が持つ。`Game.query.guideStep` で読み、要約の `guideStep` にも入れて送る（保存がなく一度でも帰還したセーブは全部済んだ扱い＝`Game.GUIDE_DONE`）。イベントなし | — | D-244 ①, D-246 ②, D-117 |
| M8 | `Inspect`（読み取り専用） | userId, partyIndex | 他のプレイヤーのパーティの詳細（S-14）。`Game.execute` を通さず、サーバーが同じサーバーにいる相手の状態から `World.inspect` で答える（メンバーの name・jobId・level・appearanceId、ギルドLv、行き先と出発時刻・時間）。状態は変えない。回数制限の対象。形の表は `Protocol.READ_COMMANDS` | NOT_FOUND（相手がいない・探索中でない） | D-108, D-121, 11章（システム）§6.2 |
| M8 | `SetListPrefs` | advSort?, advDesc?, whSort?, whDesc?, bulkSellRarityMask?, bulkSellEnchanted?, bulkSellPlus? | 一覧の並べ方（冒険者 S-40：level・attack・maxHp・hired・rebirths、倉庫 S-50：rarity・power・sell・new。desc＝高い順）と、Bulk Sell の前回の入切（売るレアリティ＝rank r の入が 2^(r-1) の位の数、エンチャント装備も売るか、プラスも売るか：D-303）を `settings.listPrefs` に保存する。送った項目だけ変わる。保存がなければ `StarterSet.listPrefs` の初期値（冒険者は Lv の高い順、倉庫はレアリティの高い順、一括売却は Common〜Rare、エンチャント装備は売らない、プラスは売る。前の版の bulkSellMaxRarity だけがあれば上限以下を入にする）。`Game.query.listPrefs` で読む。イベントなし | INVALID_SORT, INVALID_RARITY | D-117, D-119, D-231 ⑮, D-303 |
| M5b | `Train` | adventurerUid, sessions | トレーニング。最大 sessions 回、1回ごとに費用を払って経験値を得る。上限レベルかゴールド切れで止まる（払った回数分だけ行う）。クエストの「トレーニング」は行った回数で数える（D-191） | TRAINING_CAP, NOT_ENOUGH_GOLD, ADVENTURER_ON_EXPEDITION, ADVENTURER_IN_REBIRTH, INVALID_COUNT | D-076, D-077 |
| M7b | `BulkSell` | equipmentUids（開封結果に出た装備） | 開封結果のうち「今の装備より弱い」もの（06章 §17）を全部売る。修飾語つきも弱ければ売る（D-207）。保護中・装備中・商人で買ったもの・補助は対象外。確認は出さない（ボタンに売る数と合計額：`Game.query.bulkSellPreview`）。倉庫からの一括売却（D-120、確認あり）はこのコマンドではなく `Sell` で売る | NOTHING_TO_SELL | D-167, D-175, D-207 |
| M7b | `ClaimInbox` | — | 受け取り箱の中身をまとめて受け取る（ゴールド・アイテム・宝箱の山・ユニーク）。受け取れないもの（所属枠・倉庫がいっぱいなど）は受け取り箱に残す（期限なし）。結果は `InboxClaimed`（gold・items・宝箱の山ごとの数・残った件数・blocked）と、加入したユニークごとの `UniqueJoined`。受け取れるものが無くても失敗にはしない | INBOX_EMPTY | D-164, D-176 |
| M9 | `ClaimQuest` | period（"daily" / "weekly"）, questId | 達成したお題の報酬をその場で受け取る（受け取り箱を通さない）。結果は `QuestClaimed`（period・questId・rewards＝渡した gold・items・chests） | QUEST_NOT_FOUND, QUEST_NOT_DONE, QUEST_ALREADY_CLAIMED | D-286 |
| M9 | `ClaimQuestBonus` | period | その期間のお題を全部達成したボーナスを受け取る。結果は `QuestBonusClaimed`（period・rewards） | QUEST_NOT_FOUND, QUEST_NOT_DONE, QUEST_ALREADY_CLAIMED | D-286 |
| M9 | `ClaimHaul` | partyIndex | 帰還の獲得の吹き出しから開ける：パーティが持つ宝箱（`haul.chests`）を宝箱の山へ移して `haul` を消す。クライアントはこのあと移した数だけ OpenChests する。ゴールドは帰還のときに入っている。結果は `HaulClaimed`（partyIndex・gold・runs・chests＝山ごとの数） | PARTY_NOT_FOUND, HAUL_EMPTY | D-287, D-302 |
| M7b | `ClaimFriendReward` | —（同じサーバーの友達の数はサーバーが数えて `ctx.friendCount` で渡す。クライアントからは受け取らない：M7b-5） | フレンドボタンの報酬（ゴールド。踏破した一番深いダンジョンに応じて増え、人数で少し増える・上限 friendRewardMaxFriends。式は06章 §20・§22、D-190）。受け取り箱には入れず、その場で渡す。結果は `FriendReward`（gold・friendCount・nextAt・todayCount） | NO_FRIEND, DAILY_LIMIT, FRIEND_NOT_READY | D-157 |
| M7b | `GrantReferral` | role（"invitee" / "inviter"）, userId（招待した側なら招待された人）, deliveryId?（届け物の id） | 紹介の報酬（サーバー専用）を受け取り箱へ（source = "referral"、中身は referralRewards＝ステータススロットチケット）。両者とも招待された人が referralProgressCondition（転生回数の累計 `stats.rebirths`：D-195）に届いたときに渡す（D-192）。招待された側は1回だけで、`Friend.referralProgressReached(state, master)` が false なら PROGRESS_NOT_REACHED。招待した側の報酬は、相手が referralProgressCondition に届いたときに「届け物」として別の保存場所に置かれ、招待した側の次のログインで受け取り箱へ入れる（相手1人ごと・週の上限まで。他人のセーブを直接書き換えない）。受け取った届け物の id は `referral.claimedDeliveries` に記録し、同じ id は二度受け取らない。結果は `ReferralGranted`（role・userId・inboxUid。クライアントへ送るときは userId を除く：D-192） | ALREADY_CLAIMED, ALREADY_REWARDED, WEEKLY_LIMIT, INVALID_ROLE, INVALID_USER, PROGRESS_NOT_REACHED | D-157, D-180, D-192, D-195 |
| M7b | `DispatchEvent` | partyIndex, eventSlot | マップイベント（レアダンジョン・レイドボス・旅の商人）へ派遣。旅の商人へは1つの商人に1パーティだけ（帰ってきた後も2組目は送れない）、片道は場所の距離だけで決まり、着いたら `LeaveMerchant` までとどまる。探索の回数には数えない（D-274）。出発できるのは出てから mapEventWindowSeconds の間。レアダンジョン・レイドとも1パーティ1回まで（帰ってきても同じ時間帯には出られない：D-187）。レアダンジョンには日替わりの特性を当てない（D-187）。レイドはダメージを出発時に計算する | EVENT_NOT_ACTIVE（まだの時間帯）, EVENT_WINDOW_CLOSED（3分間を過ぎた・過ぎた時間帯）, EVENT_ALREADY_JOINED（レアダンジョン・レイドとも同じ時間帯に1パーティ1回まで。商人は1つの商人に1パーティ）, PARTY_BUSY, PARTY_EMPTY, ADVENTURER_IN_REBIRTH | D-152, D-179, D-187, D-274 |
| M7b | `BuyFromMerchant` | eventSlot, itemIndex | 旅の商人で買う。買えるのは、その時間帯の商人のところにパーティが着いていて、まだ帰り始めていない間だけ（3分間を過ぎていてもよい：D-274）。品のレアリティは宝箱の表からコモンを除いて引く（D-189、06章 §12）。買った装備は `fromMerchant = true` で倉庫へ入り、自動売却・一括売却で売らない | EVENT_NOT_ACTIVE（まだの時間帯・商人でない時間帯）, MERCHANT_NO_PARTY（パーティが商人のところにいない）, ITEM_NOT_FOUND（番号の品がない）, ALREADY_BOUGHT, NOT_ENOUGH_GOLD, WAREHOUSE_FULL | D-152, D-175, D-179, D-274 |
| M8 | `LeaveMerchant` | partyIndex | 商人のところから帰り始める。片道秒で帰り、商人は去る。ログアウトしたら留守の計算でログアウトの時刻（まだ着いていなければ着いた時刻）に帰り始める。押さなくても merchantStayMaxSeconds で帰り始める | MERCHANT_NO_PARTY（商人のところにいない）, MERCHANT_NOT_ARRIVED（まだ向かっている） | D-274 |
| M7b | `MarkNotifyPrompt` | stage（"firstReturn" / "loginDay2"） | 通知の許可の画面を出した記録を `settings.notifyPrompt` に付ける（設定と一緒にサーバーへ保存：D-117）。クライアントが許可の画面を出したあと（出せなかったときも）に送る。今の機会（`Game.query.notifyPromptDue`）と違えば記録しない。firstReturn を付けたときにログインボーナスの2日目をもう受け取っていたら loginDay2 も付ける（06章 §23）。結果は `NotifyPromptMarked`（stage） | INVALID_STAGE, NOT_DUE | D-196, D-117 |
| M9 | `GrantPurchase` | productId | Robux購入の付与（サーバー専用） | — | 10章 |

- マップイベントのイベント：`EventDispatched`（kind・eventSlot・partyIndex。レアダンジョンは dungeonId・pileKey、レイドは damage・hp・arriveAt）、`RaidHit`（damage・total・hp・defeated）、`RaidDefeated`、`RaidReward`（inboxUid）、`RaidReturned`、`MerchantBought`（itemIndex・equipmentUid・price）。レアダンジョンからの帰還は `ExpeditionReturned` に eventSlot・pileKey が付く。
- 受け取り箱へ入れたときのイベント：`LoginBonus`（day・cycle・uniqueId）、`PlaytimeReward`（minutes）。どれも `inboxUid` を持つ。
- クエストの達成：`QuestCompleted`（period・questId）、`QuestBonus`（period）。報酬は渡さない（受け取れる印だけ：D-286）。
- クエストの進み具合（D-153）は、オンライン中のコマンドの結果（探索の出発・開封・雇用・トレーニング・踏破・転生）で数える。探索回数はオンライン中の出発（Dispatch・自動再派遣・DispatchEvent）で数える（D-179）。トレーニングは行った回数、踏破はレアダンジョンの踏破も数えレイドは数えない（D-191）。留守番の探索（`offline = true`）は数えない（D-161）。達成したら受け取れる印を付け、報酬は ClaimQuest・ClaimQuestBonus で受け取る（D-286）。

## 3. advance（時間経過）

`Game.advance(state, ctx)` はコマンドではないが、すべてのコマンドの前に呼ぶ。

1. `returnAt <= ctx.now` の探索を帰還時刻の古い順に処理し、報酬を反映する。レイドへの派遣は到着時刻にダメージを入れ、HP を超えたら参加したパーティごとに1つレアな宝箱を受け取り箱へ入れる（D-152, D-164, D-179）。
2. 自動再派遣が有効で、`ctx.online == true`、倉庫が満杯でないなら、帰還時刻を出発時刻として次の探索を確定する。これを `ctx.now` に追いつくまで繰り返す。倉庫が満杯なら WAREHOUSE_FULL で停止する（派遣費の不足による停止は D-163 で削除）。
3. `ctx.online == false`（ログイン時の留守の計算）は留守番（D-161、06章 §13）を行う。
   - 留守の始まり＝`max(state.lastSavedAt, state.lastAdvancedAt)`（`Game.offlineStart`。D-193）。ログアウト時に出ていた探索はふつうに帰還させる。サーバーが落ちて失われたオンラインの進み具合（最後の定期保存から落ちるまで）は、次のログインで留守として計算される（二重にはならない。D-193）。
   - 自動再派遣のパーティは、帰還時刻から留守番の探索（時間 × `offlineTimeMult`、`offline = true`）を続ける。帰還時刻が `留守の始まり + offlineMaxSeconds` を超える探索は出さない（6時間までに全員帰還して終わる）。留守中は倉庫がいっぱいでも止めない（D-172）。
   - 6時間より前にログインしたときは、まだ帰っていない留守番の探索をログインの時点（`ctx.now`）で帰還させる。持ち帰るのは、探索ログの時間の流れに沿ってその時点までに終わったフロアの分の経験値・ゴールド・宝箱・アイテムだけ（その時点で撤退したのと同じ。踏破していなければ確定宝箱など踏破の報酬は出さない。全フロアを終えて帰りの移動中ならログのとおり全部）。戻ったときは全員ギルドで待機（D-172, D-186）。
   - 留守中にしないこと：マップイベント・商人・雇用・転生・トレーニング・プレイ時間報酬・クエストの数え上げ（D-161）。
   - 同じ留守を二重に計算しない（留守の始まりを最後に時間を進めた時刻より前にしない）。`lastSavedAt` の書き込みとセッションロックはサーバー側（11章、M7b-5）。
4. `ctx.online == true` のときは、1〜2 のあとで、日・週の切り替え（06章 §11）を見て、クエストの入れ替え・ログインボーナスの前進（その日の最初のオンラインの advance で1日分）・プレイ時間のリセットを行う（D-153〜D-155, D-168）。プレイ時間は前回のオンラインの advance からの経過秒を足し（ログイン直後の最初の advance は足さない）、段階に届いたら報酬を受け取り箱へ（D-154）。

## 3a. 届け物（サーバーの呼び口：D-180）

`Game.grantDelivery(state, delivery, ctx) -> (boolean, events)`。delivery = `{ id, kind, fromUserId, at, data? }`。
別の保存場所（サーバーが M7b-5 で持つ）から届いた物を受け取り箱へ入れる。`kind = "referral"` は紹介で招待した側への報酬で、`GrantReferral`（role = "inviter", userId = fromUserId, deliveryId = id）を実行する。

- 同じ id の届け物は二度受け取らない（`referral.claimedDeliveries`）。サーバーが「保存してから届け物を消す」間に落ちて同じ届け物がもう一度来ても、何も変えずに false を返す。
- 戻り値の boolean は「状態を変えたか」。false（受け取り済み・同じ相手でもう受け取った・週の上限・知らない種類・形の違うもの）のときも、サーバーは届け物を消してよい。
- 招待された側の「招待した人へ届け物を書いた」印は `Friend.inviterDelivered(state)` / `Friend.markInviterDelivered(state)` で読み書きする。
- 書くきっかけ（D-192, D-195）：サーバーは招待された人のセーブで `Friend.referralProgressReached(state, master) -> boolean` を見て、true かつ `referredBy` があり印が付いていなければ、招待した人へ届け物を書き、印を付け（`markInviterDelivered`）、招待された側に `GrantReferral`（role = "invitee"）を実行する。招待した側の週の上限を超えた届け物は、翌週まで届け物の箱に残す。招待した人の届け物の箱がいっぱい（full）なら、そのセッションでは試し直さず、招待された人の次のログインでもう一度書く（D-197。11章 §3.7）。
- `referredBy` を入れるのは新規のプレイヤー（初めての参加）のときだけ。招待された側の報酬で招待した人がいるかは、サーバー専用のコマンドなのでサーバーが確かめる（core の `GrantReferral` では確かめない：D-195）。

## 3b. ツール用の時間の操作

- 時刻を日単位で進めるのはツール（CLI・自動プレイヤー）の仮想時計の操作で、core のコマンドではない（09章）。core は渡された `ctx.now` を使うだけ（08章, D-168）。

## 4. 読み取り用関数（状態を変えない）

`Game.query.*` として、表示に必要な計算済みの値を返す。例：未開封の宝箱の山ごとの数（`chestsByPile`。`{ { pileKey, count } }` の配列。普通の山はダンジョンの順、続けて特別な宝箱の山を鍵の順。レアリティは返さない：D-087, D-166）、今日・明日の日替わりの特性（`dailyTraits`：D-156）、今のマップイベントと予告（`mapEvent`：D-152）、旅の商人の品と価格・購入済み・買えるか（`merchant`。open＝パーティが着いている・partyIndex・arriveAt）、地図に出ている商人（`merchantPresence`：D-274。open／coming／here）、商人までの片道秒（`merchantTravelSeconds`）、開封結果からの一括売却で売る数と合計額（`bulkSellPreview`：D-207。`BulkSell` と同じ判定で count・gold・equipmentUids）、レイドの HP と入ったダメージ（`raid`）、パーティのレイドのダメージの見込み（`raidDamage`）、地図に出ているレイドボス（`raidPresence`：D-275。open／closed・向かっているパーティ coming・arriveIn）、その時間帯のイベントの種類と場所（`mapEventAt`）、レアダンジョンの行き先と参加済みのパーティ（`rareDungeon`）、今週の訪問者と出現率（`weeklyVisitor`：D-158。uniqueId・候補1人あたりの chance・candidateSlots・owned・nextWeekAt）、フレンドボタンの状態（`friend`：D-157。nextAt・todayCount・dailyCap・今押したときの gold・押せない理由 blocker）、留守番の見込み（`offlineForecast`：D-161, D-162）、休息ボーナスの残り、冒険者の実効ステータス、トレーニングの見積もり（`trainingQuote`・`trainingSessionCost`）、転生費用（`rebirthCost`）、パーティの合計攻撃力・技巧合計・移動時間、探索の現在位置（ログ再生）、攻略ヒント。受け取り箱の中身（`inbox`。宝箱は山ごとの数）、今日・今週のクエスト（`quests`）、ログインボーナスのカレンダー（`loginCalendar`）、今日のプレイ時間（`playtime`）、通知の許可の画面を今出すか（`notifyPromptDue`：D-196。"firstReturn" / "loginDay2" / nil。状態の要約の `notifyPromptDue` にも入れて送る）。UIとCLIは計算をここに任せ、自前で式を持たない。
