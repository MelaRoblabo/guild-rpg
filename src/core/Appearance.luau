--!strict
-- 見た目と名前の抽選（ゲーム仕様書07章 §4、D-042, D-050〜D-054, D-062）
-- 乱数の消費順：性別（指定がなければ）→ タイプ → カテゴリ内の1種 → 名前

local Rng = require("./Rng")

local Appearance = {}

local function weightOf(e: any): number
	return e.weight
end

local function uniform(_e: any): number
	return 1
end

-- 職業 → 見た目の職業区分（D-042）
function Appearance.outfitClassOf(jobId: string, master: any): string
	return master.jobs[jobId].outfitClass
end

-- 見た目を抽選する
--   gender: 指定すれば固定（転生・見た目変更：D-051）。nil なら抽選（雇用：D-050）
--   excludeId: 直前と同じ見た目を除外（D-051）
function Appearance.roll(gender: string?, outfitClass: string, rng: Rng.Rng, master: any, excludeId: string?)
	local K = master.K
	local g = gender or rng:pickWeighted(K.appearanceGenderWeights, weightOf).id
	local looks = rng:pickWeighted(K.appearanceLooksWeights, weightOf).id
	local candidates = {}
	for _, a in master.raw.Appearances do
		if a.gender == g and a.looks == looks and a.outfitClass == outfitClass and a.id ~= excludeId then
			table.insert(candidates, a)
		end
	end
	local a = rng:pickWeighted(candidates, uniform)
	return { appearanceId = a.id, gender = g, looks = looks }
end

-- 名前を抽選する（D-054：亜人は亜人用のリスト）
function Appearance.rollName(gender: string, looks: string, rng: Rng.Rng, master: any): string
	local names = master.raw.Names
	local list = if looks == "dem" then names.dem else names[gender]
	return rng:pickWeighted(list, uniform)
end

-- 見た目のタイプ（appearanceId から引く。ユニークは nil）
function Appearance.looksOf(appearanceId: string, master: any): string?
	local a = master.appearances[appearanceId]
	return if a then a.looks else nil
end

return Appearance
