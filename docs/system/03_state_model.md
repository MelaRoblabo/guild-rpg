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
	fromMerchant: boolean?,   -- 旅の商人で買った装備。一括売却・自動売却で売らない（D-152, D-175）。version 6 で追加
}

-- 宝箱（D-084, D-166）：倉庫とは別の「宝箱置き場」。1個ずつの記録は持たず、宝箱の山×ランクの数だけ。上限なし
-- 宝箱の山の鍵（pileKey）：普通のダンジョンの宝箱は dungeonId、特別な宝箱は "special:<種類>"（例 "special:raid"。D-166）
--   レアダンジョンの宝箱は "special:rare:<相当するダンジョンの id>"（1段上のダンジョン。中身はそのダンジョンの表：D-171）
-- ランクはサーバーだけが知る。クライアント・画面に渡すのは宝箱の山ごとの合計だけ（D-087）
-- 例：chests = { dng_ruins = { 12, 4, 1, 0, 0 }, ["special:raid"] = { 0, 0, 2 } }
--     … 罠の遺跡の宝箱がコモン12・アンコモン4・レア1、レイドのレアな宝箱がレア2
export type ChestCounts = { [string]: { number } }  -- pileKey → ランク1からの数（配列。出た最上位ランクまでの長さ。D-085）

export type Party = {
	index: number,                    -- 1〜（解放済みパーティ枠）
	slots: { string },                -- 隊列1〜4の冒険者 uid（D-035）。空き枠は ""（JSON/DataStore で穴あき配列にしないため）
	autoRepeat: { dungeonId: string }?, -- 自動再派遣の設定
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
	offline: boolean?,                -- 留守番の探索（D-161）。クエストに数えない・休息ボーナスを使わない。version 6 で追加
	dailyTraitId: string?,            -- 出発時に当たっていた日替わりの特性（D-156）。留守番も出発した日の特性
	eventSlot: number?,               -- マップイベントへの派遣なら、そのイベントの時間帯の番号（D-152、06章 §12）
	raidDamage: number?,              -- レイドへの派遣なら、出発時に計算したダメージ（到着時刻に入れる。D-152）
}

-- 受け取り箱（D-164）：クエスト・プレイ時間・ログインボーナス・レイドなどの報酬の受け取り口。フレンドボタンの報酬は入れない（D-157）
-- 受け取れない報酬（所属枠・倉庫がいっぱいなど）は受け取り箱に残す。期限はない（D-176）
export type InboxEntry = {
	uid: string,                      -- "inb_<連番>"（nextUid から）
	source: "quest" | "playtime" | "login" | "raid" | "referral",  -- referral は紹介の届け物（D-180）
	at: number,                       -- 届いた時刻（ctx.now）
	rewards: {
		gold: number?,
		items: { [string]: number }?,  -- チケット・ポーション
		chests: { { pileKey: string, rank: number, count: number } }?,
		uniqueId: string?,             -- ログインボーナス7日目のユニーク（D-155）
	},
}

