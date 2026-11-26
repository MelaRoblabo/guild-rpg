# 03 プレイヤー状態（セーブデータ）

プレイヤー1人分の状態。これがそのままセーブデータになる（M7でDataStoreに保存）。JSONにできる値だけを持つ（関数・インスタンス禁止）。

```lua
export type StatBlock = { str: number, mag: number, agi: number, dex: number, hp: number }

export type Adventurer = {
	uid: string,              -- "adv_<連番>" 一意。再利用しない
	uniqueId: string?,        -- ユニークキャラならマスターID（D-055）
	name: string,
	appearanceId: string,     -- 例 "chr_m_bea_phy_01"（D-042）
	gender: "m" | "f",        -- 引き直しでも固定（D-051）
	jobId: string,            -- 例 "job_warrior"
	level: number,
	levelCap: number,
	exp: number,
	rebirthCount: number,
	baseStats: StatBlock,     -- 素の値（装備・ギフト補正を含まない）
	giftIds: { string },      -- 最大4（D-024）
	equipment: { weapon: string?, armor: string?, sub: string? }, -- 武器・防具・補助（盾/アクセサリー）。装備個体の uid
	locked: boolean,          -- 保護（お気に入り）
	hiredAt: number,
}

export type EquipmentItem = {
	uid: string,              -- "eq_<連番>"
	baseId: string,           -- 基本アイテムID
	rarity: number,           -- 1=コモン … 6=ミシック（増やせる：D-085）
	grade: number,            -- 0〜3
	modifierId: string?,
	modifierValue: number?,
	equippedBy: string?,      -- 冒険者 uid
	locked: boolean,
	fromMerchant: boolean?,   -- 旅の商人で買った装備。一括売却・自動売却で売らない（D-152, D-175）。M7b-4 の段階で追加（version はその段階で上げる）
}

-- 宝箱（D-084, D-166）：倉庫とは別の「宝箱置き場」。1個ずつの記録は持たず、宝箱の山×ランクの数だけ。上限なし
-- 宝箱の山の鍵（pileKey）：普通のダンジョンの宝箱は dungeonId、特別な宝箱は "special:<種類>"（例 "special:raid"。D-166）
--   レアダンジョンの宝箱は "special:rare:<相当するダンジョンの id>"（1段上のダンジョン。最深部の踏破後は天空の玉座のまま。中身はそのダンジョンの表：D-171, D-185）
-- ランクはサーバーだけが知る。クライアント・画面に渡すのは宝箱の山ごとの合計だけ（D-087）
-- 例：chests = { dng_ruins = { 12, 4, 1, 0, 0 }, ["special:raid"] = { 0, 0, 2 } }
--     … 罠の遺跡の宝箱がコモン12・アンコモン4・レア1、レイドのレアな宝箱がレア2
export type ChestCounts = { [string]: { number } }  -- pileKey → ランク1からの数（配列。出た最上位ランクまでの長さ。D-085）

export type Party = {
	index: number,                    -- 1〜（解放済みパーティ枠）
	slots: { string },                -- 隊列1〜4の冒険者 uid（D-035）。空き枠は ""（JSON/DataStore で穴あき配列にしないため）
	autoRepeat: { dungeonId: string }?, -- 自動再派遣の設定
	lastDungeonId: string?,           -- 最後の行き先（普通の派遣で出発したときに書く。マップイベントへの派遣は書かない）。「同じ所へ再出発」の行き先（D-228）。version 12
}

export type Expedition = {
	uid: string,
	partyIndex: number,
	dungeonId: string,
	seed: number,
	departAt: number,
	returnAt: number,
	log: ExpeditionLog,               -- 07章。出発時に確定し変更しない
	collected: boolean,
	offline: boolean?,                -- 留守番の探索（D-161）。クエストに数えない・休息ボーナスを使わない。M7b-3（version 7）で追加
	dailyTraitId: string?,            -- 出発時に当たっていた日替わりの特性（D-156）。留守番も出発した日の特性。M7b-3（version 7）で追加
	eventSlot: number?,               -- マップイベントへの派遣なら、そのイベントの時間帯の番号（D-152、06章 §12）
	raidDamage: number?,              -- レイドへの派遣なら、出発時に計算したダメージ（到着時刻に入れる。D-152）
	merchant: boolean?,               -- 旅の商人への派遣（D-274）。placeId（行き先の場所）・arriveAt（着く時刻）・leaveAt（帰り始めた時刻。まだなら nil）・
	                                  --   dungeonIds（派遣したときの品の候補のダンジョン）・bought（買った品の番号）を持つ。log は floors なし、
	                                  --   replaySeconds＝とどまる長さ（Leave までは merchantStayMaxSeconds、Leave で縮める）
	arriveAt: number?,                -- レイドへの派遣なら、ボスに着く時刻（出発 + raidTravelSeconds。06章 §12）
	raidArrived: boolean?,            -- レイドのダメージを入れ終わった
	chestPile: string?,               -- レアダンジョンへの派遣なら、宝箱の山の鍵 special:rare:<相当するダンジョン>（D-171, D-185）
}

-- 受け取り箱（D-164）：クエスト・プレイ時間・ログインボーナス・レイドなどの報酬の受け取り口。フレンドボタンの報酬は入れない（D-157）
-- 受け取れない報酬（所属枠・倉庫がいっぱいなど）は受け取り箱に残す。期限はない（D-176）
export type InboxEntry = {           -- version 8（M7b-4）
	uid: string,                      -- "inb_<連番>"（nextUid から）
	source: "quest" | "playtime" | "login" | "raid" | "referral",  -- referral は紹介の届け物（D-180）
	at: number,                       -- 届いた時刻（ctx.now。クエストは達成した行動の時刻）
	rewards: {
		gold: number?,                 -- 額。マスターデータの goldMult から届いたときの踏破で決める（D-190、06章 §22）
		items: { [string]: number }?,  -- チケット・ポーション（売却用アイテムは報酬にしない）
		chests: { { pileKey: string, rank: number, count: number } }?,  -- ランクは届いたときに SpecialChests の表で決める（D-166）。山×ランクでまとめ、ランクの低い順
		uniqueId: string?,             -- ログインボーナス7日目のユニーク（D-155）
	},
}
-- まとめて受け取る（ClaimInbox）とき：ゴールド・アイテム・宝箱はいつでも受け取る（宝箱は宝箱の山へ）。
-- ユニークは所属枠に空きがあるときだけ加入し、なければその件に uniqueId だけを残す（D-176）。
-- 受け取り箱の宝箱のランクはクライアントに送らない（Protocol.view は山ごとの数に直す：D-087）

export type QuestEntry = {           -- D-153。version 8（M7b-4）
	questId: string,                  -- マスターデータ Quests の id
	target: number,                   -- 量（パーティ数から決めた値。06章 §15）
	progress: number,
	done: boolean,                    -- 達成済み（報酬は達成時に受け取り箱へ）
}

export type HireSession = {          -- 面接中の状態（再接続での引き直し逃れ防止）
	candidates: { Candidate },
	pickedIndex: number?,
	previousRoll: StatBlock?,
	currentRoll: StatBlock?,
	freeRerollsLeft: number,
}

export type RebirthSession = {       -- 転生スロット中の状態
	adventurerUid: string,
	inherited: StatBlock,             -- 固定の1/2（端数切り捨て、Q-009）
	previousBonus: StatBlock?,
	currentBonus: StatBlock,
	freeRerollsLeft: number,
	newAppearanceId: string?,         -- 旧版の途中のセッションだけ（始めるときに見た目を決めていた）。今は持たない（D-230）
}

export type PlayerState = {
	version: number,                  -- セーブ形式の版
	seed: number,                     -- プレイヤー固有の乱数の元
	rngCounter: number,               -- 乱数を使うたびに進める（08章）
	nextUid: number,
	gold: number,
	guild: { level: number, exp: number },
	expansions: {
		partySlots: number, candidateSlots: number, rosterSize: number, warehouseSize: number,
		trainingLevel: number, -- トレーニング場のレベル（D-077、初期1）
	},                         -- version 2 で trainingLevel・unlockRank を追加（Migration v1→v2）
	adventurers: { [string]: Adventurer },
	parties: { Party },
	equipment: { [string]: EquipmentItem },
	chests: ChestCounts,       -- version 3 で一覧から数に変更（Migration v2→v3）。version 4 で unlockRank → unlockTier（v3→v4）、version 5 で解錠技術を削除（v4→v5、D-091）。version 6 で鍵を宝箱の山に広げる（v5→v6、D-166）
	items: { [string]: number },      -- アイテムID → 所持数（チケット・ポーション・売却用）
	expeditions: { [string]: Expedition },
	unlockedDungeons: { [string]: boolean },
	clearedDungeons: { [string]: boolean },   -- 初回踏破の判定
	hireSession: HireSession?,
	rebirthSession: RebirthSession?,
	rebirthAppearance: { adventurerUid: string, previousId: string, currentId: string }?, -- 転生の確定の後、見た目を選ぶ間（D-230。次の RebirthStart で新しい見た目のまま閉じる）
	appearanceSession: { adventurerUid: string, previousId: string, currentId: string }?, -- 見た目変更ポーションの選択中
	settings: {
		autoSell: { enabled: boolean, maxRarity: number, keepModified: boolean },
		                              -- 新規の初期値は enabled = true・maxRarity = 2（コモン・アンコモン）・keepModified = true（D-167）
		                              -- 商人で買った装備は自動売却しない（D-152。自動売却は開封時だけに働くので当たらない）
		notifyPrompt: { firstReturn: boolean, loginDay2: boolean },
		                              -- 通知の許可の画面を出した記録（D-196 ③。設定と一緒にサーバーへ保存：D-117）。version 11
		                              -- firstReturn：初めての帰還で出した / loginDay2：ログインボーナス2日目で出した。MarkNotifyPrompt で付ける
		guideStep: number?,           -- 初回の誘導（D-244 ①）の済んだ段の数。SetGuideStep で増える（戻らない）。
		                              -- なければ Game.query.guideStep が、帰還したことのあるセーブは全部済んだ扱い・ほかは 0 とする（移行なし）
	},
	stats: { [string]: number },      -- 集計用カウンタ（指標・実績）。クライアントには送らない
	                                  -- stats.rebirths：これまでに転生した回数の累計（RebirthChoose で +1。解雇で戻らない）。
	                                  --   紹介の進み具合はこれで数える（D-195）。version 11 で旧版の値を補う（下の移行）
	                                  -- stats.firstReturnAt：初めて探索が帰還した時刻（通知の許可の画面のきっかけ：D-196）
	lastAdvancedAt: number,
	itemLog: { ItemLogEntry },        -- 有料・無料の入手経路の記録（10章。直近N件）

	-- ここから M7b-3 以降の段階で追加（D-152〜D-168。段階ごとに version を上げる：下の「セーブの移行」）
	lastSavedAt: number,              -- 最後に保存した時刻（ふつうはログアウト時刻）。サーバーが保存のときに ctx.now を書く（11章）。version 7
	                                  -- 留守の始まりは max(lastSavedAt, lastAdvancedAt)（D-161, D-193、06章 §13）
	restBonusSeconds: number,         -- 休息ボーナスの残り秒（D-161。上限 restBonusMaxSeconds）。version 7
	quests: {                         -- D-153。version 8
		daily: { dayIndex: number, entries: { QuestEntry }, bonusDone: boolean },
		weekly: { weekIndex: number, entries: { QuestEntry }, bonusDone: boolean },
	},                                -- 入れ替えるまでは dayIndex / weekIndex = -1、entries = 空
	login: {                          -- ログインボーナス（D-155）。version 8
		lastDayIndex: number,         -- 最後に進めた日の番号（同じ日に二度進めない）
		day: number,                  -- 次に受け取るカレンダーの位置 1〜7（受け取ったら1つ進める。途切れても戻らない）
		cycle: number,                -- 何周目か（1〜）。7日目のユニークを選ぶのに使う（7日目を受け取ったら +1）
	},
	playtime: {                       -- 今日のプレイ時間（D-154）。version 8
		dayIndex: number,             -- 日の区切りで 0 に戻す（ログアウトでは戻さない）
		seconds: number,              -- 今日のオンラインの合計秒（上限 playtimeDailyCapSeconds）
		claimedSteps: number,         -- 受け取り箱へ送った段階の数
	},
	friend: {                         -- フレンドボタン（D-157）。version 9
		nextAt: number,               -- 次に押せる時刻
		dayIndex: number, todayCount: number,  -- 1日の上限の数え方
	},
	referral: {                       -- 紹介（D-157, D-192）。version 9。他のプレイヤーの UserId を含む referredBy・rewardedInvitees・claimedDeliveries は Protocol.view で除く（D-192）
		referredBy: number?,          -- 招待した人の UserId（ReferredByPlayerId。新規のプレイヤー（初めての参加）のときだけサーバーが入れる：D-195）
		inviteeRewardDone: boolean,   -- 招待された側の報酬を渡したか（1回だけ。Friend.referralProgressReached（転生回数の累計：D-195）に届いてから：D-192）
		inviterDelivered: boolean,    -- 招待された側：招待した人へ届け物を書いたか（同じ招待で2回届けない。読み書きは Friend.inviterDelivered / markInviterDelivered。
		                              --   書くきっかけ：サーバーが Friend.referralProgressReached を見て判定する（D-192））
		rewardedInvitees: { [string]: boolean },  -- 招待した側：報酬を渡した相手の UserId（文字列キー）
		claimedDeliveries: { [string]: boolean }, -- 招待した側：受け取った届け物の id（例 "referral:<招待された人の UserId>"）。同じ id は二度受け取らない
		weekIndex: number, weekCount: number,     -- 招待した側の人数の上限（週）
	},                                -- 招待した側への報酬は「届け物」として別の保存場所に置き、次のログインで受け取り箱へ入れる（D-180。届け物そのものはこのセーブには書かない。詳細は M7b-5）
	merchant: { eventSlot: number }?,  -- 最後にパーティを送った旅の商人の時間帯（D-274：同じ商人へ2組目を送らない）。買ったもの・候補のダンジョンは派遣の記録（expeditions[*].bought・dungeonIds）に持つ。旧版の bought・dungeonIds は読まない
	                                  -- bought は品の数だけの配列（穴なし）。dungeonIds は最初に買ったときの候補のダンジョン（3分間のうちに踏破が進んでも品ぞろえを変えない：06章 §12）
	raid: { eventSlot: number, hp: number, damage: number, defeated: boolean, parties: { number }, arrived: number }?,  -- 今のレイドボスの進み具合（D-152。自分専用）。version 10
	                                  -- hp は最初に出発したときに決める。parties は出発したパーティ（1パーティ1回まで）、arrived は到着した数（宝箱の数に使う：D-179）
	rareDungeonSlots: { [string]: number }?,  -- レアダンジョンに出発したパーティ（partyIndex → eventSlot。1パーティ1回まで：D-152）。version 10
	inbox: { InboxEntry },            -- 受け取り箱（D-164）。version 8
	loginTimes: { number },           -- 直近のログイン時刻（1日の中の位置・秒。UTC 0時から）。古い順に notifyLoginHistoryCount（7）回まで（D-196）。version 11
	                                  -- サーバーがログイン（読み込み）のたびに Notify.recordLogin で足す。中央値が「いつも遊ぶ時刻」（06章 §23）。クライアントには送らない
}
```

