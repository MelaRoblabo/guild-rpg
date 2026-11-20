--!strict
-- 成長段階のモデル（バランス調整用。docs/reports/M1b_balance.md）
-- 段階 i ＝ ダンジョン i に初めて挑むころの、平均的なパーティの状態（仮の想定）
--   k: 転生回数 / level: レベル / gearTier: 装備のアイテムレベル / rarity・grade: 装備のレアリティ・グレード
-- 基礎ステータス：雇用範囲の中央値から始め、転生ごとに「上限レベル時の値の1/2＋加算分の中央値」を引き継ぐ。
-- 成長は職業の基準値どおり（振れ幅なし）。

local Stages = {}

Stages.list = {
	{ k = 0, level = 1, gearTier = 1, rarity = 1, grade = 0 },
	{ k = 0, level = 8, gearTier = 1, rarity = 1, grade = 1 },
	{ k = 0, level = 15, gearTier = 2, rarity = 2, grade = 1 },
	{ k = 0, level = 24, gearTier = 3, rarity = 2, grade = 1 },
	{ k = 1, level = 25, gearTier = 4, rarity = 3, grade = 1 },
	{ k = 1, level = 38, gearTier = 5, rarity = 3, grade = 1 },
	{ k = 2, level = 45, gearTier = 6, rarity = 3, grade = 1 },
	{ k = 3, level = 55, gearTier = 7, rarity = 4, grade = 1 },
	{ k = 4, level = 65, gearTier = 8, rarity = 4, grade = 1 },
	{ k = 5, level = 75, gearTier = 9, rarity = 4, grade = 1 },
	{ k = 6, level = 85, gearTier = 10, rarity = 4, grade = 2 },
	{ k = 7, level = 98, gearTier = 11, rarity = 5, grade = 1 },
}

local STATS = { "str", "mag", "agi", "dex", "hp" }

local JOB_GEAR = {
	job_warrior = { weapon = "eq_wpn_sword", armor = "eq_arm_chainmail", sub = "eq_sub_buckler" },
	job_knight = { weapon = "eq_wpn_sword", armor = "eq_arm_chainmail", sub = "eq_sub_buckler" },
	job_thief = { weapon = "eq_wpn_dagger", armor = "eq_arm_leather", sub = "eq_sub_ring_wind" },
	job_ninja = { weapon = "eq_wpn_dagger", armor = "eq_arm_leather", sub = "eq_sub_ring_wind" },
	job_mage = { weapon = "eq_wpn_staff", armor = "eq_arm_robe", sub = "eq_sub_ring_wisdom" },
	job_sage = { weapon = "eq_wpn_staff", armor = "eq_arm_robe", sub = "eq_sub_ring_wisdom" },
	job_priest = { weapon = "eq_wpn_mace", armor = "eq_arm_vestment", sub = "eq_sub_ring_wisdom" },
	job_bishop = { weapon = "eq_wpn_mace", armor = "eq_arm_vestment", sub = "eq_sub_ring_wisdom" },
}

-- 転生モデルに沿った基礎ステータス
function Stages.baseStats(master: any, jobId: string, k: number, level: number)
	local K = master.K
	local job = master.jobs[jobId]
	local out = {}
	for _, s in STATS do
		local r = K.hireStatRange[s]
		local stat = math.floor((r.min + r.max) / 2)
		for j = 0, k - 1 do
			local cap = math.min(K.levelCapInitial + K.levelCapPerRebirth * j, K.levelCapMax)
			local atCap = stat + job.growth[s] * (cap - 1)
			local b = K.rebirthBonusRange[s]
			stat = math.floor(atCap / 2) + math.floor((b.min + b.max) / 2)
		end
		out[s] = stat + job.growth[s] * (level - 1)
	end
	return out
end

function Stages.member(master: any, jobId: string, slot: number, stage: any, giftIds: { string }?)
	local equipment = {}
	for slotName, baseId in JOB_GEAR[jobId] do
		equipment[slotName] =
			{ baseId = baseId, rarity = stage.rarity, grade = stage.grade, itemLevel = stage.gearTier }
	end
	return {
		uid = `sim_{slot}_{jobId}`,
		slot = slot,
		jobId = jobId,
		baseStats = Stages.baseStats(master, jobId, stage.k, stage.level),
		giftIds = giftIds or {},
		equipment = equipment,
	}
end

Stages.COMPOSITIONS = {
	balanced = {
		jobs = { "job_warrior", "job_thief", "job_mage", "job_priest" },
		desc = "戦士・盗賊・魔法使い・僧侶",
	},
	phys = {
		jobs = { "job_warrior", "job_warrior", "job_thief", "job_thief" },
		desc = "物理偏重（戦士2・盗賊2）",
	},
	magic = {
		jobs = { "job_warrior", "job_mage", "job_mage", "job_priest" },
		desc = "魔法偏重（戦士・魔法使い2・僧侶）",
	},
	nohealer = {
		jobs = { "job_warrior", "job_thief", "job_mage", "job_mage" },
		desc = "回復なし（戦士・盗賊・魔法使い2）",
	},
	gifts = {
		jobs = { "job_warrior", "job_thief", "job_mage", "job_priest" },
		gifts = { { "gift_sturdy" }, { "gift_trapsense" }, { "gift_exorcist" }, { "gift_lucky" } },
		desc = "バランス＋ギフト（頑健・罠師の勘・退魔の才・幸運）",
	},
}

-- 段階 i と編成名からパーティ（メンバー定義の配列）を作る
function Stages.party(master: any, stageIndex: number, composition: string?)
	local stage = Stages.list[stageIndex]
	assert(stage, `未知の段階: {stageIndex}`)
	local comp = Stages.COMPOSITIONS[composition or "balanced"]
	assert(comp, `未知の編成: {composition}`)
	local out = {}
	for i, jobId in comp.jobs do
		table.insert(out, Stages.member(master, jobId, i, stage, comp.gifts and comp.gifts[i]))
	end
	return out
end

-- プリセット名 "s<段階>[_<編成>]" を解釈する（例 s3、s5_magic）
function Stages.parse(name: string): (number, string)
	local idx, comp = string.match(name, "^s(%d+)_?(%a*)$")
	assert(idx, `プリセット名は s<段階>[_<編成>]: {name}`)
	return tonumber(idx) :: number, if comp == "" then "balanced" else comp
end

return Stages
