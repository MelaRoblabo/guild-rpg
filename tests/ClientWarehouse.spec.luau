--!strict
-- 倉庫の画面の純粋なモジュール（M8-6）：並べ替え・条件の一括売却・アイテムのタブ（D-119・D-120・D-167・D-231 ⑮）
local Formulas = require("../src/core/Formulas")
local Game = require("../src/core/Game")
local Inventory = require("../src/core/Inventory")
local Stock = require("../src/client/warehouse/Stock")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1_800_000_000

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local deps = { value = Formulas.bulkSellValue, price = Inventory.equipmentSellPrice }

	local function state(): any
		local s = Game.newState(master, 1, T0)
		return s
	end
	local function add(s: any, fields: any): string
		return Inventory.newEquipment(s, {
			baseId = fields.baseId or "eq_wpn_sword",
			rarity = fields.rarity or 1,
			grade = fields.grade or 0,
			itemLevel = fields.itemLevel or 1,
			modifierId = fields.modifierId,
			modifierValue = fields.modifierValue,
		}).uid
	end
	local function prefs(sort: string, desc: boolean?): any
		return { whSort = sort, whDesc = if desc == nil then true else desc }
	end

	describe("D-119 倉庫の一覧（Stock.list）", function()
		it("装備中の品は出さず、その枠の倉庫の品だけ", function()
			local s = state()
			local a = add(s, { rarity = 2 })
			local b = add(s, { baseId = "eq_arm_robe" })
			local list = Stock.list(s, "weapon", prefs("rarity"), master, deps)
			expect(table.find(list, a) ~= nil).toBe(true)
			expect(table.find(list, b)).toBe(nil)
			for _, uid in list do
				expect(s.equipment[uid].equippedBy).toBe(nil)
			end
		end)
		it("D-119 レアリティの高い順・低い順。同じなら新しい品を先に", function()
			local s = state()
			local low = add(s, { rarity = 1 })
			local high = add(s, { rarity = 4 })
			local high2 = add(s, { rarity = 4 })
			local list = Stock.list(s, "weapon", prefs("rarity"), master, deps)
			expect(list[1]).toBe(high2)
			expect(list[2]).toBe(high)
			expect(list[#list]).toBe(low)
			local asc = Stock.list(s, "weapon", prefs("rarity", false), master, deps)
			expect(asc[1]).toBe(low)
		end)
		it("D-119 新しい順・売却額の順", function()
			local s = state()
			local first = add(s, { rarity = 3 })
			local last = add(s, { rarity = 1 })
			expect(Stock.list(s, "weapon", prefs("new"), master, deps)[1]).toBe(last)
			expect(Stock.list(s, "weapon", prefs("new", false), master, deps)[1]).toBe(first)
			local bySell = Stock.list(s, "weapon", prefs("sell"), master, deps)
			expect(bySell[1]).toBe(first)
		end)
	end)

	describe("D-120 条件の一括売却（Stock.bulkPlan）", function()
		it(
			"D-231 ⑮ 上限以下だけ。修飾語・保護・装備中は売らない。合計は売却額の和",
			function()
				local s = state()
				local a = add(s, { rarity = 2 })
				local b = add(s, { rarity = 3 })
				local over = add(s, { rarity = 4 })
				local modded = add(s, { rarity = 1, modifierId = "mod_swift", modifierValue = 2 })
				local locked = add(s, { rarity = 1 })
				s.equipment[locked].locked = true
				local uids, total = Stock.bulkPlan(s, "weapon", 3, master, deps)
				expect(table.find(uids, a) ~= nil).toBe(true)
				expect(table.find(uids, b) ~= nil).toBe(true)
				expect(table.find(uids, over)).toBe(nil)
				expect(table.find(uids, modded)).toBe(nil)
				expect(table.find(uids, locked)).toBe(nil)
				for _, uid in uids do
					expect(s.equipment[uid].equippedBy).toBe(nil)
				end
				expect(total).toBe(Stock.total(s, uids, master, deps))
				-- Sell コマンドで売れる（core と同じ判定）
				local r = Game.execute(
					s,
					{ type = "Sell", equipmentUids = uids },
					{ now = T0, master = master, online = true }
				)
				expect(r.ok).toBe(true)
			end
		)
	end)

	describe("D-167 アイテムのタブ（Stock.items）", function()
		it("チケット・ポーションの数だけ（売却用アイテムは出さない）", function()
			local s = state()
			s.items = { itm_slot_ticket = 5, itm_bone_fragment = 3, itm_potion_appearance_change = 1 }
			local rows = Stock.items(s, master)
			local ids = {}
			for _, r in rows do
				ids[r.itemId] = r.count
			end
			expect(ids.itm_slot_ticket).toBe(5)
			expect(ids.itm_potion_appearance_change).toBe(1)
			expect(ids.itm_bone_fragment).toBe(nil)
		end)
	end)
end