## ルール

- `uid` は `nextUid` から払い出し、削除しても再利用しない。
- 配列に穴（nil）を作らない。DataStore は穴あき配列を保存できない。探索ログの hpAfter もメンバー順の配列。
- 冒険者・装備は辞書（uidキー）で持つ。将来の所有権移転（D-065）で、個体をそのまま移せる。
- 倉庫の使用量＝`equipment` のうち `equippedBy == nil` の数（Q-020）。
- 未開封宝箱は倉庫容量に含めない別枠（Q-020）。
- 形式を変えるときは `version` を上げ、`Migration.luau` に旧版からの変換を追加する。
- 日・週で区切る状態（`quests`・`login`・`playtime`・`friend`・`referral`）は、保存した `dayIndex`／`weekIndex` と `ctx.now` から出した番号（06章 §11）を比べて切り替える。時刻を自分で取らない（08章, D-168）。
- マップイベント・旅の商人・レイドの状態は「今のイベントの時間帯」の分だけ持つ。`eventSlot` が今のものと違えば古い分として捨てる（D-152）。
- 売却用アイテム（素材）は常に自動で売るので、`items` には入らない（D-167）。
- 専用ギフト（D-165）は状態の形を変えない。`giftIds` に入るギフトの1つで、専用かどうかはマスターデータ Gifts の印で見る（04章 §8）。