export type QuestEntry = {           -- D-153
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
	newAppearanceId: string,
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
	appearanceSession: { adventurerUid: string, previousId: string, currentId: string }?, -- 見た目変更ポーションの選択中
	settings: { autoSell: { enabled: boolean, maxRarity: number, keepModified: boolean } },
	                                  -- 新規の初期値は enabled = true・maxRarity = 2（コモン・アンコモン）・keepModified = true（D-167）
	                                  -- 商人で買った装備は自動売却しない（D-152。自動売却は開封時だけに働くので当たらない）
	stats: { [string]: number },      -- 集計用カウンタ（指標・実績）
	lastAdvancedAt: number,
	itemLog: { ItemLogEntry },        -- 有料・無料の入手経路の記録（10章。直近N件）

	-- ここから version 6 で追加（D-152〜D-168。Migration v5→v6）
	lastSavedAt: number,              -- 最後に保存した時刻＝ログアウト時刻。留守の計算の基準（D-161）。サーバーが保存のときに ctx.now を書く（11章）
	restBonusSeconds: number,         -- 休息ボーナスの残り秒（D-161。上限 restBonusMaxSeconds）
	quests: {                         -- D-153
		daily: { dayIndex: number, entries: { QuestEntry }, bonusDone: boolean },
		weekly: { weekIndex: number, entries: { QuestEntry }, bonusDone: boolean },
	},
	login: {                          -- ログインボーナス（D-155）
		lastDayIndex: number,         -- 最後に進めた日の番号（同じ日に二度進めない）
		day: number,                  -- カレンダーの位置 1〜7（途切れても戻らない）
		cycle: number,                -- 何周目か（1〜）。7日目のユニークを選ぶのに使う
	},
	playtime: {                       -- 今日のプレイ時間（D-154）
		dayIndex: number,             -- 日の区切りで 0 に戻す（ログアウトでは戻さない）
		seconds: number,              -- 今日のオンラインの合計秒（上限 playtimeDailyCapSeconds）
		claimedSteps: number,         -- 受け取り箱へ送った段階の数
	},
	friend: {                         -- フレンドボタン（D-157）
		nextAt: number,               -- 次に押せる時刻
		dayIndex: number, todayCount: number,  -- 1日の上限の数え方
	},
	referral: {                       -- 紹介（D-157）
		referredBy: number?,          -- 招待した人の UserId（ReferredByPlayerId。サーバーが入れる）
		inviteeRewardDone: boolean,   -- 招待された側の報酬を渡したか（1回だけ）
		rewardedInvitees: { [string]: boolean },  -- 招待した側：報酬を渡した相手の UserId（文字列キー）
		weekIndex: number, weekCount: number,     -- 招待した側の人数の上限（週）
	},                                -- 招待した側への報酬は「届け物」として別の保存場所に置き、次のログインで受け取り箱へ入れる（D-180。このセーブには書かない。詳細は M7b-5）
	merchant: { eventSlot: number, bought: { boolean } }?,  -- 今の旅の商人の品のうち買ったもの（D-152）。品ぞろえは eventSlot と seed から決まるので保存しない
	raid: { eventSlot: number, damage: number, defeated: boolean }?,  -- 今のレイドボスの進み具合（D-152。自分専用）
	rareDungeonSlots: { [string]: number }?,  -- レアダンジョンに出発したパーティ（partyIndex → eventSlot。1パーティ1回まで：D-152）
	inbox: { InboxEntry },            -- 受け取り箱（D-164）
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

## セーブの移行（version 5 → 6、M7b-2）

D-152〜D-168 で足す状態をまとめて version 6 にする（影響と修正リスト #8-1）。`Migration.CURRENT = 6`。まだ公開前なので、一番簡単な形にする（D-177）。

| 項目 | 旧版からの変換 | 根拠 |
| --- | --- | --- |
| `chests` | 鍵は dungeonId のまま宝箱の山の鍵として扱う（変換しない） | D-166, D-177 |
| `expeditions[*]` | `offline`・`dailyTraitId`・`eventSlot`・`raidDamage` は nil（旧版の探索は普通の探索） | D-161, D-156, D-152 |
| `equipment[*]` | `fromMerchant` は nil | D-175 |
| `lastSavedAt` | `lastAdvancedAt` を入れる | D-161 |
| `restBonusSeconds` | 0 | D-161 |
| `quests` | 空（次の advance で今日・今週の分を作る） | D-153 |
| `login` | `lastDayIndex = -1, day = 1, cycle = 1`（次のオンラインの advance で1日目） | D-155 |
| `playtime` | `dayIndex = -1, seconds = 0, claimedSteps = 0` | D-154 |
| `friend` | `nextAt = 0, dayIndex = -1, todayCount = 0` | D-157 |
| `referral` | `inviteeRewardDone = false, rewardedInvitees = {}, weekIndex = -1, weekCount = 0` | D-157 |
| `merchant`・`raid`・`rareDungeonSlots` | nil | D-152 |
| `inbox` | 空 | D-164 |
| `settings.autoSell` | 初期値（`enabled = true, maxRarity = 2, keepModified = true`）に合わせる | D-167, D-177 |
| `items` の売却用アイテム | 売ってゴールドにする（売却価格は今までと同じ） | D-167, D-177 |
| ユニークの冒険者 | `exclusiveGiftId` のギフトを `giftIds` に足す。ギフトの枠（giftMax）がいっぱいなら一番古いギフト（`giftIds` の先頭）と入れ替える | D-165, D-177 |

新規のセーブ（StarterSet）は上の新しい項目を初期値で持ち、`settings.autoSell` は D-167 の初期値（オン）にする。
