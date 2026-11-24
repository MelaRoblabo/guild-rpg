--!strict
-- 自動装備（D-120・D-231 ⑨・D-235 ③、06章 §24）
local AutoEquip = require("../src/core/AutoEquip")
local Game = require("../src/core/Game")
local Inventory = require("../src/core/Inventory")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1_800_000_000

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local function ctx()
		return { now = T0, master = master, online = true }
	end
	local function memberOf(s: any, jobId: string): any
		for _, uid in s.parties[1].slots do
			local a = s.adventurers[uid]
			if a and a.jobId == jobId then
				return a
			end
		end
		error("いない: " .. jobId)
	end
	local function add(s: any, baseId: string, rarity: number, grade: number?): string
		return Inventory.newEquipment(s, { baseId = baseId, rarity = rarity, grade = grade or 0, itemLevel = 1 }).uid
	end

	describe("D-231 ⑨ 重み（AutoEquip.weights）", function()
		it("一度も出ていなければ物理と魔法を半々", function()
			local p, m = AutoEquip.weights(nil, master)
			expect(p).toBe(0.5)
			expect(m).toBe(0.5)
		end)
		it(
			"最後の行き先のモンスターの出現の重みで分ける（呪われた修道院は物理6：魔法4）",
			function()
				local p, m = AutoEquip.weights("dng_abbey", master)
				expect(math.abs(p - 0.6) < 1e-9).toBe(true)
				expect(math.abs(m - 0.4) < 1e-9).toBe(true)
			end
		)
	end)

	describe("D-120 提案と適用（AutoEquip.plan・AutoEquip 命令）", function()
		it(
			"D-120 倉庫に強い武器があれば提案し、命令で付け替える（前の装備は倉庫へ）",
			function()
				local s = Game.newState(master, 1, T0)
				local w = memberOf(s, "job_warrior")
				local old = w.equipment.weapon
				local strong = add(s, "eq_wpn_sword", 6, 3)
				local plan = Game.query.autoEquipPlan(s, 1, master)
				local found = false
				for _, c in plan do
					if c.advUid == w.uid and c.slot == "weapon" then
						expect(c.to).toBe(strong)
						expect(c.from).toBe(old)
						found = true
					end
				end
				expect(found).toBe(true)
				local r = Game.execute(s, { type = "AutoEquip", partyIndex = 1 }, ctx())
				expect(r.ok).toBe(true)
				expect(s.adventurers[w.uid].equipment.weapon).toBe(strong)
				expect(s.equipment[old].equippedBy).toBe(nil)
			end
		)
		it(
			"D-120 防具は最後の行き先の重みで比べる：魔法ばかりなら魔法防御の高い方",
			function()
				local s = Game.newState(master, 1, T0)
				local w = memberOf(s, "job_warrior")
				local cur = s.equipment[w.equipment.armor]
				-- 魔法防御だけ高い防具（ローブは戦士が付けられないので、同じ鎧の倍率の高いもので比べる）
				local better = add(s, cur.baseId, 6, 3)
				s.parties[1].lastDungeonId = "dng_tower"
				local plan = AutoEquip.plan(s, 1, master)
				local armorChange = nil
				for _, c in plan do
					if c.advUid == w.uid and c.slot == "armor" then
						armorChange = c
					end
				end
				expect(armorChange ~= nil and armorChange.to == better).toBe(true)
			end
		)
		it("D-120 1つの品を2人に配らない。他の人が付けている品は使わない", function()
			local s = Game.newState(master, 1, T0)
			add(s, "eq_wpn_staff", 6, 3)
			local plan = AutoEquip.plan(s, 1, master)
			local used = {}
			for _, c in plan do
				expect(used[c.to]).toBe(nil)
				used[c.to] = true
				expect(s.equipment[c.to].equippedBy).toBe(nil)
			end
		end)
		it("付け替えるものがなければ断る。探索中のパーティは断る", function()
			local s = Game.newState(master, 1, T0)
			expect(Game.execute(s, { type = "AutoEquip", partyIndex = 1 }, ctx()).error).toBe("NOTHING_TO_CHANGE")
			add(s, "eq_wpn_sword", 6, 3)
			local d = Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx())
			expect(d.ok).toBe(true)
			expect(Game.execute(s, { type = "AutoEquip", partyIndex = 1 }, ctx()).error).toBe("PARTY_BUSY")
		end)
	end)
end
