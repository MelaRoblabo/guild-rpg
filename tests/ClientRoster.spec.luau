--!strict
-- 冒険者の画面の純粋なモジュール（M8-6）：一覧の絞り込み・並べ替え、倉庫にもっと良い装備があるか（D-117・D-119・§5.1）
local Formulas = require("../src/core/Formulas")
local Game = require("../src/core/Game")
local Inventory = require("../src/core/Inventory")
local Party = require("../src/core/Party")
local Roster = require("../src/client/adventurers/Roster")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1_800_000_000

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local deps = {
		snapshot = Game.query.snapshot,
		busy = Party.isAdventurerBusy,
		find = Party.find,
		value = Formulas.bulkSellValue,
		canEquip = Inventory.canEquip,
	}
	local function prefs(sort: string, desc: boolean?): any
		return { advSort = sort, advDesc = if desc == nil then true else desc }
	end

	describe("D-119 冒険者の一覧（Roster.list）", function()
		it("D-119 Lv の高い順・低い順", function()
			local s = Game.newState(master, 1, T0)
			local uids = Roster.list(s, "all", "all", prefs("level"), master, deps)
			local top = s.adventurers[uids[1]]
			top.level = 9
			uids = Roster.list(s, "all", "all", prefs("level"), master, deps)
			expect(uids[1]).toBe(top.uid)
			local asc = Roster.list(s, "all", "all", prefs("level", false), master, deps)
			expect(asc[#asc]).toBe(top.uid)
		end)
		it("D-119 職業系統で絞る", function()
			local s = Game.newState(master, 1, T0)
			for _, uid in Roster.list(s, "mage", "all", prefs("level"), master, deps) do
				expect(master.jobs[s.adventurers[uid].jobId].line).toBe("mage")
			end
			local all = Roster.list(s, "all", "all", prefs("level"), master, deps)
			local count = 0
			for _ in s.adventurers do
				count += 1
			end
			expect(#all).toBe(count)
		end)
		it("状態で絞る：初期の4人はパーティにいて待機", function()
			local s = Game.newState(master, 1, T0)
			expect(#Roster.list(s, "all", "wait", prefs("level"), master, deps) > 0).toBe(true)
			expect(#Roster.list(s, "all", "exploring", prefs("level"), master, deps)).toBe(0)
		end)
		it("攻撃力の順は実効の攻撃力（snapshot.atk）", function()
			local s = Game.newState(master, 1, T0)
			local uids = Roster.list(s, "all", "all", prefs("attack"), master, deps)
			for i = 2, #uids do
				local a = Game.query.snapshot(s, uids[i - 1], master).atk
				local b = Game.query.snapshot(s, uids[i], master).atk
				expect(a >= b).toBe(true)
			end
		end)
	end)

	describe("§5.1 倉庫にもっと良い装備があるか（Roster.betterGear）", function()
		it("付けられる、比べる値の高い武器が倉庫にあれば true。補助は比べない", function()
			local s = Game.newState(master, 1, T0)
			local adv = nil
			for _, a in s.adventurers do
				if a.equipment.weapon then
					adv = a
				end
			end
			assert(adv, "武器を持つ冒険者がいない")
			expect(Roster.betterGear(s, adv, "weapon", master, deps)).toBe(false)
			local cur = s.equipment[adv.equipment.weapon]
			Inventory.newEquipment(s, { baseId = cur.baseId, rarity = 6, grade = 3, itemLevel = 9 })
			expect(Roster.betterGear(s, adv, "weapon", master, deps)).toBe(true)
			expect(Roster.anyBetterGear(s, adv, master, deps)).toBe(true)
			expect(Roster.betterGear(s, adv, "sub", master, deps)).toBe(false)
		end)
	end)
end
