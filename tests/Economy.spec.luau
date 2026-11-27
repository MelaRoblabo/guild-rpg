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
			-- 倍率を掛けない経験値（1回分そのまま）で上がった結果と一致する
			local level, exp = 1, K.trainingFacility[1].expPerSession
			while exp >= Formulas.expToNext(level, K, 3) do
				exp -= Formulas.expToNext(level, K, 3)
				level += 1
			end
			expect(adv.level).toBe(level)
			expect(adv.exp).toBe(exp)
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
			expect(exec(s, { type = "OpenChests", pileKey = "dng_sky_throne" }).ok).toBeTruthy()
			expect(master.expansions.exp_unlock).toBe(nil)
		end)
		it("D-089 まとめ開きは既定で chestBatchOpen 個。残りが少なければその数", function()
			local s = pile("dng_ruins", { 150, 50 })
			local r = ev(exec(s, { type = "OpenChests", pileKey = "dng_ruins" }))
			expect(r.opened).toBe(K.chestBatchOpen)
			expect(r.remaining).toBe(200 - K.chestBatchOpen)
			local r2 = ev(exec(s, { type = "OpenChests", pileKey = "dng_ruins" }))
			expect(r2.opened).toBe(200 - K.chestBatchOpen)
			expect(Chest.total(s)).toBe(0)
		end)
		it(
			"D-089 山からはランクの残り数で重み付けして引く（数の比率どおりに出る）",
			function()
				local s = pile("dng_ruins", { 3000, 1000 })
				local r = ev(exec(s, { type = "OpenChests", pileKey = "dng_ruins", count = 2000 }))
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
				local r = ev(exec(s, { type = "OpenChests", pileKey = d.id }))
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
		it(
			"D-188 D-171 D-185 どのダンジョンも普通の演出率（10〜15%）とレアダンジョンの演出率（20〜30%）の両方に収まる",
			function()
				expect(#master.dungeonList).toBe(12)
				for _, d in master.dungeonList do
					local total, tail, rareTail = 0, 0, 0
					expect(type(d.rareChestEffectMinRarity)).toBe("number")
					for r, w in d.chestRarityWeights do
						total += w
						if r >= d.chestEffectMinRarity then
							tail += w
						end
						if r >= d.rareChestEffectMinRarity then
							rareTail += w
						end
					end
					expect(tail / total >= K.chestEffectRate.min - 1e-9).toBeTruthy()
					expect(tail / total <= K.chestEffectRate.max + 1e-9).toBeTruthy()
					expect(rareTail / total >= K.rareDungeonEffectRate.min - 1e-9).toBeTruthy()
					expect(rareTail / total <= K.rareDungeonEffectRate.max + 1e-9).toBeTruthy()
				end
			end
		)
		it(
			"D-188 D-085 表の性格：深いほどコモンが減り、各レアリティ以上が出る割合は深いほど増える（または同じ）",
			function()
				local prev: { number }? = nil
				for _, d in master.dungeonList do
					local total = 0
					for _, w in d.chestRarityWeights do
						total += w
					end
					local atLeast = table.create(master.rarityCount, 0)
					for k = 1, master.rarityCount do
						for r, w in d.chestRarityWeights do
							if r >= k then
								atLeast[k] += w / total
							end
						end
					end
					if prev then
						-- コモンの割合 = 1 − アンコモン以上の割合
						expect(atLeast[2] > prev[2]).toBeTruthy()
						for k = 2, master.rarityCount do
							expect(atLeast[k] >= prev[k] - 1e-9).toBeTruthy()
						end
					end
					prev = atLeast
				end
			end
		)
		it("D-188 rareChestEffectMinRarity はすべてのダンジョンに必須（検証で止める）", function()
			local e = {}
			local d = Fixtures.clone(require("../src/data"))
			d.Dungeons[5].rareChestEffectMinRarity = nil
			for _, i in require("../src/core/MasterData").validate(d) do
				if i.level == "error" then
					table.insert(e, i.path)
				end
			end
			expect(table.find(e, "Dungeons[5].rareChestEffectMinRarity") ~= nil).toBeTruthy()
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
				Migration.migrate(old, master)
				expect(old.version).toBe(Migration.CURRENT)
				expect(old.chests.dng_ruins).toEqual({ 0, 0, 2, 0, 0 })
				expect(old.chests.dng_tower).toEqual({ 1, 0, 0, 0, 0 })
				expect(old.expansions.unlockTier).toBe(nil) -- D-091 で廃止
				expect(old.expansions.unlockRank).toBe(nil)
			end
		)
	end)

	describe("宝箱の山（D-166, D-171）", function()
		it(
			"D-166 宝箱は宝箱の山の鍵で保存する。普通の山は dungeonId、特別な山は special:...",
			function()
				local s = newState()
				Chest.add(s, "dng_ruins", 2, 3)
				Chest.add(s, "special:raid", 3, 2)
				Chest.add(s, "special:rare:dng_castle", 1, 1)
				expect(s.chests.dng_ruins).toEqual({ 0, 3 })
				expect(s.chests["special:raid"]).toEqual({ 0, 0, 2 })
				expect(Chest.total(s)).toBe(6)
				expect(Chest.countByRank(s, master)).toEqual({ 1, 3, 2, 0, 0, 0 })
				expect(Chest.isSpecialPile("special:raid")).toBe(true)
				expect(Chest.isSpecialPile("dng_ruins")).toBe(false)
			end
		)
		it(
			"D-166 見せる一覧は宝箱の山ごとの数（普通の山の後に特別な山。レアリティは含まない）",
			function()
				local s = newState()
				Chest.add(s, "special:raid", 3, 2)
				Chest.add(s, "dng_castle", 2, 4)
				Chest.add(s, "dng_ruins", 1, 1)
				Chest.add(s, "special:rare:dng_castle", 1, 5)
				expect(Game.query.chestsByPile(s, master)).toEqual({
					{ pileKey = "dng_ruins", count = 1 },
					{ pileKey = "dng_castle", count = 4 },
					{ pileKey = "special:raid", count = 2 },
					{ pileKey = "special:rare:dng_castle", count = 5 },
				})
			end
		)
		it("D-166 ない山は PILE_NOT_FOUND、宝箱がない山は NO_CHEST", function()
			local s = newState()
			expect(exec(s, { type = "OpenChests", pileKey = "dng_nope" }).error).toBe("PILE_NOT_FOUND")
			expect(exec(s, { type = "OpenChests" }).error).toBe("PILE_NOT_FOUND")
			expect(exec(s, { type = "OpenChests", pileKey = "dng_ruins" }).error).toBe("NO_CHEST")
		end)
		it(
			"D-166 表のない特別な山（special:...）があっても壊れない（開けずに残す）",
			function()
				-- M7b-4 で SpecialChests の表を持つ山（special:raid など）は開けられるようになった（Rewards.spec）。
				-- 表のない種類と、演出ライン（rareChestEffectMinRarity）のないダンジョンのレアダンジョンの山は開けられない
				-- （D-188 で本番データは全ダンジョンが演出ラインを持つので、読み込んだ後に古城の演出ラインを外して確かめる）
				local m = Fixtures.master()
				m.dungeons.dng_castle.rareChestEffectMinRarity = nil
				local function execM(s: any, cmd: any, now: number?)
					return Game.execute(s, cmd, { now = now or T0, master = m, online = true })
				end
				local s = newState()
				Chest.add(s, "special:unknown", 3, 2)
				Chest.add(s, "special:raid", 3, 2)
				Chest.add(s, "special:rare:dng_castle", 1, 1)
				Chest.add(s, "dng_graveyard", 1, 1)
				local before = Game._deepClone(s)
				expect(execM(s, { type = "OpenChests", pileKey = "special:unknown" }).error).toBe("PILE_NOT_FOUND")
				expect(execM(s, { type = "OpenChests", pileKey = "special:rare:dng_castle" }).error).toBe(
					"PILE_NOT_FOUND"
				)
				expect(s).toEqual(before)
				-- 普通の山は開けられ、特別な山の数はそのまま
				local r = execM(s, { type = "OpenChests", pileKey = "dng_graveyard" })
				expect(r.ok).toBeTruthy()
				expect(r.events[1].pileKey).toBe("dng_graveyard")
				expect(s.chests["special:raid"]).toEqual({ 0, 0, 2 })
				-- 時間経過・保存の形も壊れない
				execM(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" })
				local e = Game.query.expeditionOf(s, 1)
				Game.advance(s, { now = e.returnAt, master = m, online = true })
				local serde = require("@lune/serde")
				local decoded = serde.decode("json", serde.encode("json", s))
				expect(decoded.chests["special:rare:dng_castle"]).toEqual({ 1 })
			end
		)
	end)

	describe("セーブの移行 version 5 → 6（D-177 の M7b-2 分）", function()
		local Migration = require("../src/core/Migration")
		local function v5State()
			local s = newState()
			s.version = 5
			s.settings.autoSell = { enabled = false, maxRarity = 1, keepModified = true }
			s.items = { itm_bone_fragment = 3, itm_sky_feather = 2, itm_slot_ticket = 4 }
			s.chests = { dng_ruins = { 2, 1 }, dng_castle = { 0, 0, 5 } }
			s.gold = 1000
			return s
		end
		it("D-177 version 5 から今の版まで移行する（v5→v6 の手順を通る）", function()
			expect(Migration.CURRENT >= 6).toBeTruthy() -- M7b は段階ごとに version を上げる（03章）
			expect(newState().version).toBe(Migration.CURRENT)
			local s = Migration.migrate(v5State(), master)
			expect(s.version).toBe(Migration.CURRENT)
		end)
		it("D-177 自動売却の設定は初期値（オン）にする", function()
			local s = Migration.migrate(v5State(), master)
			expect(s.settings.autoSell).toEqual(master.raw.StarterSet.autoSell)
			expect(s.settings.autoSell.enabled).toBe(true)
		end)
		it(
			"D-177 持っている売却用アイテムは今までと同じ売却価格で売ってゴールドにする",
			function()
				local s = Migration.migrate(v5State(), master)
				local expected = 1000
					+ master.items.itm_bone_fragment.sellPrice * 3
					+ master.items.itm_sky_feather.sellPrice * 2
				expect(s.gold).toBe(expected)
				expect(s.items).toEqual({ itm_slot_ticket = 4 }) -- 売却用でないものは残す
			end
		)
		it("D-177 宝箱の鍵は dungeonId のまま宝箱の山の鍵として使う", function()
			local s = Migration.migrate(v5State(), master)
			expect(s.chests).toEqual({ dng_ruins = { 2, 1 }, dng_castle = { 0, 0, 5 } })
			expect(exec(s, { type = "OpenChests", pileKey = "dng_castle" }).ok).toBeTruthy()
		end)
		it("D-177 移行には master が要る（無ければ何も変えずに失敗する）", function()
			local s = v5State()
			local before = Game._deepClone(s)
			expect(function()
				Migration.migrate(s)
			end).toThrow("master")
			expect(s).toEqual(before)
		end)
	end)

	describe("派遣費の廃止（D-163）", function()
		it("D-163 どのダンジョンにも派遣費がない（マスターデータ）", function()
			for _, d in master.dungeonList do
				expect(d.dispatchFee).toBe(nil)
			end
			local MasterData = require("../src/core/MasterData")
			local bad = Fixtures.clone(require("../src/data"))
			bad.Dungeons[#bad.Dungeons].dispatchFee = 1000
			expect(function()
				MasterData.load(bad)
			end).toThrow("dispatchFee")
		end)
		it("D-163 最深部のダンジョンでも所持金0で出発でき、ゴールドは減らない", function()
			local s = newState()
			local deepest = master.dungeonList[#master.dungeonList]
			s.unlockedDungeons[deepest.id] = true
			s.gold = 0
			local r = exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = deepest.id })
			expect(r.ok).toBeTruthy()
			expect(s.gold).toBe(0)
		end)
		it("D-163 自動再派遣は所持金0でも止まらない", function()
			local s = newState()
			local deepest = master.dungeonList[#master.dungeonList]
			s.unlockedDungeons[deepest.id] = true
			s.gold = 0
			exec(s, { type = "SetAutoRepeat", partyIndex = 1, dungeonId = deepest.id })
			exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = deepest.id })
			local e = Game.query.expeditionOf(s, 1)
			e.log.rewards.gold = 0
			e.log.rewards.chests = {}
			local events = Game.advance(s, ctx(e.returnAt))
			for _, ev in events do
				expect(ev.type ~= "AutoRepeatStopped").toBeTruthy()
			end
			expect(s.parties[1].autoRepeat ~= nil).toBeTruthy()
			expect(Game.query.expeditionOf(s, 1) ~= nil).toBeTruthy()
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
