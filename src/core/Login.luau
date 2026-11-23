--!strict
-- ログインボーナス（D-155, D-169, D-176、docs/system/06_formulas.md §20）
-- ログインした日数で進む7日一巡のカレンダー。途切れても戻らない。日の区切りは Calendar（D-168）。
--   login.day   次に受け取るカレンダーの位置 1〜7
--   login.cycle 何周目か（7日目のユニークを選ぶのに使う）
-- その日の最初のオンラインの advance で、day の報酬を受け取り箱へ入れてから1つ進める（7 の次は 1・cycle + 1）。
-- 7日目：ログイン用のユニーク（acquire = "login"）を loginOrder の順に1周1人。ユニークは受け取り箱経由で、
--   所属枠がいっぱいなら受け取り箱に残る（D-176）。その周のユニークがいない・持っている（届いている）・一巡した後は fallback。
-- 状態を持たない（関数の集合）。

local Calendar = require("./Calendar")
local Inbox = require("./Inbox")
local Rng = require("./Rng")

local Login = {}

Login.DAYS = 7 -- 7日一巡（D-155）

function Login.newState(): any
	return { lastDayIndex = -1, day = 1, cycle = 1 }
end

-- 7日目に配るユニーク（いなければ nil → fallback）
function Login.uniqueFor(state: any, cycle: number, master: any): any?
	local u = master.loginUniques[cycle]
	if u == nil or Inbox.hasUnique(state, u.id) then
		return nil
	end
	return u
end

-- その日の最初のオンラインの advance で呼ぶ。進めたら受け取り箱の件を返す
function Login.advance(state: any, now: number, master: any, takeRng: () -> Rng.Rng, events: { any }): any?
	local L = state.login
	local today = Calendar.dayIndex(now)
	if L.lastDayIndex >= today then
		return nil
	end
	local day, cycle = L.day, L.cycle
	local entry
	local uniqueId: string? = nil
	if day < Login.DAYS then
		entry = Inbox.push(state, "login", now, master.loginBonus.days[day], takeRng, master)
	else
		local u = Login.uniqueFor(state, cycle, master)
		if u then
			uniqueId = u.id
			entry = Inbox.push(state, "login", now, nil, takeRng, master, u.id)
		else
			entry = Inbox.push(state, "login", now, master.loginBonus.fallback, takeRng, master)
		end
	end
	L.lastDayIndex = today
	if day >= Login.DAYS then
		L.day = 1
		L.cycle = cycle + 1
	else
		L.day = day + 1
	end
	table.insert(
		events,
		{ type = "LoginBonus", at = now, day = day, cycle = cycle, uniqueId = uniqueId, inboxUid = entry.uid }
	)
	return entry
end

return Login
