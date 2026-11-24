--!strict
-- 最後の行き先（D-228）：「同じ所へ再出発」の行き先をパーティに残す
local Game = require("../src/core/Game")
local Migration = require("../src/core/Migration")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1_800_000_000

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()

	local function ctx(now: number)
		return { now = now, master = master, online = true }
	end
	local function newState(): any
		return Game.newState(master, 1, T0)
	end
	local firstDungeon = master.dungeonList[1].id

	describe("D-228 最後の行き先", function()
		it("D-228 新しいセーブでは最後の行き先はない", function()
			local s = newState()
			expect(s.parties[1].lastDungeonId).toBe(nil)
		end)
		it("D-228 派遣するとパーティに最後の行き先が残る", function()
			local s = newState()
			local r = Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = firstDungeon }, ctx(T0))
			expect(r.ok).toBe(true)
			expect(s.parties[1].lastDungeonId).toBe(firstDungeon)
		end)
		it("D-228 帰ってきたあとも最後の行き先は残る（入り直しても Go できる）", function()
			local s = newState()
			Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = firstDungeon }, ctx(T0))
			Game.advance(s, ctx(T0 + 100_000))
			expect(next(s.expeditions)).toBe(nil)
			expect(s.parties[1].lastDungeonId).toBe(firstDungeon)
		end)
	end)

	describe("D-228 セーブの移行 version 11 → 12", function()
		it("D-228 探索中なら、その行き先を最後の行き先にする", function()
			local s = newState()
			Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = firstDungeon }, ctx(T0))
			s.parties[1].lastDungeonId = nil
			s.version = 11
			Migration.migrate(s, master)
			expect(s.version).toBe(Migration.CURRENT)
			expect(s.parties[1].lastDungeonId).toBe(firstDungeon)
		end)
		it("D-228 探索中でなければ自動再派遣の行き先、それもなければなし", function()
			local s = newState()
			s.parties[1].autoRepeat = { dungeonId = firstDungeon }
			s.version = 11
			Migration.migrate(s, master)
			expect(s.parties[1].lastDungeonId).toBe(firstDungeon)
			local s2 = newState()
			s2.version = 11
			Migration.migrate(s2, master)
			expect(s2.parties[1].lastDungeonId).toBe(nil)
		end)
	end)
end
