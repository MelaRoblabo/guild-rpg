--!strict
-- 旅の商人の品の差（D-204・D-231 ⑭）
local Formulas = require("../src/core/Formulas")
local Game = require("../src/core/Game")
local Inventory = require("../src/core/Inventory")
local MerchantView = require("../src/client/event/MerchantView")
local Party = require("../src/core/Party")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1_800_000_000

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local deps = {
		value = Formulas.bulkSellValue,
		canEquip = Inventory.canEquip,
		equipMult = Formulas.equipMult,
		expPct = Formulas.equipExpPct,
		memberDef = Party.memberDef,
		snapshot = Formulas.memberSnapshot,
	}

	describe("D-231 ⑭ 商人の品で一番強くなる差（MerchantView.best）", function()
		it("強い武器なら差を返し、弱ければ nil", function()
			local s = Game.newState(master, 1, T0)
			local strong = { baseId = "eq_wpn_sword", rarity = 6, grade = 3, itemLevel = 9 }
			local weak = { baseId = "eq_wpn_sword", rarity = 1, grade = 0, itemLevel = 1 }
			local b = MerchantView.best(s, strong, master, deps)
			expect(b ~= nil and (b :: any).delta > 0).toBe(true)
			expect(MerchantView.best(s, weak, master, deps)).toBe(nil)
		end)
		it(
			"護符は倍率で返す（護符を付けている人がいなければ、空きの人と比べる）",
			function()
				local s = Game.newState(master, 1, T0)
				local amulet = { baseId = "eq_sub_amulet_learning", rarity = 5, grade = 2, itemLevel = 9 }
				for _, a in s.adventurers do
					if a.equipment.sub then
						s.equipment[a.equipment.sub].equippedBy = nil
						a.equipment.sub = nil
					end
				end
				local b = MerchantView.best(s, amulet, master, deps)
				expect(b ~= nil and (b :: any).ratio ~= nil and (b :: any).ratio > 1).toBe(true)
			end
		)
	end)
end
