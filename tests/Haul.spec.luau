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

	local function pileTotal(s: any): number
		local n = 0
		for _, c in Game.query.chestsByPile(s, master) do
			n += c.count
		end
		return n
	end
	local function haulTotal(h: any): number
		local n = 0
		for _, byRank in h.chests do
			for _, c in byRank do
				n += c
			end
		end
		return n
	end

	describe("D-287 D-302 帰還の獲得をパーティに積む", function()
		it(
			"D-287 D-302 オンライン中の帰還のゴールドは入れて記録し、宝箱は山に入れずパーティが持つ",
			function()
				local s = newState()
				expect(Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = first.id }, ctx(T0)).ok).toBe(
					true
				)
				local at = returnAt(s)
				local g0 = s.gold
				local p0 = pileTotal(s)
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
				expect(haulTotal(h)).toBe(ret.chests)
				expect(pileTotal(s)).toBe(p0) -- 右下の Chests には入らない
			end
		)
		it("D-302 自動再派遣の間は宝箱を積み続け、山には入れない", function()
			local s = newState()
			Game.execute(s, { type = "SetAutoRepeat", partyIndex = 1, dungeonId = first.id }, ctx(T0))
			Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = first.id }, ctx(T0))
			local p0 = pileTotal(s)
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
			expect(haulTotal(h)).toBe(chests)
			expect(pileTotal(s)).toBe(p0)
		end)
		it(
			"D-302 ClaimHaul でパーティの宝箱を山へ移して記録を消す。なければ HAUL_EMPTY",
			function()
				local s = newState()
				Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = first.id }, ctx(T0))
				Game.advance(s, ctx(returnAt(s)))
				local n = haulTotal(s.parties[1].haul)
				local gold = s.gold
				local p0 = pileTotal(s)
				local r = Game.execute(s, { type = "ClaimHaul", partyIndex = 1 }, ctx(T0))
				expect(r.ok).toBe(true)
				expect(r.events[1].runs).toBe(1)
				expect(r.events[1].chests[first.id] or 0).toBe(n)
				expect(s.parties[1].haul).toBe(nil)
				expect(pileTotal(s)).toBe(p0 + n)
				expect(s.gold).toBe(gold) -- ゴールドは帰還のときに入っている
				expect(Game.execute(s, { type = "ClaimHaul", partyIndex = 1 }, ctx(T0)).error).toBe("HAUL_EMPTY")
			end
		)
		it(
			"D-302 開けないまま次の冒険へ出たら、持っていた宝箱は受け取り箱へ（ランクのまま）",
			function()
				local s = newState()
				s.inbox = {}
				Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = first.id }, ctx(T0))
				local at = returnAt(s)
				Game.advance(s, ctx(at))
				local h = s.parties[1].haul
				local n = haulTotal(h)
				local r = Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = first.id }, ctx(at))
				expect(r.ok).toBe(true)
				expect(s.parties[1].haul).toBe(nil)
				if n > 0 then
					expect(#s.inbox).toBe(1)
					expect(s.inbox[1].source).toBe("expedition")
					local got = 0
					for _, c in s.inbox[1].rewards.chests do
						expect(c.rank ~= nil).toBe(true)
						got += c.count
					end
					expect(got).toBe(n)
				end
			end
		)
		it("D-087 D-302 クライアントへ送る haul は山ごとの数だけ（ランクを隠す）", function()
			local Protocol = require("../src/core/Protocol")
			local s = newState()
			Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = first.id }, ctx(T0))
			Game.advance(s, ctx(returnAt(s)))
			local n = haulTotal(s.parties[1].haul)
			local v = Protocol.view(s, master)
			local hv = v.parties[1].haul
			expect(type(hv.chests[first.id] or 0)).toBe("number")
			expect(hv.chests[first.id] or 0).toBe(n)
			expect(type(s.parties[1].haul.chests[first.id] or {})).toBe("table") -- 状態はランクのまま
		end)
		it(
			"D-287 D-281 留守中の帰還は積まず、宝箱は山へ（ログインのまとめで見せる）",
			function()
				local s = newState()
				Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = first.id }, ctx(T0))
				Game.advance(s, ctx(returnAt(s) + 10, false))
				expect(Game.query.expeditionOf(s, 1)).toBe(nil)
				expect(s.parties[1].haul).toBe(nil)
			end
		)
	end)

	describe("D-302 セーブ v14 → v15", function()
		it("D-302 v14 の haul（記録だけ。宝箱は山に入れ済み）は消す", function()
			local s = newState()
			s.version = 14
			s.parties[1].haul = { runs = 1, gold = 10, chests = { [first.id] = 2 }, dungeonId = first.id }
			Migration.migrate(s, master)
			expect(s.version).toBe(15)
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
				expect(s.version).toBe(Migration.CURRENT) -- 14 のあと v14 → 15（D-302）も通る
				expect(s.quests.daily.entries[1].claimed).toBe(true)
				expect(s.quests.daily.entries[2].claimed).toBe(nil)
				expect(s.quests.weekly.bonusClaimed).toBe(true)
			end
		)
	end)
end
