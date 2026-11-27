--!strict
-- バランスの目標の表（MB。docs/system/04_master_data.md §13、決定 D-291〜D-296）
-- ゲームの動きには使わない。成績表のツール（tools/balance）がこの表だけを読んで合否を出す。
-- 目標を変えるときは、先に決定ログを変え、この表を直す（ツールの中に目標の値を書かない）。
--
-- 各行：
--   id       : 目標のID（bal_ で始まる）
--   decision : 根拠の決定ID（複数は「D-160・D-200」のように並べる）
--   name     : 成績表に出す名前
--   source   : 測る道具。"autoplay"（1日の流れ。09章 §3）／"sim"（探索シミュレーター。09章 §2）
--   metric   : 道具が出す指標の名前（tools/balance/Metrics.luau が計算する）
--   judge    : 判定の仕方
--     "near"     : 平均が value の ±tol（割合）に入る。tolAbs があれば絶対値の幅
--     "atLeast"  : 平均（sim は各ダンジョンの値）が value 以上
--     "atMost"   : 平均（sim は各ダンジョンの値）が value 以下
--     "share"    : 入手先の配分（%）。columns の各列が ±tolPt（ポイント）に入る。列を書かない入手先は判定しない
--     "baseline" : 合否の線を置かず、保存した基準の値から大きくずれたら警告する（D-295）
--   value    : near・atLeast・atMost の値。型ごとに違うときは byProfile、ダンジョンごとに違うときは byDungeon（value より優先）
--   profiles : 測る型（"light"・"core"・"heavy"）。autoplay だけ
--   friends  : 友達の数（ctx.friendCount）。省略すると 0
--
-- 配分の列：adventure（冒険。留守番を含む：D-200）・quest・login・playtime・friend・mapevent・guild

