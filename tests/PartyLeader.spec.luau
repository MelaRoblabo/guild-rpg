--!strict
local Game = require("../src/core/Game")
local Party = require("../src/core/Party")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1767225600

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()

	local function ctx()
		return { now = T0, master = master, online = true }
	end

	local function newState()
		local s = Game.newState(master, 1, T0)
		s.gold = 100000
		return s
	end

	describe("D-271 パーティのリーダー", function()
		it("最初は隊列1番の人", function()
			local s = newState()
			expect(Party.leader(s, 1)).toBe(s.parties[1].slots[1])
		end)
		it("パーティの面から変えられる。探索中でも変えられる", function()
			local s = newState()
			local second = s.parties[1].slots[2]
			local r = Game.execute(s, { type = "SetPartyLeader", partyIndex = 1, adventurerUid = second }, ctx())
			expect(r.ok).toBe(true)
			expect(Party.leader(s, 1)).toBe(second)
			Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx())
			local third = s.parties[1].slots[3]
			expect(Game.execute(s, { type = "SetPartyLeader", partyIndex = 1, adventurerUid = third }, ctx()).ok).toBe(
				true
			)
			expect(Party.leader(s, 1)).toBe(third)
		end)
		it("パーティにいない人はリーダーにできない", function()
			local s = newState()
			local r = Game.execute(s, { type = "SetPartyLeader", partyIndex = 1, adventurerUid = "adv_999" }, ctx())
			expect(r.error).toBe("ADVENTURER_NOT_IN_PARTY")
		end)
		it(
			"リーダーが外れたら、いちばん前にいる人がリーダー。外れた人が戻っても勝手に戻らない",
			function()
				local s = newState()
				local first = s.parties[1].slots[1]
				local second = s.parties[1].slots[2]
				local third = s.parties[1].slots[3]
				Game.execute(s, { type = "SetPartyLeader", partyIndex = 1, adventurerUid = third }, ctx())
				-- 3番（リーダー）を外す
				Game.execute(s, { type = "SetPartySlot", partyIndex = 1, slot = 3 }, ctx())
				expect(Party.leader(s, 1)).toBe(first)
				-- 戻しても、リーダーは今のいちばん前の人のまま
				Game.execute(s, { type = "SetPartySlot", partyIndex = 1, slot = 3, adventurerUid = third }, ctx())
				expect(Party.leader(s, 1)).toBe(first)
				local _ = second
			end
		)
		it("1番が空いていれば、その次の人", function()
			local s = newState()
			local second = s.parties[1].slots[2]
			Game.execute(s, { type = "SetPartySlot", partyIndex = 1, slot = 1 }, ctx())
			expect(Party.leader(s, 1)).toBe(second)
		end)
	end)
end
