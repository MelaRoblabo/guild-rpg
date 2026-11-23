--!strict
-- プレイ時間報酬（D-154、docs/system/06_formulas.md §20）
-- 今日のオンラインの合計秒（1日 playtimeDailyCapSeconds まで）で、PlaytimeRewards の段階に届いたら報酬を受け取り箱へ。
-- 日の区切り（D-168）で 0 に戻す。ログアウトでは戻さない。留守番の時間は数えない（オンラインの advance だけで呼ぶ）。
-- 状態を持たない（関数の集合）。

local Calendar = require("./Calendar")
local Inbox = require("./Inbox")
local Rng = require("./Rng")

local Playtime = {}

function Playtime.newState(): any
	return { dayIndex = -1, seconds = 0, claimedSteps = 0 }
end

-- オンラインの advance で呼ぶ。from = 前回の advance の時刻、now = 今
--   日が変わっていれば 0 に戻し、足すのは今日の区切りより後の分だけ
--   ログイン直後の最初の advance は、ログイン時の留守の計算（offline の advance）で from が今になっているので足さない
function Playtime.advance(state: any, from: number, now: number, master: any, takeRng: () -> Rng.Rng, events: { any })
	local P = state.playtime
	local today = Calendar.dayIndex(now)
	local add = math.max(0, now - from)
	if P.dayIndex ~= today then
		P.dayIndex = today
		P.seconds = 0
		P.claimedSteps = 0
		add = math.min(add, math.max(0, now - Calendar.dayStart(now)))
	end
	P.seconds = math.min(P.seconds + add, master.K.playtimeDailyCapSeconds)
	local steps = master.playtimeRewards
	while P.claimedSteps < #steps do
		local step = steps[P.claimedSteps + 1]
		if P.seconds < step.minutes * 60 then
			break
		end
		P.claimedSteps += 1
		local entry = Inbox.push(state, "playtime", now, step.rewards, takeRng, master)
		table.insert(events, { type = "PlaytimeReward", at = now, minutes = step.minutes, inboxUid = entry.uid })
	end
end

-- 次の段階（なければ nil）
function Playtime.nextStep(state: any, master: any): any?
	return master.playtimeRewards[state.playtime.claimedSteps + 1]
end

return Playtime
