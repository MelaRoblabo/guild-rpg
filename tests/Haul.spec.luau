--!strict
-- 帰還の獲得の記録（D-287）と、クエストの受け取りへの移行（D-286 のセーブ v13 → v14）
local Game = require("../src/core/Game")
local Migration = require("../src/core/Migration")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1_800_000_000

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local first = master.dungeonList[1]

	local function ctx(now: number, online: boolean?)
		return { now = now, master = master, online = if online == nil then true else online }
	end
	local function newState(): any
		local s = Game.newState(master, 1, T0)
		Game.advance(s, ctx(T0))
		return s
	end
	local function returnAt(s: any): number
		return (Game.query.expeditionOf(s, 1) :: any).returnAt
	end

	describe("D-287 帰還の獲得をパーティに積む", function()
		it(
			"D-287 オンライン中に帰ったパーティに、持ち帰ったゴールドと山ごとの宝箱の数を積む",
			function()
				local s = newState()
				expect(Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = first.id }, ctx(T0)).ok).toBe(
					true
				)
				local at = returnAt(s)
				local g0 = s.gold
				local events = Game.advance(s, ctx(at))
				local ret
				for _, e in events do
					if e.type == "ExpeditionReturned" then
						ret = e
					end
				end
				local h = s.parties[1].haul
				expect(h ~= nil).toBe(true)
				expect(h.runs).toBe(1)
				expect(h.dungeonId).toBe(first.id)
				expect(h.gold).toBe(ret.gold + ret.itemsSoldGold)
				expect(h.gold).toBe(s.gold - g0)
				expect(h.chests[first.id] or 0).toBe(ret.chests)
			end
		)
		it("D-287 自動再派遣の間は積み続け、押すまで消えない", function()
			local s = newState()
			Game.execute(s, { type = "SetAutoRepeat", partyIndex = 1, dungeonId = first.id }, ctx(T0))
			Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = first.id }, ctx(T0))
			local chests = 0
			for _ = 1, 3 do
				for _, e in Game.advance(s, ctx(returnAt(s))) do
					if e.type == "ExpeditionReturned" then
						chests += e.chests
					end
				end
			end
			local h = s.parties[1].haul
			expect(h.runs).toBe(3)
			expect(h.chests[first.id] or 0).toBe(chests)
		end)
		it("D-287 AckHaul で記録を消す。記録がなければ HAUL_EMPTY", function()
			local s = newState()
			Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = first.id }, ctx(T0))
			Game.advance(s, ctx(returnAt(s)))
			local gold = s.gold
			local r = Game.execute(s, { type = "AckHaul", partyIndex = 1 }, ctx(T0))
			expect(r.ok).toBe(true)
			expect(r.events[1].haul.runs).toBe(1)
			expect(s.parties[1].haul).toBe(nil)
			expect(s.gold).toBe(gold) -- 報酬は帰還のときに入っている
			expect(Game.execute(s, { type = "AckHaul", partyIndex = 1 }, ctx(T0)).error).toBe("HAUL_EMPTY")
		end)
		it("D-287 D-281 留守中の帰還は積まない（ログインのまとめで見せる）", function()
			local s = newState()
			Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = first.id }, ctx(T0))
			Game.advance(s, ctx(returnAt(s) + 10, false))
			expect(Game.query.expeditionOf(s, 1)).toBe(nil)
			expect(s.parties[1].haul).toBe(nil)
		end)
	end)

	describe("D-286 セーブ v13 → v14", function()
		it(
			"D-286 前の版で達成済みのお題とボーナスは受け取り済みにする（受け取り箱へ入れ済み）",
			function()
				local s = newState()
				s.version = 13
				s.quests.daily.entries = {
					{ questId = "qst_daily_expeditions", target = 1, progress = 1, done = true },
					{ questId = "qst_daily_chests", target = 2, progress = 0, done = false },
				}
				s.quests.daily.bonusDone = false
				s.quests.weekly.bonusDone = true
				Migration.migrate(s, master)
				expect(s.version).toBe(14)
				expect(s.quests.daily.entries[1].claimed).toBe(true)
				expect(s.quests.daily.entries[2].claimed).toBe(nil)
				expect(s.quests.weekly.bonusClaimed).toBe(true)
			end
		)
	end)
end
