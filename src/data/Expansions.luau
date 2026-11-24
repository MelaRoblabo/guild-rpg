--!strict
-- 拡張（ゲーム仕様書08章 §4、Q-018 仮採用、D-071）
-- steps は順に購入する。value＝購入後の値、guildLevel＝必要なギルドレベル、gold＝費用
-- requiresClear＝そのダンジョンの踏破が必要（パーティ枠：所要時間÷パーティ数≒30秒になる時点で開く。D-075）
-- trainingLevel＝トレーニング場（D-077。各レベルの効果は Constants.trainingFacility）
-- 金額は仮。tools/autoplay の実測で調整する（docs/reports/M5_economy.md）

return {
	{
		id = "exp_party",
		name = "パーティ枠",
		nameEn = "Party Slot",
		kind = "partySlots",
		steps = {
			{ value = 2, guildLevel = 1, gold = 3000, requiresClear = "dng_ruins" },
			{ value = 3, guildLevel = 1, gold = 30000, requiresClear = "dng_sunken_temple" },
			{ value = 4, guildLevel = 1, gold = 300000, requiresClear = "dng_abbey" },
			{ value = 5, guildLevel = 1, gold = 3000000, requiresClear = "dng_demon_gate" },
		},
	},
	{
		id = "exp_candidate",
		name = "雇用候補枠",
		nameEn = "Candidate Slot",
		kind = "candidateSlots",
		steps = {
			{ value = 4, guildLevel = 10, gold = 10000 },
			{ value = 5, guildLevel = 30, gold = 150000 },
			{ value = 6, guildLevel = 50, gold = 1500000 },
		},
	},
	{
		id = "exp_roster",
		name = "所属枠",
		nameEn = "Roster Slot",
		kind = "rosterSize",
		steps = {
			{ value = 12, guildLevel = 3, gold = 2000 },
			{ value = 16, guildLevel = 10, gold = 8000 },
			{ value = 20, guildLevel = 20, gold = 40000 },
			{ value = 24, guildLevel = 30, gold = 150000 },
			{ value = 28, guildLevel = 40, gold = 500000 },
			{ value = 32, guildLevel = 50, gold = 1200000 },
			{ value = 36, guildLevel = 60, gold = 2500000 },
			{ value = 40, guildLevel = 70, gold = 5000000 },
		},
	},
	{
		id = "exp_warehouse",
		name = "倉庫",
		nameEn = "Warehouse",
		kind = "warehouseSize",
		steps = {
			{ value = 400, guildLevel = 5, gold = 10000 }, -- D-091：解錠技術の廃止分を上乗せ
			{ value = 500, guildLevel = 15, gold = 30000 },
			{ value = 600, guildLevel = 25, gold = 120000 },
			{ value = 700, guildLevel = 35, gold = 400000 },
			{ value = 800, guildLevel = 45, gold = 1000000 },
			{ value = 900, guildLevel = 55, gold = 2500000 },
			{ value = 1000, guildLevel = 65, gold = 5000000 },
		},
	},
	{
		id = "exp_training",
		name = "トレーニング場",
		nameEn = "Training Grounds",
		kind = "trainingLevel",
		steps = {
			-- D-091：解錠技術（D-088、廃止）の費用を上乗せ
			{ value = 2, guildLevel = 10, gold = 70000 },
			{ value = 3, guildLevel = 30, gold = 600000 },
			{ value = 4, guildLevel = 50, gold = 4500000 },
			{ value = 5, guildLevel = 70, gold = 25000000 },
		},
	},
}
