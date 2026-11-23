--!strict
-- 特別な宝箱の表（D-166, D-171、docs/system/04_master_data.md §11、06章 §19）
-- 各行：id, pileKey, rarityWeights（%。[1]=コモン…）, effectMinRarity（このレアリティ以上で演出）,
--       effectRateMin / effectRateMax（effectMinRarity 以上が出る割合の基準。行ごとに検査する。D-090 の検査は普通のダンジョンだけ）
-- spc_rare（レアダンジョン）は表を持たない：中身は相当するダンジョンの chestRarityWeights、
--   演出ラインはそのダンジョンの rareChestEffectMinRarity、基準は Constants.rareDungeonEffectRate（D-171, D-185）
-- 中身のアイテムレベルは「開けたときに踏破している一番深いダンジョン」（D-171）
-- 出現率・演出ライン・演出率の基準はすべて仮（M7b-6）

return {
	{ id = "spc_rare", pileKey = "special:rare" }, -- 鍵は special:rare:<相当するダンジョン>
	{
		id = "spc_raid",
		pileKey = "special:raid",
		rarityWeights = { 0, 0, 70, 22, 7, 1 }, -- 仮（M7b-6）。レイドのレアな宝箱（D-152）
		effectMinRarity = 4, -- 仮（M7b-6）
		effectRateMin = 0.20, -- 仮（M7b-6）
		effectRateMax = 0.40, -- 仮（M7b-6）
	},
	{
		id = "spc_quest",
		pileKey = "special:quest",
		rarityWeights = { 50, 30, 15, 5 }, -- 仮（M7b-6）
		effectMinRarity = 3, -- 仮（M7b-6）
		effectRateMin = 0.15, -- 仮（M7b-6）
		effectRateMax = 0.25, -- 仮（M7b-6）
	},
	{
		id = "spc_login",
		pileKey = "special:login",
		rarityWeights = { 50, 30, 15, 5 }, -- 仮（M7b-6）
		effectMinRarity = 3, -- 仮（M7b-6）
		effectRateMin = 0.15, -- 仮（M7b-6）
		effectRateMax = 0.25, -- 仮（M7b-6）
	},
	{
		id = "spc_playtime",
		pileKey = "special:playtime",
		rarityWeights = { 70, 20, 8, 2 }, -- 仮（M7b-6）
		effectMinRarity = 3, -- 仮（M7b-6）
		effectRateMin = 0.08, -- 仮（M7b-6）
		effectRateMax = 0.15, -- 仮（M7b-6）
	},
}
