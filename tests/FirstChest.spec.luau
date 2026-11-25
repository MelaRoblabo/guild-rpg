--!strict
-- 初めて開ける宝箱の確定の装備（D-246 ①）
local Chest = require("../src/core/Chest")
local Formulas = require("../src/core/Formulas")
local Game = require("../src/core/Game")
local Inventory = require("../src/core/Inventory")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1_800_000_000
local PILE = "dng_graveyard"

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local F = master.raw.LootTables.firstChest
	local function ctx()
		return { now = T0, master = master, online = true }
	end
	local function openOne(s: any): any
		local r = Game.execute(s, { type = "OpenChests", pileKey = PILE, count = 1 }, ctx())
		assert(r.ok, r.error)
		local e = r.events[1]
		return e.normal[1] or e.special[1]
	end
	-- パーティ1の誰かが、その品で今の装備より強くなるか
	local function upgradesSomeone(s: any, item: any): boolean
		local v = Formulas.bulkSellValue(item, master) or 0
		for _, uid in s.parties[1].slots do
			local adv = s.adventurers[uid]
			if adv and Inventory.canEquip(adv.jobId, item.baseId, master) then
				local cur = s.equipment[adv.equipment[F.slot]]
				local cv = if cur then Formulas.bulkSellValue(cur, master) or 0 else 0
				if v > cv then
					return true
				end
			end
		end
		return false
	end

	describe("D-246 ① 初めて開ける宝箱", function()
		it(
			"どのシードでも、パーティの誰かが強くなる装備が1つ入り、自動売却されない",
			function()
				for seed = 1, 30 do
					local s = Game.newState(master, seed, T0)
					Chest.add(s, PILE, 1, 2)
					local res = openOne(s)
					expect(res.firstUpgrade ~= nil).toBe(true)
					expect(table.find(res.equipmentUids, res.firstUpgrade) ~= nil).toBe(true)
					local item = s.equipment[res.firstUpgrade]
					expect(item ~= nil).toBe(true)
					expect(item.rarity).toBe(F.rarity)
					expect(item.grade).toBe(F.grade)
					expect(master.equipmentBases[item.baseId].slot).toBe(F.slot)
					expect(upgradesSomeone(s, item)).toBe(true)
				end
			end
		)
		it("2個目からは入らない（まとめて開けても最初の1個だけ）", function()
			local s = Game.newState(master, 7, T0)
			Chest.add(s, PILE, 1, 4)
			local r = Game.execute(s, { type = "OpenChests", pileKey = PILE, count = 3 }, ctx())
			local n = 0
			for _, list in { r.events[1].normal, r.events[1].special } do
				for _, res in list do
					if res.firstUpgrade then
						n += 1
					end
				end
			end
			expect(n).toBe(1)
			expect(openOne(s).firstUpgrade).toBe(nil)
		end)
		it("一度でも宝箱を開けたセーブには入らない", function()
			local s = Game.newState(master, 3, T0)
			s.stats.firstChestOpenedAt = T0 - 10
			Chest.add(s, PILE, 1, 1)
			expect(openOne(s).firstUpgrade).toBe(nil)
		end)
	end)
end
