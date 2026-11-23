--!strict
-- デイリー・ウィークリークエスト（D-153, D-179、docs/system/06_formulas.md §15）
--   Quest.newState()                       空のクエスト（次のオンラインの advance で今日・今週の分を作る）
--   Quest.refresh(state, now, master)      日・週が変わっていれば入れ替える（引き直しなし）
--   Quest.count(state, kind, n, ...)       オンライン中の行動を数え、達成したら報酬を受け取り箱へ（D-164）
-- お題は calendarSeed と日・週の番号とプレイヤーの seed から決まる（rngCounter は進めない）。
-- 状態を持たない（関数の集合）。

local Calendar = require("./Calendar")
local Inbox = require("./Inbox")
local Rng = require("./Rng")

local Quest = {}

export type Period = "daily" | "weekly"

-- 抽選の乱数をデイリーとウィークリーで分けるための番号（ゲームの調整値ではない）
local PERIOD_STREAM = { daily = 1, weekly = 2 }

local function uniform(_e: any): number
	return 1
end

function Quest.newState(): any
	return {
		daily = { dayIndex = -1, entries = {}, bonusDone = false },
		weekly = { weekIndex = -1, entries = {}, bonusDone = false },
	}
end

-- その期間のお題を抽選する（06章 §15）
--   rng = Rng.new(Rng.derive(Rng.derive(Rng.derive(calendarSeed, 日または週の番号), state.seed), 期間の番号))
--   候補（Quests のその期間の行、データの順）から重複なしで questDailyCount / questWeeklyCount 個
--   量 = amountPerParty × 解放済みのパーティ数（expansions.partySlots）
function Quest.draw(state: any, period: Period, periodIndex: number, master: any): { any }
	local K = master.K
	local rng =
		Rng.new(Rng.derive(Rng.derive(Rng.derive(K.calendarSeed, periodIndex), state.seed), PERIOD_STREAM[period]))
	local candidates = {}
	for _, q in master.questList do
		if q.period == period then
			table.insert(candidates, q)
		end
	end
	local count = if period == "daily" then K.questDailyCount else K.questWeeklyCount
	local parties = state.expansions.partySlots
	local entries = {}
	for _ = 1, math.min(count, #candidates) do
		local q = rng:pickWeighted(candidates, uniform)
		table.remove(candidates, table.find(candidates, q) :: number)
		table.insert(entries, { questId = q.id, target = q.amountPerParty * parties, progress = 0, done = false })
	end
	return entries
end

-- 日・週が変わっていれば入れ替える（オンラインの advance で呼ぶ：05章 §3）。入れ替えたら true
function Quest.refresh(state: any, now: number, master: any): boolean
	local q = state.quests
	local changed = false
	local day = Calendar.dayIndex(now)
	if q.daily.dayIndex ~= day then
		q.daily = { dayIndex = day, entries = Quest.draw(state, "daily", day, master), bonusDone = false }
		changed = true
	end
	local week = Calendar.weekIndex(now)
	if q.weekly.weekIndex ~= week then
		q.weekly = { weekIndex = week, entries = Quest.draw(state, "weekly", week, master), bonusDone = false }
		changed = true
	end
	return changed
end

-- 行動を n だけ数える（オンライン中の行動だけ：D-153, D-161, D-179）。
-- 達成したお題の報酬を受け取り箱へ入れ、その期間のお題が全部達成ならボーナス（questDailyBonus / questWeeklyBonus）も入れる
function Quest.count(
	state: any,
	kind: string,
	n: number,
	at: number,
	master: any,
	takeRng: () -> Rng.Rng,
	events: { any }
)
	if n <= 0 or state.quests == nil then
		return
	end
	for _, period in { "daily", "weekly" } do
		local book = state.quests[period]
		local completed = false
		for _, entry in book.entries do
			local row = master.quests[entry.questId]
			if row and row.kind == kind and not entry.done then
				entry.progress = math.min(entry.target, entry.progress + n)
				if entry.progress >= entry.target then
					entry.done = true
					completed = true
					local inb = Inbox.push(state, "quest", at, row.rewards, takeRng, master)
					table.insert(events, {
						type = "QuestCompleted",
						at = at,
						period = period,
						questId = entry.questId,
						inboxUid = inb.uid,
					})
				end
			end
		end
		if completed and not book.bonusDone and #book.entries > 0 then
			local all = true
			for _, entry in book.entries do
				all = all and entry.done
			end
			if all then
				book.bonusDone = true
				local bonus = if period == "daily" then master.K.questDailyBonus else master.K.questWeeklyBonus
				local inb = Inbox.push(state, "quest", at, bonus, takeRng, master)
				table.insert(events, { type = "QuestBonus", at = at, period = period, inboxUid = inb.uid })
			end
		end
	end
end

return Quest
