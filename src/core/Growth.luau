--!strict
-- 経験値とレベルアップ（ゲーム仕様書07章 §1、docs/system/06_formulas.md §8）
-- D-039 / D-043：成長は職業の基準値 ± growthVariance（最低0）
-- D-045：転職後は新しい職業の成長を使う（常に現在の jobId を見る）

local Formulas = require("./Formulas")
local Rng = require("./Rng")
local Types = require("./Types")

local Growth = {}

-- 個人の経験値倍率（転生回数 × (1 + 大食らい＋装備の経験値補正)。補正の合計は expBonusCap まで：D-082）
-- equipment は state.equipment（装備の補正を数えるとき）
function Growth.expMultiplier(adv: any, master: any, equipment: any?): number
	local K = master.K
	local rate = 0
	for _, g in adv.giftIds do
		local gift = master.gifts[g]
		if gift and gift.effect.kind == "expPct" then
			rate += gift.effect.value
		end
	end
	if equipment then
		for _, slot in { "weapon", "armor", "sub" } do
			local uid = adv.equipment[slot]
			local item = uid and equipment[uid]
			if item then
				rate += Formulas.equipExpPct(item, master)
			end
		end
	end
	return (1 + K.rebirthExpBonusPerCount * adv.rebirthCount) * (1 + math.min(rate, K.expBonusCap))
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

-- 貯まった経験値で capLevel までレベルを上げる。capLevel に達したら経験値は捨てる
function Growth.levelUpTo(adv: any, capLevel: number, rng: Rng.Rng, master: any): { number }
	local K = master.K
	local levels = {}
	while adv.level < capLevel do
		local need = Formulas.expToNext(adv.level, K, adv.rebirthCount)
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
	if adv.level >= capLevel then
		adv.exp = 0
	end
	return levels
end

-- 経験値を加え、レベルアップを処理する。上がったレベルの一覧を返す
-- 上限レベルでは経験値を貯めない（07章）
-- outerMult：expBonusCap の外で掛ける倍率（休息ボーナス × 日替わりの expMult。06章 §8・§14、D-173）。省略時 1
function Growth.addExp(
	adv: any,
	rawAmount: number,
	rng: Rng.Rng,
	master: any,
	equipment: any?,
	outerMult: number?
): { number }
	if adv.level >= adv.levelCap then
		adv.exp = 0
		return {}
	end
	adv.exp += math.floor(rawAmount * Growth.expMultiplier(adv, master, equipment) * (outerMult or 1))
	return Growth.levelUpTo(adv, adv.levelCap, rng, master)
end

return Growth
