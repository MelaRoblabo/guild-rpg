--!strict
-- クエストの画面（D-153・D-179・D-191・D-233）の見せ方。純粋な関数（Lune でテストする）。
--   - 区切りまでの残り時間の短い書き方（Daily 14h／Weekly 2d。1時間を切ったら分）。
--   - 行の報酬の札：一番大きい報酬1つ（宝箱があれば宝箱の数、なければチケット、なければゴールド）。

export type Deps = {
	nextDayStart: (now: number) -> number, -- Calendar.nextDayStart
	nextWeekStart: (now: number) -> number, -- Calendar.nextWeekStart
}

local QuestView = {}

function QuestView.left(period: string, now: number, deps: Deps): string
	local until_ = if period == "weekly" then deps.nextWeekStart(now) else deps.nextDayStart(now)
	local s = math.max(0, until_ - now)
	if s >= 86400 then
		return math.floor(s / 86400) .. "d"
	elseif s >= 3600 then
		return math.floor(s / 3600) .. "h"
	end
	return math.max(1, math.floor(s / 60)) .. "m"
end

-- 行の報酬の札：{ kind = "chest"|"ticket"|"gold", n }
function QuestView.mainReward(rewards: any): { kind: string, n: number }?
	if rewards == nil then
		return nil
	end
	local chests = 0
	for _, c in rewards.chests or {} do
		chests += c.count
	end
	if chests > 0 then
		return { kind = "chest", n = chests }
	end
	local tickets = (rewards.items or {}).itm_slot_ticket
	if tickets and tickets > 0 then
		return { kind = "ticket", n = tickets }
	end
	if rewards.goldMult then
		return { kind = "gold", n = rewards.goldMult }
	end
	return nil
end

return QuestView
