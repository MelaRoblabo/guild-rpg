--!strict
-- 自動売却の初期値・売却用アイテムの自動売却・一括売却（D-167, D-175、06章 §17）
local Chest = require("../src/core/Chest")
local Formulas = require("../src/core/Formulas")
local Game = require("../src/core/Game")
local Inventory = require("../src/core/Inventory")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1767225600

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()

	local function ctx(now: number?)
		return { now = now or T0, master = master, online = true }
	end
	local function exec(s: any, cmd: any): any
		return Game.execute(s, cmd, ctx())
	end
	local function newState()
		return Game.newState(master, 1, T0)
	end
	-- 職業 jobId の冒険者（初期の4人から探す）
	local function advOf(s: any, jobId: string): any
		for _, a in s.adventurers do
			if a.jobId == jobId then
				return a
			end
		end
		error("いない: " .. jobId)
	end
	local function newItem(s: any, baseId: string, rarity: number, grade: number?): any
		return Inventory.newEquipment(s, { baseId = baseId, rarity = rarity, grade = grade or 0, itemLevel = 1 })
	end
	local function sellableIds(): { [string]: boolean }
		local out = {}
		for id, item in master.items do
			if item.kind == "sellable" then
				out[id] = true
			end
		end
		return out
	end

	describe("自動売却の初期値（D-167）", function()
		it(
			"D-167 新しいセーブは自動売却がオン（コモン・アンコモン、修飾語つきは残す）",
			function()
				local s = newState()
				expect(s.settings.autoSell).toEqual({ enabled = true, maxRarity = 2, keepModified = true })
				expect(s.settings.autoSell).toEqual(master.raw.StarterSet.autoSell)
			end
		)
		it("D-167 初期値のまま開けると、アンコモン以下は修飾語つきだけ残る", function()
			local s = newState()
			s.expansions.warehouseSize = 100000
			Chest.add(s, "dng_ruins", 1, 60)
			Chest.add(s, "dng_ruins", 2, 60)
			local r = exec(s, { type = "OpenChests", pileKey = "dng_ruins", count = 120 })
			expect(r.ok).toBeTruthy()
			for _, e in s.equipment do
				if e.equippedBy == nil then
					expect(e.modifierId ~= nil).toBeTruthy()
				end
			end
			local soldCount = 0
			for _, list in { r.events[1].normal, r.events[1].special } do
				for _, res in list do
					soldCount += #res.autoSold
				end
			end
			expect(soldCount > 0).toBeTruthy()
		end)
		it("D-167 マスターデータの初期値が壊れていれば起動しない", function()
			local MasterData = require("../src/core/MasterData")
			local bad = Fixtures.clone(require("../src/data"))
			bad.StarterSet.autoSell.maxRarity = 99
			expect(function()
				MasterData.load(bad)
			end).toThrow("StarterSet.autoSell.maxRarity")
		end)
	end)

	describe("売却用アイテムは常に自動で売る（D-167）", function()
		it(
			"D-167 開封で出た売却用アイテムは、自動売却を切っていても売ってゴールドになる",
			function()
				local s = newState()
				s.expansions.warehouseSize = 100000
				exec(s, { type = "SetAutoSell", enabled = false })
				Chest.add(s, "dng_ruins", 1, 200)
				local gold0 = s.gold
				local r = exec(s, { type = "OpenChests", pileKey = "dng_ruins", count = 200 })
				local fromMaterials, fromGold, materials = 0, 0, 0
				for _, list in { r.events[1].normal, r.events[1].special } do
					for _, res in list do
						fromMaterials += res.soldItemsGold
						fromGold += res.gold
						for id, n in res.soldItems do
							expect(master.items[id].kind).toBe("sellable")
							materials += n
						end
						for id in res.items do
							expect(master.items[id].kind ~= "sellable").toBeTruthy()
						end
					end
				end
				expect(materials > 0).toBeTruthy()
				expect(s.gold).toBe(gold0 + fromMaterials + fromGold)
				local sellable = sellableIds()
				for id in s.items do
					expect(sellable[id]).toBe(nil) -- items に入れない（03章）
				end
			end
		)
		it("D-167 帰還で持ち帰った売却用アイテムも売る（items に入らない）", function()
			local s = newState()
			exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" })
			local e = Game.query.expeditionOf(s, 1)
			e.log.rewards.items = { itm_bone_fragment = 3, itm_slot_ticket = 1 }
			local gold0 = s.gold
			local events = Game.advance(s, ctx(e.returnAt))
			local price = master.items.itm_bone_fragment.sellPrice * 3
			expect(events[1].itemsSoldGold).toBe(price)
			expect(s.gold).toBe(gold0 + e.log.rewards.gold + price)
			expect(s.items.itm_bone_fragment).toBe(nil)
			expect(s.items.itm_slot_ticket).toBe(1) -- チケットは売らない
		end)
	end)

	describe("一括売却（D-167, D-175、06章 §17）", function()
		-- 戦士の今の剣をレア（3）にして、コモンの剣が「弱い」になる状態
		local function withStrongSword()
			local s = newState()
			local warrior = advOf(s, "job_warrior")
			s.equipment[warrior.equipment.weapon].rarity = 3
			return s, warrior
		end

		it("D-167 付けられる全員の今の装備より性能値が低い装備を売る", function()
			local s = withStrongSword()
			local weak = newItem(s, "eq_wpn_sword", 1)
			local price = Inventory.equipmentSellPrice(weak, master)
			local gold0 = s.gold
			local r = exec(s, { type = "BulkSell", equipmentUids = { weak.uid } })
			expect(r.ok).toBeTruthy()
			expect(s.equipment[weak.uid]).toBe(nil)
			expect(s.gold).toBe(gold0 + price)
			expect(r.events[1].equipmentUids).toEqual({ weak.uid })
		end)
		it("D-167 同じ性能値・より強い装備は売らない", function()
			local s = newState() -- 戦士の剣はコモン+0
			local same = newItem(s, "eq_wpn_sword", 1)
			local better = newItem(s, "eq_wpn_sword", 2)
			local r = exec(s, { type = "BulkSell", equipmentUids = { same.uid, better.uid } })
			expect(r.error).toBe("NOTHING_TO_SELL")
			expect(s.equipment[same.uid] ~= nil and s.equipment[better.uid] ~= nil).toBeTruthy()
		end)
		it("D-175 その枠が空いている冒険者が1人でもいれば売らない", function()
			local s, warrior = withStrongSword()
			local weak = newItem(s, "eq_wpn_sword", 1)
			-- 剣を付けられる騎士を、武器なしで加える
			local knight = table.clone(warrior)
			knight.uid = "adv_999"
			knight.jobId = "job_knight"
			knight.equipment = {}
			s.adventurers[knight.uid] = knight
			expect(exec(s, { type = "BulkSell", equipmentUids = { weak.uid } }).error).toBe("NOTHING_TO_SELL")
			-- 騎士にも強い剣を付ければ売れる
			local strong = newItem(s, "eq_wpn_sword", 3)
			strong.equippedBy = knight.uid
			knight.equipment.weapon = strong.uid
			expect(exec(s, { type = "BulkSell", equipmentUids = { weak.uid } }).ok).toBeTruthy()
		end)
		it("D-175 付けられる冒険者の誰か1人より強ければ売らない", function()
			local s, warrior = withStrongSword()
			local knight = table.clone(warrior)
			knight.uid = "adv_999"
			knight.jobId = "job_knight"
			local mid = newItem(s, "eq_wpn_sword", 1, 3) -- コモン+3
			local knightSword = newItem(s, "eq_wpn_sword", 1, 0) -- コモン+0（mid より弱い）
			knightSword.equippedBy = knight.uid
			knight.equipment = { weapon = knightSword.uid }
			s.adventurers[knight.uid] = knight
			expect(exec(s, { type = "BulkSell", equipmentUids = { mid.uid } }).error).toBe("NOTHING_TO_SELL")
		end)
		it("D-175 付けられる冒険者が1人もいなければ売らない", function()
			local s = newState()
			local warrior = advOf(s, "job_warrior")
			s.equipment[warrior.equipment.weapon].equippedBy = nil
			s.adventurers[warrior.uid] = nil
			local weak = newItem(s, "eq_wpn_sword", 1)
			expect(exec(s, { type = "BulkSell", equipmentUids = { weak.uid } }).error).toBe("NOTHING_TO_SELL")
		end)
		it("D-175 防具は物理防御＋魔法防御の合計で比べる", function()
			-- 物理防御だけなら同じ、合計では低い重鎧を足したデータ
			local m = Fixtures.master(function(d)
				local chain = nil
				for _, b in d.EquipmentBases do
					if b.id == "eq_arm_chainmail" then
						chain = b
					end
				end
				local row = Fixtures.clone(chain)
				row.id = "eq_arm_test_plate"
				row.mdef = 0
				table.insert(d.EquipmentBases, row)
			end)
			local s = Game.newState(m, 1, T0)
			local chain = m.equipmentBases.eq_arm_chainmail
			local plate =
				Inventory.newEquipment(s, { baseId = "eq_arm_test_plate", rarity = 1, grade = 0, itemLevel = 1 })
			expect(Formulas.bulkSellValue(plate, m)).toBe(chain.pdef)
			expect(Formulas.bulkSellValue({ baseId = chain.id, rarity = 1, grade = 0, itemLevel = 1 }, m)).toBe(
				chain.pdef + chain.mdef
			)
			local r = Game.execute(
				s,
				{ type = "BulkSell", equipmentUids = { plate.uid } },
				{ now = T0, master = m, online = true }
			)
			expect(r.ok).toBeTruthy()
			expect(s.equipment[plate.uid]).toBe(nil)
		end)
		it("D-175 武器は攻撃力補正（性能値）で比べる", function()
			local item = { baseId = "eq_wpn_sword", rarity = 3, grade = 2, itemLevel = 4 }
			local base = master.equipmentBases.eq_wpn_sword
			expect(Formulas.bulkSellValue(item, master)).toBe(
				math.floor(base.atk * Formulas.equipMult(3, 2, 4, master.K))
			)
		end)
		it("D-175 補助（盾・アクセサリー）は対象外", function()
			local s = newState()
			local warrior = advOf(s, "job_warrior")
			s.equipment[warrior.equipment.sub].rarity = 5
			local weakShield = newItem(s, "eq_sub_buckler", 1)
			expect(Formulas.bulkSellValue(weakShield, master)).toBe(nil)
			expect(exec(s, { type = "BulkSell", equipmentUids = { weakShield.uid } }).error).toBe("NOTHING_TO_SELL")
		end)
		it("D-167 修飾語つき・保護中・装備中・商人で買ったものは売らない", function()
			local s, warrior = withStrongSword()
			local modified = newItem(s, "eq_wpn_sword", 1)
			modified.modifierId = master.raw.Modifiers[1].id
			modified.modifierValue = 1
			local locked = newItem(s, "eq_wpn_sword", 1)
			locked.locked = true
			local merchant = newItem(s, "eq_wpn_sword", 1)
			merchant.fromMerchant = true
			local equipped = s.equipment[warrior.equipment.weapon]
			local before = Game._deepClone(s)
			local r = exec(s, {
				type = "BulkSell",
				equipmentUids = { modified.uid, locked.uid, merchant.uid, equipped.uid },
			})
			expect(r.error).toBe("NOTHING_TO_SELL")
			expect(s).toEqual(before) -- 失敗したら状態は変わらない
		end)
		it("D-167 対象の中から弱いものだけを売り、もう無い品は飛ばす", function()
			local s = withStrongSword()
			local weak = newItem(s, "eq_wpn_sword", 1)
			local keep = newItem(s, "eq_wpn_sword", 4)
			local r = exec(s, { type = "BulkSell", equipmentUids = { "eq_gone", weak.uid, keep.uid, weak.uid } })
			expect(r.ok).toBeTruthy()
			expect(r.events[1].equipmentUids).toEqual({ weak.uid })
			expect(s.equipment[keep.uid] ~= nil).toBeTruthy()
		end)
		it("D-167 開封結果からそのまま一括売却できる", function()
			local s = withStrongSword()
			s.expansions.warehouseSize = 100000
			exec(s, { type = "SetAutoSell", enabled = false })
			Chest.add(s, "dng_graveyard", 1, 30)
			local r = exec(s, { type = "OpenChests", pileKey = "dng_graveyard", count = 30 })
			local uids = {}
			for _, list in { r.events[1].normal, r.events[1].special } do
				for _, res in list do
					for _, uid in res.equipmentUids do
						table.insert(uids, uid)
					end
				end
			end
			local expected = {}
			local want = 0
			for _, uid in uids do
				if Inventory.isWeakForBulkSell(s, s.equipment[uid], master) then
					expected[uid] = true
					want += 1
				end
			end
			expect(want > 0).toBeTruthy() -- 固定シードでコモンの剣が出る
			local r2 = exec(s, { type = "BulkSell", equipmentUids = uids })
			expect(r2.ok).toBeTruthy()
			for _, uid in r2.events[1].equipmentUids do
				expect(expected[uid]).toBe(true)
				expect(s.equipment[uid]).toBe(nil)
			end
			expect(#r2.events[1].equipmentUids).toBe(want)
		end)
	end)
end
