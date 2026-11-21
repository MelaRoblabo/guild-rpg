--!strict
-- ダンジョンの設計テンプレート（D-068：ダンジョンを増やす、D-069：転生まで見据えたバランス）
-- tools/sim/calibrate.luau がこれを読み、強さ・距離・罠レベル・経験値をシミュレーションで決めて
-- src/data/Dungeons.luau を生成する。数値を手で直したいときは、ここの目標値を変えて再生成する。
--
-- stage        : 想定パーティの段階（tools/sim/Stages.luau の番号）
-- targetClear  : 想定パーティでの踏破率の目標
-- timeTarget   : 想定パーティでの所要秒の目標（難しいほど長く：D-069。実際の周回は想定より強い状態で回るため、
--                難度3以降は1.25倍に置く：D-075）
-- ratios       : モンスター基準値の比率（hp・atk・pdef・mdef）。全体の大きさは calibrate が決める
-- trapEvade    : 想定パーティの罠回避率の目標
-- chestRarityWeights : 宝箱のレアリティの出現率（%）。[1]=コモン …（D-085）。深いほど少しずつ上位が増える。
--                     書いていない上位のレアリティは0。レアリティを増やしたら必要なダンジョンに足す
-- chestEffectMinRarity : このレアリティ以上の宝箱は開けるとき演出が入る（D-089）。演出の派手さはレアリティで決まる
--                     演出が入る割合は Constants.chestEffectRate（10〜15%）に収める（D-090。検証でエラーになる）
-- dispatchFee  : 派遣費（D-079）。上級ダンジョンだけ。出発のたびにゴールドが減る（仮）

local BAL = { hp = 8, atk = 0.9, pdef = 0.4, mdef = 0.4 }
local ARMORED = { hp = 8, atk = 0.9, pdef = 1.0, mdef = 0.3 }
local ARCANE = { hp = 8, atk = 0.9, pdef = 0.3, mdef = 1.0 }
local BEAST = { hp = 7, atk = 1.1, pdef = 0.3, mdef = 0.3 }
local DRAGON = { hp = 11, atk = 1.0, pdef = 0.6, mdef = 0.6 }
-- D-092：魔法・物理への強さをはっきりさせる（M6 の編成比較で封印の塔は魔法、鋼鉄の要塞は物理が有利すぎた）
local ARCANE_STRONG = { hp = 8, atk = 0.9, pdef = 0.2, mdef = 1.6 }
local ARMORED_STRONG = { hp = 8, atk = 0.9, pdef = 1.6, mdef = 0.2 }

