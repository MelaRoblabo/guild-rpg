--!strict
-- M7b-5 の決定の反映：紹介の進み具合は転生回数の累計（D-195）、ゲーム外の通知の細部（D-196）、セーブの移行 v10 → 11
local serde = require("@lune/serde")

local Calendar = require("../src/core/Calendar")
local Friend = require("../src/core/Friend")
local Game = require("../src/core/Game")
local Login = require("../src/core/Login")
local MasterData = require("../src/core/MasterData")
local Migration = require("../src/core/Migration")
local Notify = require("../src/core/Notify")
local Protocol = require("../src/core/Protocol")
local Rng = require("../src/core/Rng")
local Data = require("../src/data")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1767225600 -- 2026-01-01 00:00 UTC
local DAY = 86400
local HOUR = 3600

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local K = master.K

	local function ctx(now: number)
		return { now = now, master = master, online = true }
	end
	local function exec(s: any, cmd: any, now: number?): any
		return Game.execute(s, cmd, ctx(now or T0))
	end
	local function newState(): any
		return Game.newState(master, 1, T0)
	end
	local function errorsOf(mutate: (any) -> ()): string
		local d = Fixtures.clone(Data)
		mutate(d)
		local lines = {}
		for _, i in MasterData.validate(d) do
			if i.level == "error" then
				table.insert(lines, i.path .. " " .. i.message)
			end
		end
		return table.concat(lines, "\n")
	end

	-- 隊列1の先頭の冒険者を1回転生させる
	local function rebirthOnce(s: any): string
		local uid = s.parties[1].slots[1]
		local adv = s.adventurers[uid]
		adv.level = adv.levelCap
		s.gold = 10 ^ 9
		expect(exec(s, { type = "RebirthStart", adventurerUid = uid }).ok).toBeTruthy()
		expect(exec(s, { type = "RebirthChoose", which = "current" }).ok).toBeTruthy()
		return uid
	end

	describe("紹介の進み具合は転生回数の累計（D-195）", function()
		it("D-195 転生の確定で累計（stats.rebirths）を数え、紹介の進み具合に届く", function()
			local s = newState()
			expect(Friend.referralProgressReached(s, master)).toBe(false)
			rebirthOnce(s)
			expect(s.stats.rebirths).toBe(1)
			expect(Friend.referralProgressReached(s, master)).toBe(K.referralProgressCondition.count <= 1)
		end)
		it(
			"D-195 転生した冒険者を解雇しても累計は戻らない（進み具合に届いたまま）",
			function()
				local s = newState()
				local uid = rebirthOnce(s)
				for i, slot in s.parties[1].slots do
					if slot == uid then
						expect(exec(s, { type = "SetPartySlot", partyIndex = 1, slot = i }).ok).toBeTruthy()
					end
				end
				expect(exec(s, { type = "Dismiss", adventurerUid = uid }).ok).toBeTruthy()
				expect(s.adventurers[uid]).toBe(nil)
				expect(s.stats.rebirths).toBe(1)
				local m1 = Fixtures.master(function(d)
					d.Constants.referralProgressCondition = { kind = "rebirthsTotal", count = 1 }
				end)
				expect(Friend.referralProgressReached(s, m1)).toBe(true)
			end
		)
		it(
			"D-195 進み具合の条件の種類は rebirthsTotal だけ（旧 rebirthedAdventurers は通さない）",
			function()
				expect(string.find(
					errorsOf(function(d)
						d.Constants.referralProgressCondition = { kind = "rebirthedAdventurers", count = 1 }
					end),
					"Constants.referralProgressCondition.kind",
					1,
					true
				) ~= nil).toBe(true)
				expect(errorsOf(function(d)
					d.Constants.referralProgressCondition = { kind = "rebirthsTotal", count = 1 }
				end)).toBe("")
			end
		)
	end)

	describe("いつも遊ぶ時刻（D-196 ②）", function()
		it(
			"D-196 ログイン時刻を1日の中の位置（秒）で直近 notifyLoginHistoryCount 回まで記録する",
			function()
				expect(K.notifyLoginHistoryCount).toBe(7)
				local s = newState()
				expect(s.loginTimes).toEqual({})
				for i = 1, K.notifyLoginHistoryCount + 2 do
					Notify.recordLogin(s, T0 + i * DAY + i * HOUR, master)
				end
				expect(#s.loginTimes).toBe(K.notifyLoginHistoryCount)
				-- 古いもの（1回目・2回目）を捨て、3回目から残る
				expect(s.loginTimes[1]).toBe(3 * HOUR)
				expect(s.loginTimes[#s.loginTimes]).toBe((K.notifyLoginHistoryCount + 2) * HOUR)
			end
		)
		it("D-196 D-168 1日の中の位置は UTC 0時（Calendar）から数える", function()
			local s = newState()
			local at = Calendar.dayStart(T0 + 10 * DAY) + 21 * HOUR + 30 * 60
			Notify.recordLogin(s, at, master)
			expect(s.loginTimes).toEqual({ 21 * HOUR + 30 * 60 })
		end)
		it("D-196 いつも遊ぶ時刻は中央値（記録がなければ nil）", function()
			local s = newState()
			expect(Notify.usualTimeOfDay(s)).toBe(nil)
			s.loginTimes = { 20 * HOUR, 8 * HOUR, 21 * HOUR, 19 * HOUR, 23 * HOUR, 20 * HOUR + 600, 2 * HOUR }
			-- 並べると 2, 8, 19, 20, 20:10, 21, 23 時。真ん中は 20 時
			expect(Notify.usualTimeOfDay(s)).toBe(20 * HOUR)
			-- 偶数個なら真ん中の2つのうち小さいほう
			s.loginTimes = { 10 * HOUR, 12 * HOUR, 9 * HOUR, 22 * HOUR }
			expect(Notify.usualTimeOfDay(s)).toBe(10 * HOUR)
			-- 状態は変えない（並べ替えは写しで）
			expect(s.loginTimes).toEqual({ 10 * HOUR, 12 * HOUR, 9 * HOUR, 22 * HOUR })
		end)
		it("D-196 直近のログイン時刻はクライアントに送らない", function()
			local s = newState()
			Notify.recordLogin(s, T0 + HOUR, master)
			expect(Protocol.view(s, master).loginTimes).toBe(nil)
		end)
	end)

	describe("通知の許可を求める画面（D-196 ③）", function()
		local function takeRng()
			return Rng.new(1)
		end
		-- ログインボーナスの d 日目まで受け取った状態にする
		local function receiveLoginDays(s: any, d: number)
			for i = 1, d do
				local events = {}
				Login.advance(s, T0 + (i - 1) * DAY, master, takeRng, events)
			end
		end
		local function returnFirst(s: any)
			s.stats.firstReturnAt = T0
		end

		it("D-196 初めての帰還まで出さない。帰還したら firstReturn", function()
			local s = newState()
			expect(s.settings.notifyPrompt).toEqual({ firstReturn = false, loginDay2 = false })
			expect(Notify.promptDue(s)).toBe(nil)
			expect(Protocol.view(s, master).notifyPromptDue).toBe(nil)
			returnFirst(s)
			expect(Notify.promptDue(s)).toBe("firstReturn")
			expect(Protocol.view(s, master).notifyPromptDue).toBe("firstReturn")
		end)
		it("D-196 探索の帰還で firstReturn になる（stats.firstReturnAt）", function()
			local s = newState()
			expect(exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }).ok).toBeTruthy()
			Game.advance(s, { now = T0 + DAY, master = master, online = false })
			expect(s.stats.firstReturnAt ~= nil).toBe(true)
			expect(Game.query.notifyPromptDue(s)).toBe("firstReturn")
		end)
		it(
			"D-196 D-117 出した記録は設定と一緒に保存し、ログインボーナス2日目にもう一度",
			function()
				local s = newState()
				receiveLoginDays(s, 1)
				returnFirst(s)
				local r = exec(s, { type = "MarkNotifyPrompt", stage = "firstReturn" })
				expect(r.ok).toBeTruthy()
				expect(r.events[1].type).toBe("NotifyPromptMarked")
				expect(s.settings.notifyPrompt).toEqual({ firstReturn = true, loginDay2 = false })
				expect(Notify.promptDue(s)).toBe(nil)
				-- 2日目のログインボーナスを受け取ったら loginDay2
				Login.advance(s, T0 + DAY, master, takeRng, {})
				expect(s.login.day).toBe(3)
				expect(Notify.promptDue(s)).toBe("loginDay2")
				expect(exec(s, { type = "MarkNotifyPrompt", stage = "loginDay2" }).ok).toBeTruthy()
				expect(s.settings.notifyPrompt).toEqual({ firstReturn = true, loginDay2 = true })
				expect(Notify.promptDue(s)).toBe(nil)
				-- 2周目以降も出さない
				s.login.cycle = 3
				expect(Notify.promptDue(s)).toBe(nil)
			end
		)
		it(
			"D-196 初めての帰還が2日目より後なら、2日目の機会はもう過ぎている（続けて2回出さない）",
			function()
				local s = newState()
				receiveLoginDays(s, 2)
				returnFirst(s)
				expect(Notify.promptDue(s)).toBe("firstReturn")
				expect(exec(s, { type = "MarkNotifyPrompt", stage = "firstReturn" }).ok).toBeTruthy()
				expect(s.settings.notifyPrompt).toEqual({ firstReturn = true, loginDay2 = true })
				expect(Notify.promptDue(s)).toBe(nil)
			end
		)
		it(
			"D-196 今の機会でなければ記録しない（NOT_DUE、状態は変えない）。形の違う機会は通さない",
			function()
				local s = newState()
				local before = Game._deepClone(s)
				expect(exec(s, { type = "MarkNotifyPrompt", stage = "firstReturn" }).error).toBe("NOT_DUE")
				expect(exec(s, { type = "MarkNotifyPrompt", stage = "loginDay2" }).error).toBe("NOT_DUE")
				expect(exec(s, { type = "MarkNotifyPrompt", stage = "nope" }).error).toBe("INVALID_STAGE")
				expect(s).toEqual(before)
				expect({ Protocol.validateCommand({ type = "MarkNotifyPrompt", stage = "firstReturn" }) }).toEqual({
					true,
					nil,
				})
				expect((Protocol.validateCommand({ type = "MarkNotifyPrompt", stage = "nope" }))).toBe(false)
				expect((Protocol.validateCommand({ type = "MarkNotifyPrompt" }))).toBe(false)
			end
		)
	end)

	describe("セーブの移行 version 10 → 11（D-195, D-196）", function()
		local function v10State(): any
			local s = newState()
			s.version = 10
			s.loginTimes = nil
			s.settings.notifyPrompt = nil
			s.stats.rebirths = nil
			return s
		end
		it("D-195 転生回数の累計は今いる冒険者の rebirthCount の合計を初期値にする", function()
			local s = v10State()
			local slots = s.parties[1].slots
			s.adventurers[slots[1]].rebirthCount = 2
			s.adventurers[slots[2]].rebirthCount = 1
			Migration.migrate(s, master)
			expect(s.version).toBe(Migration.CURRENT) -- v10 → 11 → 以降の版（v11 → 12 は ClientHub の D-228）
			expect(Migration.CURRENT >= 11).toBeTruthy()
			expect(s.stats.rebirths).toBe(3)
		end)
		it(
			"D-195 すでに数えている累計のほうが大きければ減らさない（解雇した分を失わない）",
			function()
				local s = v10State()
				s.adventurers[s.parties[1].slots[1]].rebirthCount = 1
				s.stats.rebirths = 5
				Migration.migrate(s, master)
				expect(s.stats.rebirths).toBe(5)
			end
		)
		it("D-196 ログイン時刻は空、許可の画面はまだ出していない", function()
			local s = Migration.migrate(v10State(), master)
			expect(s.loginTimes).toEqual({})
			expect(s.settings.notifyPrompt).toEqual(Notify.newPromptState())
			expect(s.settings.autoSell ~= nil).toBe(true)
			-- 新規のセーブも同じ初期値
			local n = newState()
			expect(n.version).toBe(Migration.CURRENT)
			expect(n.loginTimes).toEqual({})
			expect(n.settings.notifyPrompt).toEqual(Notify.newPromptState())
			-- JSON にして戻しても動く
			local decoded = serde.decode("json", serde.encode("json", s))
			Notify.recordLogin(decoded, T0 + HOUR, master)
			expect(Notify.usualTimeOfDay(decoded)).toBe(HOUR)
		end)
	end)
end