## セーブの移行（M7b は段階ごとに version を上げる）

D-152〜D-168 で足す状態は、まとめて1つの版にせず、**M7b の段階ごとに version を1つ上げる**（影響と修正リスト #8-1）。段階ごとにテストつきで動く形にするため。まだ公開前なので、どの段階も一番簡単な形にする（D-177）。

- `Migration.migrate(state, master)` にはマスターデータを渡す（売却価格・初期値を使う手順があるため）。master が無いと v5 → v6 で失敗し、状態は変えない。Roblox のサーバー（`src/server/PlayerSessions`）も master を渡す（2026-11-23 に対応済み）。

### version 5 → 6（M7b-2）　`Migration.CURRENT = 6`

| 項目 | 旧版からの変換 | 根拠 |
| --- | --- | --- |
| `chests` | 鍵は dungeonId のまま宝箱の山の鍵として扱う（変換しない） | D-166, D-177 |
| `settings.autoSell` | 初期値（StarterSet の `autoSell`：`enabled = true, maxRarity = 2, keepModified = true`）に合わせる | D-167, D-177 |
| `items` の売却用アイテム | 売ってゴールドにする（売却価格は今までと同じ `sellPrice × 数`）。`items` から消す | D-167, D-177 |

### version 6 → 7（M7b-3）　`Migration.CURRENT = 7`

