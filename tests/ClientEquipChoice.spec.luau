--!strict
-- 装備の選択の純粋なモジュール（M8-6）：候補の並び・補助の種類ごとの差・付け替えたときの値（D-130・D-231 ⑭・D-232 ⑥）
local EquipChoice = require("../src/client/adventurers/EquipChoice")
local Formulas = require("../src/core/Formulas")
local Game = require("../src/core/Game")
local Inventory = require("../src/core/Inventory")
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

	local function warrior(s: any): any
		for _, a in s.adventurers do
			if a.jobId == "job_warrior" then
				return a
			end
		end
		error("戦士がいない")
	end
	local function add(s: any, baseId: string, rarity: number, grade: number?): string
		return Inventory.newEquipment(s, { baseId = baseId, rarity = rarity, grade = grade or 0, itemLevel = 1 }).uid
	end

	describe("D-231 ⑭ 候補（EquipChoice.candidates）", function()
		it("倉庫の品だけ、付けられる品だけ。武器は差の大きい順", function()
			local s = Game.newState(master, 1, T0)
			local adv = warrior(s)
			local weak = add(s, "eq_wpn_sword", 1)
			local strong = add(s, "eq_wpn_sword", 5, 2)
			local staff = add(s, "eq_wpn_staff", 6) -- 戦士は杖を付けられない
			local list = EquipChoice.candidates(s, adv, "weapon", master, deps)
			expect(list[1].uid).toBe(strong)
			local ids = {}
			for _, c in list do
				ids[c.uid] = true
				expect(s.equipment[c.uid].equippedBy).toBe(nil)
			end
			expect(ids[weak]).toBe(true)
			expect(ids[staff]).toBe(nil)
		end)
		it("D-232 ⑥ 補助は今と同じ種類→指輪→護符の順。護符は倍率も返す", function()
			local s = Game.newState(master, 1, T0)
			local adv = warrior(s) -- 初期は盾（バックラー）
			local amulet = add(s, "eq_sub_amulet_learning", 3)
			local ring = add(s, "eq_sub_ring_power", 3)
			local shield = add(s, "eq_sub_buckler", 4)
			local list = EquipChoice.candidates(s, adv, "sub", master, deps)
			expect(list[1].uid).toBe(shield)
			expect(list[2].uid).toBe(ring)
			expect(list[3].uid).toBe(amulet)
			expect(list[3].ratio ~= nil and list[3].ratio > 1).toBe(true)
			expect(list[2].delta > 0).toBe(true)
		end)
	end)

	describe("D-130 付け替えたときの値（EquipChoice.compare）", function()
		it("強い武器なら攻撃が上がる。外すと下がる。変わる値だけ", function()
			local s = Game.newState(master, 1, T0)
			local adv = warrior(s)
			local strong = add(s, "eq_wpn_sword", 6, 3)
			local rows = EquipChoice.compare(s, adv, "weapon", strong, master, deps)
			expect(#rows).toBe(1)
			expect(rows[1].key).toBe("atk")
			expect(rows[1].after > rows[1].before).toBe(true)
			local off = EquipChoice.compare(s, adv, "weapon", nil, master, deps)
			expect(off[1].after < off[1].before).toBe(true)
		end)
	end)
end