return {
	{
		id = "dng_graveyard",
		name = "古い墓地",
		stage = 1,
		targetClear = 0.97, -- 最初のダンジョンは確実に宝箱を持ち帰れること（01章）
		timeTarget = 50, -- 最初の宝箱を1分以内に（01章、D-067）
		floors = 7,
		terrainTags = { "outdoor" },
		ratios = BAL,
		trapEvade = 0.8,
		monsters = {
			{ id = "mon_skeleton", weight = 3 },
			{ id = "mon_ghost", weight = 3 },
			{ id = "mon_ghoul", weight = 2 },
			{ id = "mon_giant_rat", weight = 2 },
		},
		bosses = { { id = "mon_bone_lord", weight = 1 } },
		chestRarityWeights = { 88, 12 },
		chestEffectMinRarity = 2,
		sellableItems = { { id = "itm_bone_fragment", weight = 1 } },
		jobPotionTargets = { "job_priest", "job_bishop" },
		modifierPool = { "mod_exorcism", "mod_healing" },
	},
	{
		id = "dng_ruins",
		name = "罠の遺跡",
		stage = 2,
		timeTarget = 65,
		floors = 9,
		terrainTags = { "outdoor" },
		ratios = BEAST,
		trapEvade = 0.45, -- 罠の多いダンジョン
		trapDamageRate = 0.30,
		monsters = {
			{ id = "mon_ruin_wolf", weight = 4 },
			{ id = "mon_clay_golem", weight = 4 },
			{ id = "mon_imp", weight = 2 },
		},
		bosses = { { id = "mon_stone_guardian", weight = 1 } },
		chestRarityWeights = { 85, 10, 5 },
		chestEffectMinRarity = 2,
		sellableItems = { { id = "itm_old_gear", weight = 1 } },
		jobPotionTargets = { "job_thief", "job_ninja" },
		modifierPool = { "mod_trapward", "mod_swift" },
	},
	{
		id = "dng_tower",
		name = "封印の塔",
		stage = 3,
		timeTarget = 94,
		floors = 11,
		terrainTags = { "indoor" },
		ratios = ARCANE_STRONG,
		monsters = {
			{ id = "mon_wisp", weight = 4 },
			{ id = "mon_gargoyle", weight = 3 },
			{ id = "mon_shade_sorcerer", weight = 3 },
		},
		bosses = { { id = "mon_sealed_archmage", weight = 1 } },
		chestRarityWeights = { 72, 16, 10, 2 },
		chestEffectMinRarity = 3,
		sellableItems = { { id = "itm_magic_shard", weight = 1 } },
		jobPotionTargets = { "job_mage", "job_sage" },
		modifierPool = { "mod_healing", "mod_swift" },
	},
	{
		id = "dng_castle",
		name = "騎士の古城",
		stage = 4,
		timeTarget = 106,
		floors = 13,
		terrainTags = { "indoor" },
		ratios = ARMORED,
		monsters = {
			{ id = "mon_cursed_knight", weight = 5 },
			{ id = "mon_armored_hound", weight = 4 },
			{ id = "mon_dark_chaplain", weight = 1 },
		},
		bosses = { { id = "mon_fallen_lord", weight = 1 } },
		chestRarityWeights = { 62, 23, 12, 3 },
		chestEffectMinRarity = 3,
		sellableItems = { { id = "itm_knight_crest", weight = 1 } },
		jobPotionTargets = { "job_warrior", "job_knight" },
		modifierPool = { "mod_exorcism", "mod_trapward" },
	},
	{
		id = "dng_sunken_temple",
		name = "水没神殿",
		stage = 5,
		timeTarget = 119,
		floors = 13,
		terrainTags = { "indoor" },
		ratios = BAL,
		monsters = {
			{ id = "mon_merfolk_raider", weight = 3 },
			{ id = "mon_drowned_sailor", weight = 2 },
			{ id = "mon_sea_witch", weight = 5 },
		},
		bosses = { { id = "mon_tide_priestess", weight = 1 } },
		chestRarityWeights = { 50, 28, 12, 9, 1 },
		chestEffectMinRarity = 4,
		sellableItems = { { id = "itm_tide_pearl", weight = 1 } },
		jobPotionTargets = { "job_mage", "job_sage" },
		modifierPool = { "mod_healing", "mod_exorcism" },
	},
	{
		id = "dng_mist_forest",
		name = "霧の大森林",
		stage = 6,
		timeTarget = 131,
		floors = 15,
		terrainTags = { "outdoor" },
		ratios = BEAST,
		monsters = {
			{ id = "mon_dire_wolf", weight = 5 },
			{ id = "mon_treant", weight = 3 },
			{ id = "mon_mist_sprite", weight = 2 },
		},
		bosses = { { id = "mon_ancient_bear", weight = 1 } },
		chestRarityWeights = { 40, 32, 15, 11, 2 },
		chestEffectMinRarity = 4,
		sellableItems = { { id = "itm_amber_sap", weight = 1 } },
		jobPotionTargets = { "job_thief", "job_ninja" },
		modifierPool = { "mod_swift", "mod_trapward" },
	},
	{
		id = "dng_labyrinth",
		dispatchFee = 1000,
		name = "地下大迷宮",
		stage = 7,
		timeTarget = 144,
		floors = 15,
		terrainTags = { "indoor" },
		ratios = BAL,
		trapEvade = 0.45,
		trapDamageRate = 0.30,
		monsters = {
			{ id = "mon_labyrinth_bull", weight = 4 },
			{ id = "mon_mimic", weight = 3 },
			{ id = "mon_deep_sorcerer", weight = 3 },
		},
		bosses = { { id = "mon_labyrinth_warden", weight = 1 } },
		chestRarityWeights = { 30, 34, 21, 12, 3 },
		chestEffectMinRarity = 4,
		sellableItems = { { id = "itm_labyrinth_coin", weight = 1 } },
		jobPotionTargets = { "job_warrior", "job_knight" },
		modifierPool = { "mod_trapward", "mod_swift" },
	},
	{
		id = "dng_abbey",
		dispatchFee = 2500,
		name = "呪われた修道院",
		stage = 8,
		timeTarget = 156,
		floors = 17,
		terrainTags = { "indoor" },
		ratios = ARCANE,
		monsters = {
			{ id = "mon_fallen_monk", weight = 4 },
			{ id = "mon_wraith", weight = 4 },
			{ id = "mon_gargoyle", weight = 2 },
		},
		bosses = { { id = "mon_abbot_lich", weight = 1 } },
		chestRarityWeights = { 20, 33, 25, 12, 9, 1 },
		chestEffectMinRarity = 5,
		sellableItems = { { id = "itm_holy_relic", weight = 1 } },
		jobPotionTargets = { "job_priest", "job_bishop" },
		modifierPool = { "mod_exorcism", "mod_healing" },
	},
	{
		id = "dng_iron_fortress",
		dispatchFee = 5000,
		name = "鋼鉄の要塞",
		stage = 9,
		timeTarget = 165,
		floors = 17,
		terrainTags = { "indoor" },
		ratios = ARMORED_STRONG,
		monsters = {
			{ id = "mon_iron_golem", weight = 4 },
			{ id = "mon_clockwork_soldier", weight = 4 },
			{ id = "mon_arcane_turret", weight = 2 },
		},
		bosses = { { id = "mon_fortress_colossus", weight = 1 } },
		chestRarityWeights = { 12, 30, 30, 15, 11, 2 },
		chestEffectMinRarity = 5,
		sellableItems = { { id = "itm_steel_cog", weight = 1 } },
		jobPotionTargets = { "job_warrior", "job_knight" },
		modifierPool = { "mod_trapward", "mod_swift" },
	},
	{
		id = "dng_dragon_nest",
		dispatchFee = 10000,
		name = "竜の巣",
		stage = 10,
		timeTarget = 175,
		floors = 19,
		terrainTags = { "outdoor" },
		ratios = DRAGON,
		monsters = {
			{ id = "mon_drake", weight = 4 },
			{ id = "mon_wyvern", weight = 3 },
			{ id = "mon_dragon_cultist", weight = 3 },
		},
		bosses = { { id = "mon_elder_dragon", weight = 1 } },
		chestRarityWeights = { 6, 25, 33, 21, 12, 3 },
		chestEffectMinRarity = 5,
		sellableItems = { { id = "itm_dragon_scale", weight = 1 } },
		jobPotionTargets = { "job_mage", "job_sage" },
		modifierPool = { "mod_swift", "mod_healing" },
	},
	{
		id = "dng_demon_gate",
		dispatchFee = 18000,
		name = "魔界の門",
		stage = 11,
		timeTarget = 247, -- D-092／D-093：パーティ5つで帰還間隔約30秒。撤退も長くなるよう移動を延ばす
		floors = 19,
		terrainTags = { "indoor" },
		ratios = ARCANE,
		monsters = {
			{ id = "mon_demon_knight", weight = 3 },
			{ id = "mon_hellhound", weight = 2 },
			{ id = "mon_abyss_caster", weight = 5 },
		},
		bosses = { { id = "mon_gate_keeper", weight = 1 } },
		chestRarityWeights = { 2, 18, 34, 31, 10, 5 },
		chestEffectMinRarity = 5,
		sellableItems = { { id = "itm_demon_horn", weight = 1 } },
		jobPotionTargets = { "job_thief", "job_ninja" },
		modifierPool = { "mod_healing", "mod_trapward" },
	},
	{
		id = "dng_sky_throne",
		dispatchFee = 30000,
		name = "天空の玉座",
		stage = 12,
		timeTarget = 265, -- D-092／D-093：同上
		floors = 21,
		terrainTags = { "outdoor" },
		ratios = DRAGON,
		monsters = {
			{ id = "mon_sky_sentinel", weight = 4 },
			{ id = "mon_storm_spirit", weight = 3 },
			{ id = "mon_fallen_seraph", weight = 3 },
		},
		bosses = { { id = "mon_sky_tyrant", weight = 1 } },
		chestRarityWeights = { 1, 12, 30, 32, 15, 10 },
		chestEffectMinRarity = 6,
		sellableItems = { { id = "itm_sky_feather", weight = 1 } },
		jobPotionTargets = { "job_priest", "job_bishop" },
		modifierPool = { "mod_exorcism", "mod_swift" },
	},
}
