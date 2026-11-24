--!strict
-- 拡張の見せ方（S-22、D-071・D-237 ①）
local ExpandInfo = require("../src/client/guild/ExpandInfo")
local Game = require("../src/core/Game")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1_800_000_000

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()

	local function rowOf(rows: { any }, kind: string): any
		for _, r in rows do
			if r.kind == kind then
				return r
			end
		end
		error("ない: " .. kind)
	end

	describe("D-071 拡張の行（ExpandInfo.rows）", function()
		it("D-237 ① 踏破もお金も足りないときは両方を返す", function()
			local s = Game.newState(master, 1, T0)
			s.gold = 0
			local party = rowOf(ExpandInfo.rows(s, master), "partySlots")
			expect(party.needClear ~= nil).toBe(true)
			expect(party.shortGold).toBe(true)
			expect(party.canBuy).toBe(false)
		end)
		it("条件とお金が足りれば買える。買える行があれば NEW", function()
			local s = Game.newState(master, 1, T0)
			local roster = rowOf(ExpandInfo.rows(s, master), "rosterSize")
			s.guild.level = roster.step.guildLevel
			s.gold = roster.step.gold
			roster = rowOf(ExpandInfo.rows(s, master), "rosterSize")
			expect(roster.canBuy).toBe(true)
			expect(ExpandInfo.anyBuyable(s, master)).toBe(true)
			local r = Game.execute(
				s,
				{ type = "BuyExpansion", expansionId = roster.id },
				{ now = T0, master = master, online = true }
			)
			expect(r.ok).toBe(true)
			expect(rowOf(ExpandInfo.rows(s, master), "rosterSize").bought).toBe(roster.bought + 1)
		end)
	end)
end
