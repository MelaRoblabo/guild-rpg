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
}

-- 宝箱（D-084）：倉庫とは別の「宝箱置き場」。1個ずつの記録は持たず、ダンジョン×ランクの数だけ。上限なし
-- ランクはサーバーだけが知る。クライアント・画面に渡すのはダンジョンごとの合計だけ（D-087）
-- 例：chests = { dng_ruins = { 12, 4, 1, 0, 0 } }  … 罠の遺跡の宝箱がコモン12・アンコモン4・レア1
export type ChestCounts = { [string]: { number } }  -- dungeonId → ランク1からの数（配列。出た最上位ランクまでの長さ。D-085）

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
		unlockTier: number,    -- 解錠技術：開けられる宝箱のダンジョンの難度の上限（D-088、初期2）
	},                         -- version 2 で trainingLevel・unlockRank を追加（Migration v1→v2）
	adventurers: { [string]: Adventurer },
	parties: { Party },
	equipment: { [string]: EquipmentItem },
	chests: ChestCounts,       -- version 3 で一覧から数に変更（Migration v2→v3）。version 4 で unlockRank → unlockTier（v3→v4）
	items: { [string]: number },      -- アイテムID → 所持数（チケット・ポーション・売却用）
	expeditions: { [string]: Expedition },
	unlockedDungeons: { [string]: boolean },
	clearedDungeons: { [string]: boolean },   -- 初回踏破の判定
	hireSession: HireSession?,
	rebirthSession: RebirthSession?,
	appearanceSession: { adventurerUid: string, previousId: string, currentId: string }?, -- 見た目変更ポーションの選択中
	settings: { autoSell: { enabled: boolean, maxRarity: number } },
	stats: { [string]: number },      -- 集計用カウンタ（指標・実績）
	lastAdvancedAt: number,
	itemLog: { ItemLogEntry },        -- 有料・無料の入手経路の記録（10章。直近N件）
}
```

## ルール

- `uid` は `nextUid` から払い出し、削除しても再利用しない。
- 配列に穴（nil）を作らない。DataStore は穴あき配列を保存できない。探索ログの hpAfter もメンバー順の配列。
- 冒険者・装備は辞書（uidキー）で持つ。将来の所有権移転（D-065）で、個体をそのまま移せる。
- 倉庫の使用量＝`equipment` のうち `equippedBy == nil` の数（Q-020）。
- 未開封宝箱は倉庫容量に含めない別枠（Q-020）。
- 形式を変えるときは `version` を上げ、`Migration.luau` に旧版からの変換を追加する。