return {
	-- 判定に使う seed の数（D-291：5つの seed の平均）
	seeds = 5,

	targets = {
		-- 進行速度
		{
			id = "bal_days_to_max_growth",
			decision = "D-161・D-199・D-291・D-299",
			name = "最大の育成までの暦日数",
			source = "autoplay",
			metric = "daysToMaxGrowth",
			judge = "near",
			byProfile = { light = 110, core = 30, heavy = 15 }, -- ライトは D-299（D-280 の後の実測から）
			tol = 0.10,
			profiles = { "light", "core", "heavy" },
		},
		{
			id = "bal_milestones",
			decision = "D-295",
			name = "途中の目安の日（初めての転生・パーティ枠・ダンジョンの解放）",
			source = "autoplay",
			metric = "milestoneDays",
			judge = "baseline",
			profiles = { "light", "core", "heavy" },
		},

		-- オンラインと留守番（D-292：経験値は外し、留守番が動く6時間までの分で割る）
		{
			id = "bal_online_ratio_gold",
			decision = "D-161・D-292",
			name = "1時間あたりの価値 オンライン÷留守番：ゴールド（探索）",
			source = "autoplay",
			metric = "onlineRatioGold",
			judge = "atLeast",
			value = 10,
			profiles = { "light", "core", "heavy" },
		},
		{
			id = "bal_online_ratio_chests",
			decision = "D-161・D-200・D-292",
			name = "1時間あたりの価値 オンライン÷留守番：宝箱（レイドの宝箱込み）",
			source = "autoplay",
			metric = "onlineRatioChests",
			judge = "atLeast",
			value = 10,
			profiles = { "light", "core", "heavy" },
		},

		-- 経済
		{
			id = "bal_gold_pileup",
			decision = "D-163・D-296",
			name = "ゴールドの積み上がり（最後の転生までの 残高÷その日の収入 の最大）",
			source = "autoplay",
			metric = "maxBalanceDays",
			judge = "atMost",
			value = 3,
			profiles = { "light", "core", "heavy" },
		},
		{
			id = "bal_merchant_good",
			decision = "D-204",
			name = "旅の商人の品のうち「誰かの今の装備より良い品」の割合",
			source = "autoplay",
			metric = "merchantGoodShare",
			judge = "near",
			value = 0.15,
			tolAbs = 0.05, -- 仮（判定の幅は決定なし。D-204 は「約15%」）
			profiles = { "core" },
		},

		-- 報酬の入手先の配分（コアで合わせる：D-200）
		{
			id = "bal_share_gold",
			decision = "D-160・D-200・D-205",
			name = "入手先の配分：ゴールド（直接）",
			source = "autoplay",
			metric = "shareGold",
			judge = "share",
			columns = { adventure = 65, quest = 10, login = 5, playtime = 10, mapevent = 5 },
			tolPt = 5, -- 仮（判定の幅は決定なし）
			profiles = { "core" },
		},
		{
			id = "bal_share_chests",
			decision = "D-160・D-200",
			name = "入手先の配分：宝箱",
			source = "autoplay",
			metric = "shareChests",
			judge = "share",
			columns = { adventure = 70, quest = 10, login = 5, playtime = 5, mapevent = 10 },
			tolPt = 5, -- 仮
			profiles = { "core" },
		},
		{
			id = "bal_share_tickets",
			decision = "D-160・D-200",
			name = "入手先の配分：ステータススロットチケット",
			source = "autoplay",
			metric = "shareTickets",
			judge = "share",
			columns = { adventure = 10, quest = 45, login = 15, playtime = 5, guild = 25 },
			tolPt = 5, -- 仮
			profiles = { "core" },
		},
		{
			id = "bal_share_tools",
			decision = "D-160・D-178・D-255・D-293",
			name = "入手先の配分：指南書・手鏡・ロケット",
			source = "autoplay",
			metric = "shareTools",
			judge = "share",
			columns = { adventure = 50, quest = 20, login = 20, mapevent = 10 }, -- ギルドLvの分（D-178）は判定しない
			tolPt = 5, -- 仮
			profiles = { "core" },
		},
		{
			id = "bal_tools_total",
			decision = "D-298",
			name = "指南書・手鏡・ロケットの1日あたりの数（コアで約20個）",
			source = "autoplay",
			metric = "toolsPerDay",
			judge = "near",
			value = 20,
			tol = 0.20, -- 仮（D-298 は「約20個」）
			profiles = { "core" },
		},
		{
			id = "bal_friend_gold",
			decision = "D-157・D-160",
			name = "フレンドのゴールドの割合（友達1人）",
			source = "autoplay",
			metric = "friendGoldShare",
			judge = "near",
			value = 5,
			tolAbs = 2, -- 仮
			profiles = { "core" },
			friends = 1,
		},

		-- レイド
		{
			id = "bal_raid_parties",
			decision = "D-179・D-203",
			name = "レイドの討伐に要ったパーティ数（1でときどき・2でたいてい）",
			source = "autoplay",
			metric = "raidPartiesNeeded",
			judge = "baseline",
			profiles = { "core" },
		},

		-- 探索（シミュレーター。段階のパーティは tools/sim/Stages.luau）
		{
			id = "bal_stage_clear",
			decision = "D-069",
			name = "想定段階のパーティでの踏破率（約60%。古い墓地は確実に宝箱を持ち帰る）",
			source = "sim",
			metric = "stageClearRate",
			judge = "near",
			value = 0.60,
			byDungeon = { dng_graveyard = 0.97 }, -- 01章：最初のダンジョンは確実に宝箱を持ち帰れること
			tolAbs = 0.10, -- 仮（D-069 は「約60%」）
		},
		{
			id = "bal_stage_time",
			decision = "D-067・D-069・D-097・D-098",
			name = "想定段階のパーティでの所要秒（中央値）",
			source = "sim",
			metric = "stageMedianSeconds",
			judge = "near",
			byDungeon = {
				dng_graveyard = 50, -- 最初の宝箱を1分以内に（D-067）
				dng_ruins = 65,
				dng_tower = 94,
				dng_castle = 106,
				dng_sunken_temple = 119,
				dng_mist_forest = 131,
				dng_labyrinth = 144,
				dng_abbey = 156,
				dng_iron_fortress = 165,
				dng_dragon_nest = 175,
				dng_demon_gate = 247, -- D-098：パーティ5つで帰還間隔約30秒
				dng_sky_throne = 265, -- D-098
			},
			tol = 0.10, -- 仮
		},
		{
			id = "bal_early_unlock_clear",
			decision = "D-279・D-294・D-300",
			name = "ゴールドで先に解放したダンジョンの踏破率（前のダンジョンで育てた、踏破の手前のパーティ）",
			source = "sim",
			metric = "earlyUnlockClearRate",
			judge = "atLeast",
			value = 0.30,
		},
	},
}
