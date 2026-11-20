--!strict
-- ダンジョン（ゲーム仕様書05章、docs/system/04_master_data.md §4）
-- 数値はすべて仮（Q-003, Q-004, Q-017）。M1 のシミュレーターで調整する。
-- base: 1体目のモンスターの HP・攻撃力・物理防御・魔法防御（D-003）
-- monsters / bosses: 出現の重み。最終フロアは bosses から抽選（Q-020）
-- battleReward: 戦闘1回の経験値・ゴールド（強さ倍率を掛ける）
-- minChestRank: 宝箱ランク抽選の起点（D-015）
-- sellableItems: アイテムイベントで「売却用」が出たときの抽選（D-016）
-- jobPotionTargets: レア以上の宝箱から出る転職ポーションの対象（D-058）
-- modifierPool: 宝箱の装備に付く修飾語の候補（06章）
-- unlockAfterClear: このダンジョンの初回踏破で解放（Q-017）。nil なら最初から解放

return {
	{
		id = "dng_graveyard",
		name = "古い墓地",
		floors = 7,
		distance = 3,
		terrainTags = { "outdoor" },
		base = { hp = 60, atk = 14, pdef = 4, mdef = 4 },
		monsters = {
			{ id = "mon_skeleton", weight = 3 },
			{ id = "mon_ghost", weight = 3 },
			{ id = "mon_ghoul", weight = 2 },
			{ id = "mon_giant_rat", weight = 2 },
		},
		bosses = { { id = "mon_bone_lord", weight = 1 } },
		trapLevel = 1,
		minChestRank = 1,
		battleReward = { exp = 10, gold = 15 },
		sellableItems = { { id = "itm_bone_fragment", weight = 1 } },
		jobPotionTargets = { "job_priest", "job_bishop" },
		modifierPool = { "mod_exorcism", "mod_healing" },
		unlockAfterClear = nil,
	},
	{
		id = "dng_ruins",
		name = "罠の遺跡",
		floors = 9,
		distance = 5,
		terrainTags = { "outdoor" },
		base = { hp = 90, atk = 18, pdef = 6, mdef = 5 },
		monsters = {
			{ id = "mon_ruin_wolf", weight = 4 },
			{ id = "mon_clay_golem", weight = 4 },
			{ id = "mon_imp", weight = 2 },
		},
		bosses = { { id = "mon_stone_guardian", weight = 1 } },
		trapLevel = 3,
		minChestRank = 1,
		battleReward = { exp = 14, gold = 20 },
		sellableItems = { { id = "itm_old_gear", weight = 1 } },
		jobPotionTargets = { "job_thief", "job_ninja" },
		modifierPool = { "mod_trapward", "mod_swift" },
		unlockAfterClear = "dng_graveyard",
	},
	{
		id = "dng_tower",
		name = "封印の塔",
		floors = 11,
		distance = 7,
		terrainTags = { "indoor" },
		base = { hp = 120, atk = 22, pdef = 6, mdef = 14 },
		monsters = {
			{ id = "mon_wisp", weight = 4 },
			{ id = "mon_gargoyle", weight = 3 },
			{ id = "mon_shade_sorcerer", weight = 3 },
		},
		bosses = { { id = "mon_sealed_archmage", weight = 1 } },
		trapLevel = 2,
		minChestRank = 2,
		battleReward = { exp = 18, gold = 26 },
		sellableItems = { { id = "itm_magic_shard", weight = 1 } },
		jobPotionTargets = { "job_mage", "job_sage" },
		modifierPool = { "mod_healing", "mod_swift" },
		unlockAfterClear = "dng_ruins",
	},
	{
		id = "dng_castle",
		name = "騎士の古城",
		floors = 13,
		distance = 9,
		terrainTags = { "indoor" },
		base = { hp = 170, atk = 26, pdef = 16, mdef = 8 },
		monsters = {
			{ id = "mon_cursed_knight", weight = 5 },
			{ id = "mon_armored_hound", weight = 4 },
			{ id = "mon_dark_chaplain", weight = 1 },
		},
		bosses = { { id = "mon_fallen_lord", weight = 1 } },
		trapLevel = 2,
		minChestRank = 2,
		battleReward = { exp = 24, gold = 34 },
		sellableItems = { { id = "itm_knight_crest", weight = 1 } },
		jobPotionTargets = { "job_warrior", "job_knight" },
		modifierPool = { "mod_exorcism", "mod_trapward" },
		unlockAfterClear = "dng_tower",
	},
}
