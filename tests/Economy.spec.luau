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

	describe("宝箱の保管・まとめ開き（D-084, D-087, D-089〜D-091）", function()
		local function pile(dungeonId: string, counts: { number })
			local s = newState()
			s.expansions.warehouseSize = 100000
			for r, n in counts do
				if n > 0 then
					Chest.add(s, dungeonId, r, n)
				end
			end
			return s
		end
		local function ev(r: any)
			return r.events[1]
		end
		it(
			"D-084 宝箱は倉庫とは別に、ダンジョン×ランクの数だけを保存する（上限なし）",
			function()
				local s = newState()
				Chest.add(s, "dng_ruins", 2, 3000)
				Chest.add(s, "dng_castle", 2, 5)
				expect(s.chests.dng_ruins).toEqual({ 0, 3000 })
				expect(Chest.countByRank(s, master)).toEqual({ 0, 3005, 0, 0, 0, 0 })
				expect(Game.query.warehouse(s).used).toBe(Game.query.warehouse(newState()).used)
				expect(exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }).ok).toBeTruthy()
				local e = Game.query.expeditionOf(s, 1)
				local brought = #e.log.rewards.chests
				Game.advance(s, ctx(e.returnAt))
				expect(Chest.total(s)).toBe(3005 + brought)
			end
		)
		it(
			"D-087 プレイヤーに見せる一覧はダンジョンごとの数だけ（レアリティを含まない）",
			function()
				local s = newState()
				Chest.add(s, "dng_ruins", 1, 2)
				Chest.add(s, "dng_ruins", 3, 1)
				Chest.add(s, "dng_castle", 2, 4)
				local list = Game.query.chestsByDungeon(s, master)
				expect(list).toEqual({
					{ dungeonId = "dng_ruins", count = 3 },
					{ dungeonId = "dng_castle", count = 4 },
				})
			end
		)
		it("D-091 解錠技術は廃止。どのダンジョンの宝箱もすぐ開けられる", function()
			local s = newState()
			s.expansions.warehouseSize = 100000
			Chest.add(s, "dng_sky_throne", 6, 3)
			expect(exec(s, { type = "OpenChests", dungeonId = "dng_sky_throne" }).ok).toBeTruthy()
			expect(master.expansions.exp_unlock).toBe(nil)
		end)
		it("D-089 まとめ開きは既定で chestBatchOpen 個。残りが少なければその数", function()
			local s = pile("dng_ruins", { 150, 50 })
			local r = ev(exec(s, { type = "OpenChests", dungeonId = "dng_ruins" }))
			expect(r.opened).toBe(K.chestBatchOpen)
			expect(r.remaining).toBe(200 - K.chestBatchOpen)
			local r2 = ev(exec(s, { type = "OpenChests", dungeonId = "dng_ruins" }))
			expect(r2.opened).toBe(200 - K.chestBatchOpen)
			expect(Chest.total(s)).toBe(0)
		end)
		it(
			"D-089 山からはランクの残り数で重み付けして引く（数の比率どおりに出る）",
			function()
				local s = pile("dng_ruins", { 3000, 1000 })
				local r = ev(exec(s, { type = "OpenChests", dungeonId = "dng_ruins", count = 2000 }))
				local high = 0
				for _, x in r.normal do
					high += if x.rank == 2 then 1 else 0
				end
				for _, x in r.special do
					high += if x.rank == 2 then 1 else 0
				end
				expect(high / 2000).toBeCloseTo(0.25, 0.03)
			end
		)
		it(
			"D-089 発生ライン以上は演出あり。演出なしの一覧 → 演出ありはレアリティの低い順",
			function()
				local d = master.dungeons.dng_castle
				local s = pile(d.id, { 20, 20, 20, 20, 20, 20 })
				local r = ev(exec(s, { type = "OpenChests", dungeonId = d.id }))
				expect(#r.normal + #r.special).toBe(100)
				for _, x in r.normal do
					expect(x.rank < d.chestEffectMinRarity).toBeTruthy()
					expect(x.effect).toBe(false)
				end
				local prev = 0
				for _, x in r.special do
					expect(x.rank >= d.chestEffectMinRarity).toBeTruthy()
					expect(x.rank >= prev).toBeTruthy()
					prev = x.rank
				end
			end
		)
		it("D-090 どのダンジョンも演出が入る割合は基準（10〜15%）に収まる", function()
			for _, d in master.dungeonList do
				local total, tail = 0, 0
				for r, w in d.chestRarityWeights do
					total += w
					if r >= d.chestEffectMinRarity then
						tail += w
					end
				end
				expect(tail / total >= K.chestEffectRate.min - 1e-9).toBeTruthy()
				expect(tail / total <= K.chestEffectRate.max + 1e-9).toBeTruthy()
			end
		end)
		it("D-089 演出の発生ラインはダンジョンごとに決まっている", function()
			for _, d in master.dungeonList do
				expect(d.chestEffectMinRarity >= 1 and d.chestEffectMinRarity <= master.rarityCount).toBeTruthy()
			end
			expect(
				master.dungeons.dng_sky_throne.chestEffectMinRarity > master.dungeons.dng_graveyard.chestEffectMinRarity
			).toBeTruthy()
		end)
		it(
			"D-084 / D-091 古いセーブは移行される（宝箱の一覧→数、解錠技術は削除）",
			function()
				local Migration = require("../src/core/Migration")
				local old = {
					version = 2,
					expansions = { unlockRank = 4 },
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
				expect(old.expansions.unlockTier).toBe(nil) -- D-091 で廃止
				expect(old.expansions.unlockRank).toBe(nil)
			end
		)
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
