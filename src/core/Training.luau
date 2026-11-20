--!strict
-- トレーニング（D-076, D-077。docs/system/06_formulas.md §8b）
-- ゴールドを払って経験値を得る。1回の費用はレベルが上がるほど跳ね上がり、
-- 上げられるのはトレーニング場のレベルで決まる上限まで。経験値に倍率は掛けない。

local Formulas = require("./Formulas")
local Growth = require("./Growth")
local Rng = require("./Rng")

local Training = {}

function Training.facility(state: any, master: any): any
	return master.K.trainingFacility[state.expansions.trainingLevel]
end

-- 1回の費用（D-076）
function Training.sessionCost(level: number, K: any): number
	return math.floor(K.trainGoldCoef * level ^ K.trainGoldExponent)
end

-- トレーニングで上げられるレベルの上限（トレーニング場の上限と本人の上限の小さい方）
function Training.levelCap(adv: any, state: any, master: any): number
	return math.min(adv.levelCap, Training.facility(state, master).levelCap)
end

-- 最大 sessions 回行う。上限レベルに達するか、ゴールドが足りなくなったら止める
-- 戻り値：{ sessions = 実施回数, gold = 費用合計, levels = 上がったレベルの一覧 }
function Training.run(state: any, adv: any, sessions: number, rng: Rng.Rng, master: any): any
	local K = master.K
	local cap = Training.levelCap(adv, state, master)
	local gain = Training.facility(state, master).expPerSession
	local done, spent, levels = 0, 0, {}
	while done < sessions and adv.level < cap do
		local cost = Training.sessionCost(adv.level, K)
		if state.gold < cost then
			break
		end
		state.gold -= cost
		spent += cost
		done += 1
		adv.exp += gain
		for _, lv in Growth.levelUpTo(adv, cap, rng, master) do
			table.insert(levels, lv)
		end
	end
	return { sessions = done, gold = spent, levels = levels }
end

-- 目標レベルまでの見積もり（UI・CLI 用。状態は変えない）
function Training.quote(state: any, adv: any, targetLevel: number, master: any): any
	local K = master.K
	local cap = math.min(targetLevel, Training.levelCap(adv, state, master))
	local gain = Training.facility(state, master).expPerSession
	local level, exp, sessions, gold = adv.level, adv.exp, 0, 0
	while level < cap do
		local need = Formulas.expToNext(level, K, adv.rebirthCount)
		local n = math.max(0, math.ceil((need - exp) / gain))
		sessions += n
		gold += n * Training.sessionCost(level, K)
		exp = exp + n * gain - need
		level += 1
	end
	return { toLevel = level, sessions = sessions, gold = gold }
end

return Training