| 項目 | 旧版からの変換 | 根拠 |
| --- | --- | --- |
| `lastSavedAt` | `lastAdvancedAt` を入れる（すでにあれば変えない） | D-161 |
| `restBonusSeconds` | 0 | D-161 |
| `expeditions[*]` | `offline`・`dailyTraitId` は nil のまま（旧版の探索は普通の探索で、日替わりの特性なし） | D-161, D-156 |

新規のセーブは `lastSavedAt = 作成時刻`、`restBonusSeconds = 0` を持つ。

### version 7 → 8（M7b-4 前半）　`Migration.CURRENT = 8`

| 項目 | 旧版からの変換 | 根拠 |
| --- | --- | --- |
| `quests` | `daily = { dayIndex = -1, entries = {}, bonusDone = false }`, `weekly = { weekIndex = -1, entries = {}, bonusDone = false }`（次のオンラインの advance で今日・今週の分を作る） | D-153 |
| `login` | `lastDayIndex = -1, day = 1, cycle = 1`（次のオンラインの advance で1日目） | D-155 |
| `playtime` | `dayIndex = -1, seconds = 0, claimedSteps = 0` | D-154 |
| `inbox` | 空 | D-164 |

新規のセーブも同じ初期値を持つ（`Game.newState`）。

### version 8 → 9（M7b-4 後半の担当A）　`Migration.CURRENT = 9`

