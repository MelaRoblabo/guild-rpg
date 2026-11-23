--!strict
-- 今週の訪問者と特別な訪問者（D-158, D-170, D-155、docs/system/06_formulas.md §18）
-- 今週の訪問者は calendarSeed と週の番号（Calendar）だけから決まるので、全員共通・どのサーバーでも同じ。
-- 候補は acquire = "visitor" のユニーク（ログインボーナス用 login・初回踏破 firstClear は入らない）。
--   Visitor.forWeek  その週の訪問者（ユニークの行。候補がいなければ nil）
--   Visitor.roll     雇用候補1人ぶんの判定。① 今週の訪問者（weeklyVisitorChance）→ ② 特別な訪問者（specialVisitorChance）
-- 状態を持たない（関数の集合）。

local Calendar = require("./Calendar")
local Rng = require("./Rng")

local Visitor = {}

local function uniform(_e: any): number
	return 1
end

-- その週の訪問者（データの並び順の候補から均等に1人）
function Visitor.forWeek(weekIndex: number, master: any): any?
	local list = master.visitorUniques
	if #list == 0 then
		return nil
	end
	local rng = Rng.new(Rng.derive(master.K.calendarSeed, weekIndex))
	return rng:pickWeighted(list, uniform)
end

-- 時刻 now の週の訪問者
function Visitor.forTime(now: number, master: any): any?
	return Visitor.forWeek(Calendar.weekIndex(now), master)
end

-- そのユニークを持っているか
function Visitor.owns(state: any, uniqueId: string): boolean
	for _, a in state.adventurers do
		if a.uniqueId == uniqueId then
			return true
		end
	end
	return false
end

-- 雇用候補1人ぶんの訪問者の判定。出たユニークの行（出なければ nil）
-- taken：この雇用の候補にすでに出たユニーク（同じ人を2枠に出さない。出たら印を付ける）
-- 乱数の消費順：①今週の訪問者の判定（飛ばすときは引かない）→ ②特別な訪問者の判定 →（当たれば）候補から1人
function Visitor.roll(state: any, rng: Rng.Rng, master: any, now: number, taken: { [string]: boolean }): any?
	local K = master.K
	local weekly = Visitor.forTime(now, master)
	-- ① 今週の訪問者を持っていれば（この雇用の候補にもう出ていれば）飛ばす
	if weekly and not Visitor.owns(state, weekly.id) and not taken[weekly.id] then
		if rng:chance(K.weeklyVisitorChance) then
			taken[weekly.id] = true
			return weekly
		end
	end
	-- ② 今週の訪問者以外の、持っていない visitor のユニークから均等に1人
	local pool = {}
	for _, u in master.visitorUniques do
		if not taken[u.id] and not Visitor.owns(state, u.id) and not (weekly and u.id == weekly.id) then
			table.insert(pool, u)
		end
	end
	if rng:chance(K.specialVisitorChance) and #pool > 0 then
		local u = rng:pickWeighted(pool, uniform)
		taken[u.id] = true
		return u
	end
	return nil
end

-- 雇用画面のバナー用（D-158）：今週の訪問者・候補1人あたりの出現率・持っているか・次の週の区切り
function Visitor.summary(state: any, now: number, master: any): any
	local weekly = Visitor.forTime(now, master)
	return {
		uniqueId = if weekly then weekly.id else nil,
		chance = master.K.weeklyVisitorChance, -- 候補1人ごとの確率（候補枠の数だけ判定する）
		candidateSlots = state.expansions.candidateSlots,
		owned = if weekly then Visitor.owns(state, weekly.id) else false,
		weekIndex = Calendar.weekIndex(now),
		nextWeekAt = Calendar.nextWeekStart(now),
	}
end

return Visitor
