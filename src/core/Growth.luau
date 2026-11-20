--!strict
-- 経験値とレベルアップ（ゲーム仕様書07章 §1、docs/system/06_formulas.md §8）
-- D-039 / D-043：成長は職業の基準値 ± growthVariance（最低0）
-- D-045：転職後は新しい職業の成長を使う（常に現在の jobId を見る）

local Formulas = require("./Formulas")
local Rng = require("./Rng")
local Types = require("./Types")

local Growth = {}

-- 個人の経験値倍率（転生回数・大食らい）
function Growth.expMultiplier(adv: any, master: any): number
	local K = master.K
	local rate = 0
	for _, g in adv.giftIds do
		local gift = master.gifts[g]
		if gift and gift.effect.kind == "expPct" then
			rate += gift.effect.value
		end
	end
	return (1 + K.rebirthExpBonusPerCount * adv.rebirthCount) * (1 + math.min(rate, K.personalBonusCap))
end

-- 1レベル分の成長を抽選する（乱数の消費順：STAT_KEYS の順）
function Growth.rollGrowth(jobId: string, rng: Rng.Rng, master: any): Types.StatBlock
	local K = master.K
	local job = master.jobs[jobId]
	local v = K.growthVariance
	local out: any = {}
	for _, s in Types.STAT_KEYS do
		out[s] = math.max(0, job.growth[s] + rng:int(-v, v))
	end
	return out
end

-- 経験値を加え、レベルアップを処理する。上がったレベルの一覧を返す
-- 上限レベルでは経験値を貯めない（07章）
function Growth.addExp(adv: any, rawAmount: number, rng: Rng.Rng, master: any): { number }
	local K = master.K
	local levels = {}
	if adv.level >= adv.levelCap then
		adv.exp = 0
		return levels
	end
	adv.exp += math.floor(rawAmount * Growth.expMultiplier(adv, master))
	while adv.level < adv.levelCap do
		local need = Formulas.expToNext(adv.level, K)
		if adv.exp < need then
			break
		end
		adv.exp -= need
		adv.level += 1
		local g = Growth.rollGrowth(adv.jobId, rng, master)
		for _, s in Types.STAT_KEYS do
			adv.baseStats[s] += g[s]
		end
		table.insert(levels, adv.level)
	end
	if adv.level >= adv.levelCap then
		adv.exp = 0
	end
	return levels
end

return Growth
