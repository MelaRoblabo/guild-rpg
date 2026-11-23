--!strict
-- ゲーム外の通知で「その日に一番効く1つ」を選ぶ（D-159、11章 §8.2）。Roblox API は使わない。
--
-- 退出したときの状態から、送る時刻（sendAt）の見込みを作って選ぶ：
--   状態を写し、core の留守番（Game.advance、online = false）を sendAt まで進めた結果を見る（ログイン時と同じ計算）。
-- 優先順位（D-159 の案）：
--   ① loginUnique  ：あと1日でログインボーナスのユニーク（次に受け取るのが7日目で、その周のユニークがいる）
--   ② offlineDone  ：全パーティ帰還・宝箱 N 個（退出時に出ていた探索があり、sendAt が留守番の終わり以後。N は留守番で増える宝箱の数）
--   ③ dailyTrait   ：今日の日替わりが得意なダンジョン（sendAt の日の特性が、自動再派遣にしているダンジョンに当たる。仮の解釈：Q）
--   ④ rebirthReady ：転生できる冒険者 N 人（留守番のあとで上限レベルに届いていて、まだ転生できる人）
--   ⑤ dailyReset   ：デイリー更新（いつでも当てはまる。最後の候補）

local Calendar = require("@game/ReplicatedStorage/Core/Calendar")
local Game = require("@game/ReplicatedStorage/Core/Game")
local Login = require("@game/ReplicatedStorage/Core/Login")
local Rebirth = require("@game/ReplicatedStorage/Core/Rebirth")

local NotificationPicker = {}

-- 優先順（D-159）
NotificationPicker.KINDS = { "loginUnique", "offlineDone", "dailyTrait", "rebirthReady", "dailyReset" }

export type Pick = { kind: string, count: number? }

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

local function chestTotal(state: any, master: any): number
	local n = 0
	for _, c in Game.query.chestsByPile(state, master) do
		n += c.count
	end
	return n
end

-- 送る時刻：その人がいつも遊ぶ時刻（仮：今回ログインした時刻の、UTC の1日の中の位置）のうち、
-- 退出から minAwaySeconds 以上あとの最初のもの
function NotificationPicker.sendAt(loginAt: number, logoutAt: number, minAwaySeconds: number): number
	local timeOfDay = loginAt - Calendar.dayStart(loginAt)
	local earliest = logoutAt + minAwaySeconds
	local t = Calendar.dayStart(earliest) + timeOfDay
	if t < earliest then
		t = Calendar.nextDayStart(earliest) + timeOfDay
	end
	return t
end

-- 候補を選ぶ。enabled は送れる種類（文面の id を登録したもの）。当てはまるものがなければ nil
function NotificationPicker.pick(
	state: any,
	master: any,
	logoutAt: number,
	sendAt: number,
	enabled: { [string]: boolean }
): Pick?
	-- 留守番の見込み（写しに対して。保存のときに書く lastSavedAt も退出時刻にそろえる）
	local future = deepCopy(state)
	future.lastSavedAt = logoutAt
	Game.advance(future, { now = sendAt, master = master, online = false })

	local checks: { [string]: () -> (boolean, number?) } = {
		loginUnique = function()
			local cal = Game.query.loginCalendar(future, sendAt, master)
			return cal.uniqueId ~= nil and cal.day == Login.DAYS and not cal.receivedToday, nil
		end,
		offlineDone = function()
			if next(state.expeditions) == nil then
				return false, nil
			end
			if sendAt < logoutAt + master.K.offlineMaxSeconds then
				return false, nil -- 留守番がまだ終わっていない
			end
			return true, math.max(0, chestTotal(future, master) - chestTotal(state, master))
		end,
		dailyTrait = function()
			local repeatDungeons = {}
			for _, p in future.parties do
				if p.autoRepeat then
					repeatDungeons[p.autoRepeat.dungeonId] = true
				end
			end
			for _, pick in Game.query.dailyTraits(sendAt, master).today do
				if repeatDungeons[pick.dungeonId] then
					return true, nil
				end
			end
			return false, nil
		end,
		rebirthReady = function()
			local n = 0
			for _, adv in future.adventurers do
				if Rebirth.canRebirth(adv, master) == nil then
					n += 1
				end
			end
			return n > 0, n
		end,
		dailyReset = function()
			return true, nil
		end,
	}

	for _, kind in NotificationPicker.KINDS do
		if enabled[kind] then
			local ok, count = checks[kind]()
			if ok then
				return { kind = kind, count = count }
			end
		end
	end
	return nil
end

return NotificationPicker
