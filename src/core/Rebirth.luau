--!strict
-- 転生（ゲーム仕様書07章 §2、D-024, D-071, D-072, Q-009, Q-021）
-- 抽選と適用の計算のみ。コマンドの検証は Game が行う。

local Formulas = require("./Formulas")
local Rng = require("./Rng")
local Types = require("./Types")

local Rebirth = {}

-- 引き直しの比較：合計値（HP を除く4項目：Q-006）
function Rebirth.total(stats: Types.StatBlock): number
	return stats.str + stats.mag + stats.agi + stats.dex
end

-- 引き継ぎ分：転生前の素の値の1/2（端数切り捨て：Q-009）
function Rebirth.inherited(base: Types.StatBlock): Types.StatBlock
	local out: any = {}
	for _, s in Types.STAT_KEYS do
		out[s] = math.floor(base[s] / 2)
	end
	return out
end

-- 加算分の抽選（D-072）。乱数の消費順は STAT_KEYS の順
function Rebirth.rollBonus(base: Types.StatBlock, newRebirthCount: number, rng: Rng.Rng, master: any): Types.StatBlock
	local out: any = {}
	for _, s in Types.STAT_KEYS do
		out[s] = Formulas.rollRebirthBonus(base[s], newRebirthCount, rng, master.K)
	end
	return out
end

-- 加算分の上限（表示用）
function Rebirth.bonusMax(base: Types.StatBlock, master: any): Types.StatBlock
	local out: any = {}
	for _, s in Types.STAT_KEYS do
		out[s] = Formulas.rebirthBonusMax(base[s], master.K)
	end
	return out
end

-- 転生できるか（上限レベルに達していて、まだ上限を伸ばせる）
function Rebirth.canRebirth(adv: any, master: any): string?
	if adv.level < adv.levelCap then
		return "LEVEL_NOT_AT_CAP"
	end
	if adv.levelCap >= master.K.levelCapMax then
		return "MAX_REBIRTH"
	end
	return nil
end

-- 転生を確定する。追加したギフトID（なければ nil）を返す
function Rebirth.apply(adv: any, session: any, bonus: Types.StatBlock, rng: Rng.Rng, master: any): string?
	local K = master.K
	for _, s in Types.STAT_KEYS do
		adv.baseStats[s] = session.inherited[s] + bonus[s]
	end
	adv.rebirthCount += 1
	adv.level = 1
	adv.exp = 0
	adv.levelCap = math.min(adv.levelCap + K.levelCapPerRebirth, K.levelCapMax)
	adv.appearanceId = session.newAppearanceId
	-- D-024：2・4・6回目の転生でギフトを1つ追加（未所持から抽選、最大4）
	if table.find(K.rebirthGiftAddAt, adv.rebirthCount) and #adv.giftIds < K.giftMax then
		local pool = {}
		for _, g in master.giftList do
			if not table.find(adv.giftIds, g.id) then
				table.insert(pool, g)
			end
		end
		if #pool > 0 then
			local g = rng:pickWeighted(pool, function(x)
				return x.weight
			end)
			table.insert(adv.giftIds, g.id)
			return g.id
		end
	end
	return nil
end

-- 転生費用（D-080）：転生回数に応じて rebirthCost から引く
function Rebirth.cost(adv: any, master: any): number
	return master.K.rebirthCost[adv.rebirthCount + 1] or 0
end

return Rebirth
