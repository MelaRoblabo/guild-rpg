--!strict
-- ゴールドの使い道（D-076〜D-080）と経験値補正の装備（D-082）
local Formulas = require("../src/core/Formulas")
local Chest = require("../src/core/Chest")
local Game = require("../src/core/Game")
local Growth = require("../src/core/Growth")
local Inventory = require("../src/core/Inventory")
local Training = require("../src/core/Training")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1767225600

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local K = master.K

	local function ctx(now: number?)
		return { now = now or T0, master = master, online = true }
	end
	local function exec(s: any, cmd: any, now: number?)
		return Game.execute(s, cmd, ctx(now))
	end
	local function newState()
		local s = Game.newState(master, 1, T0)
		return s, s.parties[1].slots[1]
	end

	describe("トレーニング（D-076, D-077）", function()
		it("D-076 ゴールドを払って経験値を得る。費用＝係数×Lv^指数", function()
			local s, uid = newState()
			s.gold = 10 ^ 9
			local r = exec(s, { type = "Train", adventurerUid = uid, sessions = 1 })
			expect(r.ok).toBeTruthy()
			expect(s.gold).toBe(10 ^ 9 - Training.sessionCost(1, K))
			expect(Training.sessionCost(10, K)).toBe(math.floor(K.trainGoldCoef * 10 ^ K.trainGoldExponent))
			expect(s.adventurers[uid].level > 1 or s.adventurers[uid].exp == K.trainingFacility[1].expPerSession).toBeTruthy()
		end)
		it("D-076 経験値に転生・ギフト・装備の倍率は掛からない", function()
			local s, uid = newState()
			s.gold = 10 ^ 9
			local adv = s.adventurers[uid]
			adv.rebirthCount = 3
			adv.levelCap = 50
			adv.giftIds = { "gift_glutton" }
			exec(s, { type = "Train", adventurerUid = uid, sessions = 1 })
			adv = s.adventurers[uid]
			local need = Formulas.expToNext(1, K, 3)
			expect(adv.level).toBe(2)
			expect(adv.exp).toBe(K.trainingFacility[1].expPerSession - need)
		end)
		it("D-077 トレーニング場のレベルで決まる上限までしか上がらない", function()
			local s, uid = newState()
			s.gold = 10 ^ 12
			expect(exec(s, { type = "Train", adventurerUid = uid, sessions = 100000 }).ok).toBeTruthy()
			expect(s.adventurers[uid].level).toBe(K.trainingFacility[1].levelCap)
			expect(exec(s, { type = "Train", adventurerUid = uid, sessions = 1 }).error).toBe("TRAINING_CAP")
		end)
		it("D-077 本人の上限レベルも超えない", function()
			local s, uid = newState()
			s.gold = 10 ^ 12
			s.expansions.trainingLevel = #K.trainingFacility
			exec(s, { type = "Train", adventurerUid = uid, sessions = 100000 })
			expect(s.adventurers[uid].level).toBe(K.levelCapInitial)
		end)
		it("D-077 トレーニング場を改修すると1回の経験値が増える", function()
			expect(K.trainingFacility[2].expPerSession > K.trainingFacility[1].expPerSession).toBeTruthy()
			local s = newState()
			s.gold = 10 ^ 9
			s.guild.level = 100
			expect(exec(s, { type = "BuyExpansion", expansionId = "exp_training" }).ok).toBeTruthy()
			expect(Training.facility(s, master).expPerSession).toBe(K.trainingFacility[2].expPerSession)
		end)
		it("D-076 ゴールドが尽きたら途中で止まり、払った分だけ行う", function()
			local s, uid = newState()
			s.gold = Training.sessionCost(1, K) * 2 + 1
			local r = exec(s, { type = "Train", adventurerUid = uid, sessions = 50 })
			expect(r.ok).toBeTruthy()
			expect(r.events[1].gold <= Training.sessionCost(1, K) * 2 + 1).toBeTruthy()
			expect(s.gold < Training.sessionCost(s.adventurers[uid].level, K)).toBeTruthy()
		end)
		it("D-076 探索中はトレーニングできない", function()
			local s, uid = newState()
			s.gold = 10 ^ 9
			exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" })
			expect(exec(s, { type = "Train", adventurerUid = uid, sessions = 1 }).error).toBe(
				"ADVENTURER_ON_EXPEDITION"
			)
		end)
		it("D-076 見積もりは実際の費用と一致する", function()
			local s, uid = newState()
			s.gold = 10 ^ 12
			local q = Training.quote(s, s.adventurers[uid], 10, master)
			local r = exec(s, { type = "Train", adventurerUid = uid, sessions = q.sessions })
			expect(s.adventurers[uid].level).toBe(10)
			expect(r.events[1].gold).toBe(q.gold)
		end)
	end)

	describe("解錠技術（D-078）", function()
		local function withChests(ranks: { number })
			local s = newState()
			s.expansions.warehouseSize = 100000
			for _, rank in ranks do
				Chest.add(s, "dng_ruins", rank, 1)
			end
			return s
		end
		it("D-078 上限より高いランクの宝箱は開けられず、ギルドに残る", function()
			local s = withChests({ 1, 2, 3, 5 })
			expect(exec(s, { type = "OpenChests" }).ok).toBeTruthy()
			expect(Chest.total(s)).toBe(2)
			expect(Chest.count(s, "dng_ruins", 3)).toBe(1)
			expect(Chest.count(s, "dng_ruins", 5)).toBe(1)
		end)
		it("D-078 開けられる宝箱がなければ CHEST_RANK_TOO_HIGH", function()
			local s = withChests({ 4 })
			expect(exec(s, { type = "OpenChests" }).error).toBe("CHEST_RANK_TOO_HIGH")
			expect(exec(s, { type = "OpenChests", rank = 4 }).error).toBe("CHEST_RANK_TOO_HIGH")
		end)
		it(
			"D-084 宝箱は倉庫とは別に、ダンジョン×ランクの数だけを保存する（上限なし）",
			function()
				local s = newState()
				Chest.add(s, "dng_ruins", 2, 3000)
				Chest.add(s, "dng_castle", 2, 5)
				expect(s.chests.dng_ruins).toEqual({ 0, 3000, 0, 0, 0 })
				expect(Chest.countByRank(s)).toEqual({ 0, 3005, 0, 0, 0 })
				expect(Game.query.warehouse(s).used).toBe(Game.query.warehouse(newState()).used)
				expect(exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }).ok).toBeTruthy()
				local e = Game.query.expeditionOf(s, 1)
				local brought = #e.log.rewards.chests
				Game.advance(s, ctx(e.returnAt))
				expect(Chest.total(s)).toBe(3005 + brought)
			end
		)
		it(
			"D-084 ランク・個数を指定して開けられる。ダンジョンの並び順→ランクの低い順に開ける",
			function()
				local s = newState()
				s.expansions.warehouseSize = 100000
				Chest.add(s, "dng_castle", 2, 2)
				Chest.add(s, "dng_graveyard", 2, 2)
				Chest.add(s, "dng_graveyard", 1, 2)
				local r = exec(s, { type = "OpenChests", rank = 2, count = 3 })
				expect(#r.events).toBe(3)
				expect(r.events[1].result.dungeonId).toBe("dng_graveyard")
				expect(r.events[3].result.dungeonId).toBe("dng_castle")
				expect(Chest.count(s, "dng_graveyard", 1)).toBe(2)
				expect(Chest.count(s, "dng_castle", 2)).toBe(1)
			end
		)
		it("D-084 セーブ v2 の宝箱一覧は数に変換される", function()
			local Migration = require("../src/core/Migration")
			local old = {
				version = 2,
				chests = {
					{ uid = "ch_1", rank = 3, dungeonId = "dng_ruins", obtainedAt = T0 },
					{ uid = "ch_2", rank = 3, dungeonId = "dng_ruins", obtainedAt = T0 },
					{ uid = "ch_3", rank = 1, dungeonId = "dng_tower", obtainedAt = T0 },
				},
			}
			Migration.migrate(old)
			expect(old.version).toBe(Migration.CURRENT)
			expect(old.chests.dng_ruins).toEqual({ 0, 0, 2, 0, 0 })
			expect(old.chests.dng_tower).toEqual({ 1, 0, 0, 0, 0 })
		end)
		it("D-078 解錠技術を上げると開けられる", function()
			local s = withChests({ 3 })
			s.gold = 10 ^ 9
			expect(exec(s, { type = "BuyExpansion", expansionId = "exp_unlock" }).ok).toBeTruthy()
			expect(exec(s, { type = "OpenChests" }).ok).toBeTruthy()
			expect(Chest.total(s)).toBe(0)
		end)
	end)

	describe("派遣費（D-079）", function()
		local feeDungeon = nil
		for _, d in master.dungeonList do
			if d.dispatchFee and feeDungeon == nil then
				feeDungeon = d
			end
		end
		it("D-079 派遣費のあるダンジョンは出発時にゴールドが減る", function()
			local s = newState()
			s.unlockedDungeons[feeDungeon.id] = true
			s.gold = feeDungeon.dispatchFee - 1
			expect(exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = feeDungeon.id }).error).toBe(
				"NOT_ENOUGH_GOLD"
			)
			s.gold = feeDungeon.dispatchFee
			expect(exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = feeDungeon.id }).ok).toBeTruthy()
			expect(s.gold).toBe(0)
		end)
		it("D-079 自動周回はゴールドが足りなければ止まる", function()
			local s = newState()
			s.unlockedDungeons[feeDungeon.id] = true
			s.gold = feeDungeon.dispatchFee
			exec(s, { type = "SetAutoRepeat", partyIndex = 1, dungeonId = feeDungeon.id })
			exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = feeDungeon.id })
			local e = Game.query.expeditionOf(s, 1)
			e.log.rewards.gold = 0
			e.log.rewards.chests = {}
			local events = Game.advance(s, ctx(e.returnAt))
			local stopped = nil
			for _, ev in events do
				if ev.type == "AutoRepeatStopped" then
					stopped = ev.reason
				end
			end
			expect(stopped).toBe("NOT_ENOUGH_GOLD")
		end)
		it("D-079 初級ダンジョンには派遣費がない", function()
			expect(master.dungeons.dng_graveyard.dispatchFee).toBe(nil)
		end)
	end)

	describe("経験値補正の装備（D-082）", function()
		it(
			"D-082 修練の護符で獲得経験値が増える（レアリティ・グレードで伸び、アイテムレベルでは伸びない）",
			function()
				local base = master.equipmentBases.eq_sub_amulet_learning
				local a = Formulas.equipExpPct({ baseId = base.id, rarity = 1, grade = 0, itemLevel = 1 }, master)
				local b = Formulas.equipExpPct({ baseId = base.id, rarity = 1, grade = 0, itemLevel = 9 }, master)
				local c = Formulas.equipExpPct({ baseId = base.id, rarity = 3, grade = 2, itemLevel = 1 }, master)
				expect(a).toBeCloseTo(base.expPct)
				expect(b).toBeCloseTo(a)
				expect(c).toBeCloseTo(base.expPct * K.equipRarityMult[3] * (1 + 2 * K.equipGradeCoef))
			end
		)
		it("D-082 装備すると帰還時の経験値に掛かる", function()
			local s, uid = newState()
			local adv = s.adventurers[uid]
			local before = Growth.expMultiplier(adv, master, s.equipment)
			local e =
				Inventory.newEquipment(s, { baseId = "eq_sub_amulet_learning", rarity = 5, grade = 0, itemLevel = 1 })
			exec(s, { type = "Unequip", adventurerUid = uid, slot = "sub" })
			exec(s, { type = "Equip", adventurerUid = uid, equipmentUid = e.uid })
			adv = s.adventurers[uid]
			local after = Growth.expMultiplier(adv, master, s.equipment)
			expect(after / before).toBeCloseTo(1 + math.min(0.20 * K.equipRarityMult[5], K.expBonusCap))
		end)
		it("D-082 経験値補正の合計は expBonusCap まで", function()
			local adv = { giftIds = { "gift_glutton" }, rebirthCount = 0, equipment = { sub = "x" } }
			local eq = { x = { baseId = "eq_sub_amulet_learning", rarity = 5, grade = 3 } }
			expect(Growth.expMultiplier(adv, master, eq)).toBeCloseTo(1 + K.expBonusCap)
		end)
	end)
end
