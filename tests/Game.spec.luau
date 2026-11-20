--!strict
local serde = require("@lune/serde")

local Chest = require("../src/core/Chest")
local Game = require("../src/core/Game")
local Growth = require("../src/core/Growth")
local Inventory = require("../src/core/Inventory")
local Rng = require("../src/core/Rng")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1767225600

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()

	local function ctx(now: number, online: boolean?)
		return { now = now, master = master, online = if online == nil then true else online }
	end

	local function newState(seed: number?)
		return Game.newState(master, seed or 1, T0)
	end

	local function firstExpedition(state: any)
		for _, e in state.expeditions do
			return e
		end
		return nil
	end

	local function advUids(state: any): { string }
		return table.clone(state.parties[1].slots)
	end

	describe("初期状態（Q-020）", function()
		it("Q-020 4人がパーティ1の隊列1〜4に入り、装備している", function()
			local s = newState()
			for slot = 1, 4 do
				local adv = s.adventurers[s.parties[1].slots[slot]]
				expect(adv ~= nil).toBeTruthy()
				expect(adv.equipment.weapon ~= nil).toBeTruthy()
			end
			expect(s.gold).toBe(master.raw.StarterSet.gold)
			expect(Inventory.warehouseUsage(s)).toBe(0)
		end)
		it("Q-017 最初は古い墓地だけ解放されている", function()
			local s = newState()
			expect(s.unlockedDungeons.dng_graveyard).toBe(true)
			expect(s.unlockedDungeons.dng_ruins).toBe(nil)
		end)
	end)

	describe("派遣と帰還（D-026）", function()
		it("01章 最初の宝箱を1分以内に持ち帰れる", function()
			for seed = 1, 30 do
				local s = newState(seed)
				local r = Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx(T0))
				expect(r.ok).toBeTruthy()
				local e = firstExpedition(s)
				expect(e.returnAt - T0 < 60).toBeTruthy()
				Game.advance(s, ctx(e.returnAt))
				expect(Chest.total(s) >= 1).toBeTruthy()
			end
		end)
		it("D-026 帰還時刻の前は何も起きず、過ぎたら報酬が反映される", function()
			local s = newState()
			Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx(T0))
			local e = firstExpedition(s)
			local gold0 = s.gold
			expect(#Game.advance(s, ctx(e.returnAt - 1))).toBe(0)
			expect(s.gold).toBe(gold0)
			local events = Game.advance(s, ctx(e.returnAt))
			expect(events[1].type).toBe("ExpeditionReturned")
			expect(s.gold).toBe(gold0 + e.log.rewards.gold)
			expect(firstExpedition(s)).toBe(nil)
		end)
		it("探索中のパーティは再派遣・編成変更できない", function()
			local s = newState()
			Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx(T0))
			local r = Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx(T0 + 1))
			expect(r.error).toBe("PARTY_BUSY")
			local r2 = Game.execute(s, { type = "SetPartySlot", partyIndex = 1, slot = 1 }, ctx(T0 + 1))
			expect(r2.error).toBe("PARTY_BUSY")
			local uid = s.parties[1].slots[1]
			local eq = Inventory.newEquipment(s, { baseId = "eq_wpn_sword", rarity = 1, grade = 0, itemLevel = 1 })
			local r3 = Game.execute(s, { type = "Equip", adventurerUid = uid, equipmentUid = eq.uid }, ctx(T0 + 1))
			expect(r3.error).toBe("ADVENTURER_ON_EXPEDITION")
		end)
		it("未解放のダンジョンには派遣できない", function()
			local s = newState()
			local r = Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_ruins" }, ctx(T0))
			expect(r.error).toBe("DUNGEON_LOCKED")
		end)
		it(
			"Q-017 初踏破で次のダンジョンが解放され、ギルド経験値に初回ボーナス",
			function()
				local s = newState()
				Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx(T0))
				local e = firstExpedition(s)
				expect(e.log.result).toBe("clear")
				Game.advance(s, ctx(e.returnAt))
				expect(s.unlockedDungeons.dng_ruins).toBe(true)
				expect(s.stats.guildExpTotal).toBe(e.log.rewards.guildExp + master.K.guildExpFirstClear)
			end
		)
	end)

	describe("失敗したコマンドは状態を変えない（01章 §3）", function()
		it("エラー時に state が完全に同じ", function()
			local s = newState()
			local before = Game._deepClone(s)
			for _, cmd in
				{
					{ type = "Dispatch", partyIndex = 1, dungeonId = "dng_castle" },
					{ type = "Dispatch", partyIndex = 9, dungeonId = "dng_graveyard" },
					{ type = "OpenChests" },
					{ type = "Sell", equipmentUids = { "eq_1" } },
					{ type = "Nope" },
				}
			do
				local r = Game.execute(s, cmd, ctx(T0))
				expect(r.ok).toBeFalsy()
			end
			expect(s).toEqual(before)
		end)
	end)

	describe("パーティ編成（D-035）", function()
		it("同じパーティ内で配置すると入れ替わる", function()
			local s = newState()
			local u = advUids(s)
			Game.execute(s, { type = "SetPartySlot", partyIndex = 1, slot = 1, adventurerUid = u[4] }, ctx(T0))
			expect(s.parties[1].slots[1]).toBe(u[4])
			expect(s.parties[1].slots[4]).toBe(u[1])
		end)
		it("外すと空き枠になり、全員外すと派遣できない", function()
			local s = newState()
			for slot = 1, 4 do
				Game.execute(s, { type = "SetPartySlot", partyIndex = 1, slot = slot }, ctx(T0))
			end
			local r = Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx(T0))
			expect(r.error).toBe("PARTY_EMPTY")
		end)
	end)

	describe("装備・倉庫・売却（06章）", function()
		it("職業が装備できない種類は装備できない", function()
			local s = newState()
			local mage = s.parties[1].slots[3]
			local sword = Inventory.newEquipment(s, { baseId = "eq_wpn_sword", rarity = 1, grade = 0, itemLevel = 1 })
			local r = Game.execute(s, { type = "Equip", adventurerUid = mage, equipmentUid = sword.uid }, ctx(T0))
			expect(r.error).toBe("JOB_CANNOT_EQUIP")
		end)
		it("装備を替えると前の装備は倉庫へ戻る", function()
			local s = newState()
			local warrior = s.parties[1].slots[1]
			local old = s.adventurers[warrior].equipment.weapon
			local sword = Inventory.newEquipment(s, { baseId = "eq_wpn_sword", rarity = 2, grade = 1, itemLevel = 2 })
			local r = Game.execute(s, { type = "Equip", adventurerUid = warrior, equipmentUid = sword.uid }, ctx(T0))
			expect(r.ok).toBeTruthy()
			expect(s.adventurers[warrior].equipment.weapon).toBe(sword.uid)
			expect(s.equipment[old].equippedBy).toBe(nil)
		end)
		it("Q-020 倉庫が満杯なら外せない", function()
			local s = newState()
			s.expansions.warehouseSize = 0
			local r =
				Game.execute(s, { type = "Unequip", adventurerUid = s.parties[1].slots[1], slot = "weapon" }, ctx(T0))
			expect(r.error).toBe("WAREHOUSE_FULL")
		end)
		it(
			"売却価格＝基本価格×レアリティ倍率×(1+0.5×グレード)×1.3^(IL−1)、装備中・保護中は売れない",
			function()
				local s = newState()
				local e = Inventory.newEquipment(s, { baseId = "eq_wpn_sword", rarity = 3, grade = 2, itemLevel = 2 })
				local expected = math.floor(20 * 2.5 * 2 * 1.3)
				Game.execute(s, { type = "SetLock", uid = e.uid, locked = true }, ctx(T0))
				expect(Game.execute(s, { type = "Sell", equipmentUids = { e.uid } }, ctx(T0)).error).toBe("ITEM_LOCKED")
				Game.execute(s, { type = "SetLock", uid = e.uid, locked = false }, ctx(T0))
				local gold0 = s.gold
				expect(Game.execute(s, { type = "Sell", equipmentUids = { e.uid } }, ctx(T0)).ok).toBeTruthy()
				expect(s.gold).toBe(gold0 + expected)
				local equipped = s.adventurers[s.parties[1].slots[1]].equipment.weapon
				expect(Game.execute(s, { type = "Sell", equipmentUids = { equipped } }, ctx(T0)).error).toBe(
					"ITEM_EQUIPPED"
				)
			end
		)
	end)

	describe("宝箱（D-015）", function()
		local function withChests(rank: number, n: number)
			local s = newState()
			s.expansions.unlockRank = 5 -- 解錠技術は別のテスト（D-078）
			for _ = 1, n do
				Chest.add(s, "dng_castle", rank, 1)
			end
			return s
		end
		it(
			"D-015 開封で中身を抽選。装備のレアリティ＝ランク、アイテムレベル＝ダンジョンの tier",
			function()
				local s = withChests(3, 5)
				local r = Game.execute(s, { type = "OpenChests" }, ctx(T0))
				expect(r.ok).toBeTruthy()
				expect(Chest.total(s)).toBe(0)
				for _, ev in r.events :: any do
					for _, uid in ev.result.equipmentUids do
						expect(s.equipment[uid].rarity).toBe(3)
						expect(s.equipment[uid].itemLevel).toBe(master.dungeons.dng_castle.tier)
					end
				end
			end
		)
		it("Q-020 倉庫の空きが足りなければ開けられない", function()
			local s = withChests(1, 1)
			s.expansions.warehouseSize = 1
			expect(Game.execute(s, { type = "OpenChests" }, ctx(T0)).error).toBe("WAREHOUSE_FULL")
		end)
		it("D-058 統計: レア以上の箱からポーションがおよそ5%で出る", function()
			local s = withChests(3, 2000)
			s.expansions.warehouseSize = 100000
			Game.execute(s, { type = "OpenChests" }, ctx(T0))
			local potions = 0
			for id, n in s.items do
				if string.find(id, "potion") then
					potions += n
				end
			end
			expect(potions / 2000).toBeCloseTo(master.K.potionChanceRarePlus, 0.015)
		end)
	end)

	describe("自動再派遣（01章）", function()
		it("帰還時刻から次の探索が連続して確定する", function()
			local s = newState()
			Game.execute(s, { type = "SetAutoRepeat", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx(T0))
			Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx(T0))
			local first = firstExpedition(s)
			local events = Game.advance(s, ctx(T0 + 600))
			local returns = 0
			for _, e in events do
				if e.type == "ExpeditionReturned" then
					returns += 1
				end
			end
			expect(returns >= 10).toBeTruthy()
			local cur = firstExpedition(s)
			expect(cur ~= nil and cur.departAt <= T0 + 600 and cur.returnAt > T0 + 600).toBeTruthy()
			expect(cur.uid ~= first.uid).toBeTruthy()
		end)
		it("企画書§16.8 案A オフライン中は帰還まで進めるが再派遣しない", function()
			local s = newState()
			Game.execute(s, { type = "SetAutoRepeat", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx(T0))
			Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx(T0))
			Game.advance(s, ctx(T0 + 3600, false))
			expect(firstExpedition(s)).toBe(nil)
			expect(s.parties[1].autoRepeat ~= nil).toBeTruthy()
		end)
		it("Q-020 倉庫が満杯なら自動再派遣を止める（報酬は消さない）", function()
			local s = newState()
			Game.execute(s, { type = "SetAutoRepeat", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx(T0))
			Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx(T0))
			s.expansions.warehouseSize = 0
			local events = Game.advance(s, ctx(T0 + 600))
			local stopped = false
			for _, e in events do
				stopped = stopped or e.type == "AutoRepeatStopped"
			end
			expect(stopped).toBeTruthy()
			expect(s.parties[1].autoRepeat).toBe(nil)
			expect(Chest.total(s) >= 1).toBeTruthy()
		end)
	end)

	describe("成長（D-039, D-043, D-041）", function()
		it("D-043 レベルアップ時の成長は職業の基準値±1（最低0）", function()
			local rng = Rng.new(5)
			for _ = 1, 500 do
				local g = Growth.rollGrowth("job_warrior", rng, master)
				expect(g.str).toBeBetween(3, 5)
				expect(g.mag).toBeBetween(0, 1)
				expect(g.hp).toBeBetween(4, 6)
			end
		end)
		it("07章 レベル上限では経験値を貯めない", function()
			local s = newState()
			local adv = s.adventurers[s.parties[1].slots[1]]
			adv.level = adv.levelCap
			Growth.addExp(adv, 999999, Rng.new(1), master)
			expect(adv.level).toBe(adv.levelCap)
			expect(adv.exp).toBe(0)
		end)
		it("D-070 大食らいは経験値+25%、転生1回ごとに+50%", function()
			local adv = { giftIds = { "gift_glutton" }, rebirthCount = 2 }
			expect(Growth.expMultiplier(adv, master)).toBeCloseTo(2 * 1.25)
		end)
	end)

	describe("セーブデータ", function()
		it("JSON に変換して戻しても同じ（DataStore に保存できる形）", function()
			local s = newState()
			expect(Game.execute(s, { type = "SetPartySlot", partyIndex = 1, slot = 2 }, ctx(T0)).ok).toBeTruthy()
			Game.execute(s, { type = "SetAutoRepeat", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx(T0))
			Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx(T0))
			Game.advance(s, ctx(T0 + 300))
			local decoded = serde.decode("json", serde.encode("json", s))
			expect(decoded.parties[1].slots[2]).toBe("")
			expect(#decoded.parties[1].slots).toBe(4)
			expect(decoded.gold).toBe(s.gold)
		end)
		it("D-026 同じシード・同じ操作なら同じ結果（決定論）", function()
			local function play()
				local s = newState(42)
				Game.execute(s, { type = "SetAutoRepeat", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx(T0))
				Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx(T0))
				Game.advance(s, ctx(T0 + 1200))
				Game.execute(s, { type = "OpenChests" }, ctx(T0 + 1200))
				return s
			end
			expect(play()).toEqual(play())
		end)
	end)
end
