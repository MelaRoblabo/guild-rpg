--!strict
-- 宝箱の画面の純粋なモジュール（M8-4）：開封で出た装備で誰が強くなるか（D-130・D-223）
local Formulas = require("../src/core/Formulas")
local Game = require("../src/core/Game")
local Inventory = require("../src/core/Inventory")
local Upgrades = require("../src/client/chest/Upgrades")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1_800_000_000

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local deps = { value = Formulas.bulkSellValue, canEquip = Inventory.canEquip }

	-- 武器を持っている最初の冒険者と、その武器
	local function setup(): (any, any, any)
		local s = Game.newState(master, 1, T0)
		local uids = {}
		for uid in s.adventurers do
			table.insert(uids, uid)
		end
		table.sort(uids)
		for _, uid in uids do
			local adv = s.adventurers[uid]
			local w = adv.equipment.weapon
			if w then
				return s, adv, s.equipment[w]
			end
		end
		error("武器を持つ冒険者がいない")
	end

	local function add(s: any, from: any, fields: any): string
		return Inventory.newEquipment(s, {
			baseId = fields.baseId or from.baseId,
			rarity = fields.rarity or from.rarity,
			grade = fields.grade or from.grade,
			itemLevel = fields.itemLevel or from.itemLevel,
		}).uid
	end

	describe("D-130 1つの品で強くなる冒険者（Upgrades.forItem）", function()
		it(
			"D-130 今の武器より強い武器なら、その人が強くなる（差は比べる値の差）",
			function()
				local s, adv, cur = setup()
				local uid = add(s, cur, { rarity = 6, grade = 3 })
				local list = Upgrades.forItem(s, uid, master, deps)
				local found = nil
				for _, u in list do
					if u.advUid == adv.uid then
						found = u
					end
				end
				expect(found ~= nil).toBe(true)
				local v = Formulas.bulkSellValue(s.equipment[uid], master) :: number
				local cv = Formulas.bulkSellValue(cur, master) :: number
				expect((found :: any).delta).toBe(v - cv)
				expect((found :: any).slot).toBe("weapon")
			end
		)
		it("D-130 今の武器と同じ強さなら強くならない", function()
			local s, adv, cur = setup()
			local uid = add(s, cur, {})
			for _, u in Upgrades.forItem(s, uid, master, deps) do
				expect(u.advUid == adv.uid).toBe(false)
			end
		end)
		it("D-130 枠が空なら、付けられる人は必ず強くなる（今の値は 0）", function()
			local s, adv, cur = setup()
			Inventory.unequip(s, adv, "weapon")
			local uid = add(s, cur, {})
			local found = nil
			for _, u in Upgrades.forItem(s, uid, master, deps) do
				if u.advUid == adv.uid then
					found = u
				end
			end
			expect(found ~= nil).toBe(true)
			expect((found :: any).current).toBe(0)
		end)
		it("D-130 装備中の品は候補にしない", function()
			local s, _, cur = setup()
			expect(#Upgrades.forItem(s, cur.uid, master, deps)).toBe(0)
		end)
		it("D-130 強くなる差の大きい順に並ぶ", function()
			local s, _, cur = setup()
			local uid = add(s, cur, { rarity = 6, grade = 3 })
			local list = Upgrades.forItem(s, uid, master, deps)
			for i = 2, #list do
				expect(list[i - 1].delta >= list[i].delta).toBe(true)
			end
		end)
		it("D-285 ギルドにいない（冒険中の）人は勧めない", function()
			local s, adv, cur = setup()
			local uid = add(s, cur, { rarity = 6, grade = 3 })
			local away = table.clone(deps) :: any
			away.busy = function(_s: any, advUid: string): boolean
				return advUid == adv.uid
			end
			local all = Upgrades.forItem(s, uid, master, deps)
			local some = Upgrades.forItem(s, uid, master, away)
			local found = false
			for _, u in all do
				found = found or u.advUid == adv.uid
			end
			expect(found).toBe(true)
			for _, u in some do
				expect(u.advUid ~= adv.uid).toBe(true)
			end
		end)
	end)

	describe("D-223 結果のカード（Upgrades.plan）", function()
		it("D-223 1人に1つ、1つの品は1人だけに割り当てる", function()
			local s, _, cur = setup()
			local a = add(s, cur, { rarity = 6, grade = 3 })
			local b = add(s, cur, { rarity = 5, grade = 2 })
			local c = add(s, cur, { rarity = 4, grade = 1 })
			local plan = Upgrades.plan(s, { a, b, c }, master, deps)
			local items, advs = {}, {}
			for _, u in plan do
				expect(items[u.itemUid]).toBe(nil)
				expect(advs[u.advUid]).toBe(nil)
				items[u.itemUid] = true
				advs[u.advUid] = true
			end
			expect(#plan >= 1).toBe(true)
			for i = 2, #plan do
				expect(plan[i - 1].delta >= plan[i].delta).toBe(true)
			end
		end)
		it("D-223 一番強くなる組が先頭に来る", function()
			local s, _, cur = setup()
			local weak = add(s, cur, { rarity = 2 })
			local strong = add(s, cur, { rarity = 6, grade = 3 })
			local plan = Upgrades.plan(s, { weak, strong }, master, deps)
			expect(plan[1].itemUid).toBe(strong)
		end)
		it("D-223 割り当てた組はどれも強くなる（差が正）", function()
			local s, _, cur = setup()
			local same = add(s, cur, {})
			local plan = Upgrades.plan(s, { same }, master, deps)
			for _, u in plan do
				expect(u.delta > 0).toBe(true)
			end
		end)
	end)
end
