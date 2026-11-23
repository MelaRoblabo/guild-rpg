--!strict
-- 日替わりの特性（D-156, D-173、docs/system/06_formulas.md §16）
-- 日の番号（Calendar）と calendarSeed だけから決まるので、全員共通・どのサーバーでも同じ。
-- 帯（dailyTraitBands）ごとに、帯の難度のダンジョンから1つ、DailyTraits から1つを抽選する。

local Calendar = require("./Calendar")
local Rng = require("./Rng")

local DailyTrait = {}

export type Pick = { band: number, dungeonId: string, traitId: string }

local function uniform(_e: any): number
	return 1
end

-- その日の特性の一覧（帯の順）
function DailyTrait.forDay(dayIndex: number, master: any): { Pick }
	local K = master.K
	local rng = Rng.new(Rng.derive(K.calendarSeed, dayIndex))
	local out = {}
	for i, band in K.dailyTraitBands do
		local candidates = {}
		for _, d in master.dungeonList do
			if d.tier >= band.min and d.tier <= band.max then
				table.insert(candidates, d)
			end
		end
		local dungeon = rng:pickWeighted(candidates, uniform)
		local trait = rng:pickWeighted(master.dailyTraitList, uniform)
		table.insert(out, { band = i, dungeonId = dungeon.id, traitId = trait.id })
	end
	return out
end

-- 時刻 now の日に、そのダンジョンに当たっている特性の id（なければ nil）
function DailyTrait.traitIdFor(dungeonId: string, now: number, master: any): string?
	for _, p in DailyTrait.forDay(Calendar.dayIndex(now), master) do
		if p.dungeonId == dungeonId then
			return p.traitId
		end
	end
	return nil
end

-- 特性の行（id が nil・知らない id なら nil）
function DailyTrait.row(traitId: string?, master: any): any?
	if traitId == nil then
		return nil
	end
	return master.dailyTraits[traitId]
end

-- 経験値の倍率（帰還時に掛ける。expBonusCap の外：D-173）
function DailyTrait.expMult(traitId: string?, master: any): number
	local t = DailyTrait.row(traitId, master)
	return if t and t.effect == "expMult" then t.value else 1
end

return DailyTrait