| 項目 | 旧版からの変換 | 根拠 |
| --- | --- | --- |
| `friend` | `nextAt = 0, dayIndex = -1, todayCount = 0` | D-157 |
| `referral` | `inviteeRewardDone = false, inviterDelivered = false, rewardedInvitees = {}, claimedDeliveries = {}, weekIndex = -1, weekCount = 0`（`referredBy` は nil。サーバーが入れる） | D-157, D-180 |
| ユニークの冒険者 | `exclusiveGiftId` のギフトを `giftIds` に足す。ギフトの枠（giftMax）がいっぱいなら一番古いギフト（`giftIds` の先頭）と入れ替える（その位置に置く）。今は専用ギフトを持つユニークがいないので何も変わらない | D-165, D-177, D-185 |

新規のセーブも同じ初期値を持つ（`Game.newState`）。移行には master が要る（無ければ何も変えずに失敗する）。ユニークは雇用・初回踏破・受け取り箱のどれで加入しても、加入したときに専用ギフトを持つ（`Hiring.newAdventurer`）。

### version 9 → 10（M7b-4 後半の担当B。マップイベント）　`Migration.CURRENT = 10`

担当A（今週の訪問者・専用ギフト・フレンド：v8 → 9）と同時に作業したため、まとめるときに v8 → 9 から振り直した。

| 項目 | 旧版からの変換 | 根拠 |
| --- | --- | --- |
| `expeditions[*]` | `eventSlot`・`raidDamage`・`arriveAt`・`raidArrived`・`chestPile` は nil（旧版の探索は普通の探索） | D-152 |
| `equipment[*]` | `fromMerchant` は nil | D-175 |
| `merchant`・`raid`・`rareDungeonSlots` | nil | D-152 |

### version 10 → 11（M7b-5 の決定 D-195・D-196 の反映）　`Migration.CURRENT = 11`

| 項目 | 旧版からの変換 | 根拠 |
| --- | --- | --- |
| `stats.rebirths` | 今いる冒険者の `rebirthCount` の合計を下限にする（`max(今の stats.rebirths, 合計)`。すでに数えている累計のほうが大きければそのまま＝解雇した冒険者の分を失わない） | D-195 |
| `loginTimes` | 空（次のログインからサーバーが足す） | D-196 |
| `settings.notifyPrompt` | `firstReturn = false, loginDay2 = false`（まだ出していない） | D-196, D-117 |

新規のセーブも同じ初期値を持つ（`Game.newState`。`stats.rebirths` は最初の転生で 1 になる）。

### version 11 → 12（M8-2 の決定 D-228）　`Migration.CURRENT = 12`

| 項目 | 旧版からの変換 | 根拠 |
| --- | --- | --- |
| `parties[*].lastDungeonId` | 今いる普通の探索があればその行き先、なければ自動再派遣の行き先、どちらもなければ nil | D-228 |

新規のセーブは nil（最初の派遣で書く）。

### version 12 → 13 以降

まだ足していない項目は今はない。次の段階で状態を足すときは、ここに表（項目・旧版からの変換・根拠・足す段階）を作ってから version を上げ、足した段階でこの表を「version n → n+1」の節に移す。

新規のセーブ（`Game.newState`）は、その時点の version で足した項目を初期値で持ち、`settings.autoSell` は StarterSet の D-167 の初期値（オン）にする。
