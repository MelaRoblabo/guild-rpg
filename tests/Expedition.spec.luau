--!strict
local Events = require("../src/core/Events")
local Expedition = require("../src/core/Expedition")
local Formulas = require("../src/core/Formulas")
local Rng = require("../src/core/Rng")
local Fixtures = require("./helpers/Fixtures")

local function party(master: any, level: number): { any }
	local jobs = { "job_warrior", "job_thief", "job_mage", "job_priest" }
	local out = {}
	for i, jobId in jobs do
		local job = master.jobs[jobId]
		local base = {}
		for _, s in { "str", "mag", "agi", "dex", "hp" } do
			base[s] = 12 + job.growth[s] * (level - 1) + (if s == "hp" then 33 else 0)
		end
		table.insert(
			out,
			Formulas.memberSnapshot(
				{ uid = "m" .. i, slot = i, jobId = jobId, baseStats = base, giftIds = {}, equipment = {} },
				master
			)
		)
	end
	return out
end

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local K = master.K

	local function run(seed: number, level: number, dungeonId: string?, m: any?)
		local mm = m or master
		return Expedition.simulate({
			seed = seed,
			departAt = 1000,
			dungeonId = dungeonId or "dng_graveyard",
			members = party(mm, level),
		}, mm)
	end

	describe("構造", function()
		it("D-026 同じ入力なら同じログ（決定論）", function()
			expect(run(42, 5)).toEqual(run(42, 5))
		end)
		it("D-001 奇数フロア＝戦闘、偶数フロア＝イベント", function()
			local log = run(1, 30)
			expect(log.result).toBe("clear")
			for _, f in log.floors do
				expect(f.kind).toBe(if f.floor % 2 == 1 then "battle" else "event")
			end
		end)
		it("D-001 最終フロアはボス", function()
			local log = run(1, 30)
			local last = log.floors[#log.floors]
			expect(last.monsterId).toBe("mon_bone_lord")
		end)
		it("D-003 n番目の戦闘は基準値×(1+0.2(n−1))", function()
			local log = run(1, 30)
			local d = master.dungeons.dng_graveyard
			expect(log.floors[1].monsterStats.hp).toBe(d.base.hp)
			expect(log.floors[3].monsterStats.hp).toBe(math.floor(d.base.hp * 1.2))
			expect(log.floors[7].monsterStats.hp).toBe(math.floor(d.base.hp * 1.6))
		end)
	end)

	describe("報酬", function()
		it("D-019 踏破で確定宝箱が1個以上", function()
			local log = run(5, 30)
			expect(log.result).toBe("clear")
			expect(#(log.clearChestRanks :: any) >= 1).toBeTruthy()
		end)
		it("D-012 / D-041 戦闘勝利の経験値は生存者で等分、ゴールドを得る", function()
			local log = run(7, 30)
			local d = master.dungeons.dng_graveyard
			local expectedGold = 0
			for n = 1, 4 do
				expectedGold += math.floor(d.battleReward.gold * Formulas.monsterScale(n, K))
			end
			expect(log.rewards.gold).toBe(expectedGold)
			local first = log.rewards.exp.m1
			for _, uid in { "m2", "m3", "m4" } do
				expect(log.rewards.exp[uid]).toBe(first)
			end
		end)
		it("D-013 全滅で撤退しても確保済みの宝箱は持ち帰る", function()
			-- 強すぎるダンジョンで撤退するログを探す
			for level = 1, 20 do
				for seed = 1, 50 do
					local log = run(seed, level, "dng_tower")
					if log.result == "retreat" and #log.rewards.chests > 0 then
						expect(log.clearChestRanks).toBe(nil)
						return
					end
				end
			end
			error("撤退かつ宝箱ありのログが見つからない")
		end)
		it("Q-017 ギルド経験値＝攻略フロア数＋踏破ボーナス", function()
			local log = run(1, 30)
			expect(log.rewards.guildExp).toBe(7 * K.guildExpPerFloor + K.guildExpClearBonus)
		end)
	end)

	describe("時間（D-026）", function()
		it("所要秒＝片道×2＋再生秒（戦闘1ターン1秒、イベント2秒）", function()
			local log = run(3, 10)
			local replay = 0
			for _, f in log.floors do
				if f.kind == "battle" then
					replay += #(f.turns :: any) * K.replaySecondsPerTurn
				else
					replay += K.replaySecondsPerEvent
				end
			end
			expect(log.replaySeconds).toBe(replay)
			expect(log.totalSeconds).toBe(log.travelSeconds * 2 + replay)
		end)
		it("再生位置：行き → フロア → 帰り → 帰還", function()
			local log = run(3, 10)
			expect(Expedition.progressAt(log, 1000).phase).toBe("outbound")
			local f1 = Expedition.progressAt(log, 1000 + log.travelSeconds)
			expect(f1.phase).toBe("floor")
			expect(f1.floorIndex).toBe(1)
			expect(Expedition.progressAt(log, 1000 + log.travelSeconds + log.replaySeconds).phase).toBe("inbound")
			expect(Expedition.progressAt(log, 1000 + log.totalSeconds).phase).toBe("returned")
		end)
	end)

	describe("イベント", function()
		local function ctxWith(members: { any }, dungeonId: string?, seed: number?)
			return {
				members = members,
				dungeon = master.dungeons[dungeonId or "dng_ruins"],
				rng = Rng.new(seed or 1),
				K = K,
				rewards = { exp = {}, gold = 0, chests = {}, items = {}, floorsCleared = 0, guildExp = 0 },
				giftTriggers = {},
			}
		end

		it("D-014 統計: イベント確率 40/15/20/10/15%（5万回、誤差±1%）", function()
			local counts = {}
			local n = 50000
			local ctx = ctxWith({ Fixtures.memberState({ maxHp = 1000000, dex = 1000000 }) })
			for _ = 1, n do
				local kind = Events.run(ctx)
				counts[kind] = (counts[kind] or 0) + 1
			end
			expect(counts.chest / n).toBeCloseTo(0.40, 0.01)
			expect(counts.item / n).toBeCloseTo(0.15, 0.01)
			expect(counts.trap / n).toBeCloseTo(0.20, 0.01)
			expect(counts.fountain / n).toBeCloseTo(0.10, 0.01)
			expect(counts.none / n).toBeCloseTo(0.15, 0.01)
		end)
		it(
			"D-085 統計: 宝箱のレアリティはダンジョンの出現率の表どおり（罠の遺跡）",
			function()
				local ctx = ctxWith({ Fixtures.memberState({}) }, "dng_ruins")
				local w = master.dungeons.dng_ruins.chestRarityWeights
				local total = 0
				for _, x in w do
					total += x
				end
				local counts = table.create(master.rarityCount, 0)
				local n = 50000
				for _ = 1, n do
					counts[Events.rollChestRank(ctx)] += 1
				end
				for r = 1, master.rarityCount do
					expect(counts[r] / n).toBeCloseTo((w[r] or 0) / total, 0.01)
				end
			end
		)
		it("D-085 古い墓地はコモン・アンコモンだけ、罠の遺跡はレアまで", function()
			expect(#master.dungeons.dng_graveyard.chestRarityWeights).toBe(2)
			expect(#master.dungeons.dng_ruins.chestRarityWeights).toBe(3)
		end)
		it("D-085 深いダンジョンほどコモンが減り、上位が増える（緩やかに）", function()
			local prevCommon, prevTop = math.huge, -1
			for _, d in master.dungeonList do
				local total, top = 0, 0
				for r, x in d.chestRarityWeights do
					total += x
					if r >= 4 then
						top += x
					end
				end
				local common = (d.chestRarityWeights[1] or 0) / total
				expect(common <= prevCommon).toBeTruthy()
				expect(top / total >= prevTop).toBeTruthy()
				prevCommon, prevTop = common, top / total
			end
		end)
		it(
			"D-085 最も深いダンジョンでも最上位のレアリティは1割未満（ハズレがある）",
			function()
				local d = master.dungeonList[#master.dungeonList]
				local total = 0
				for _, x in d.chestRarityWeights do
					total += x
				end
				expect((d.chestRarityWeights[master.rarityCount] or 0) / total < 0.1).toBeTruthy()
				expect((d.chestRarityWeights[master.rarityCount] or 0) / total > 0).toBeTruthy()
			end
		)
		it("D-017 罠に技巧0で挑むと全員がダメージ、全滅もありうる", function()
			-- 罠が出るまで回す
			for seed = 1, 500 do
				local members =
					{ Fixtures.memberState({ maxHp = 10, dex = 0 }, 1), Fixtures.memberState({ slot = 2, dex = 0 }, 1) }
				local ctx = ctxWith(members, "dng_ruins", seed)
				local kind, detail, wiped = Events.run(ctx)
				if kind == "trap" then
					expect(detail.evaded).toBeFalsy()
					expect(wiped).toBeTruthy()
					return
				end
			end
			error("罠が出なかった")
		end)
		it("D-018 泉は戦闘不能者を復活させない", function()
			for seed = 1, 500 do
				local members =
					{ Fixtures.memberState({ maxHp = 100 }, 0), Fixtures.memberState({ slot = 2, maxHp = 100 }, 50) }
				local ctx = ctxWith(members, "dng_ruins", seed)
				local kind = Events.run(ctx)
				if kind == "fountain" then
					expect(members[1].hp).toBe(0)
					expect(members[2].hp).toBe(75)
					return
				end
			end
			error("泉が出なかった")
		end)
		it("D-019 幸運所持者がいれば追加の宝箱が出ることがある", function()
			local extra = 0
			local ctx = ctxWith({ Fixtures.memberState({ lucky = true }) }, "dng_graveyard")
			for _ = 1, 10000 do
				local ranks = Events.secureChest(ctx)
				if #ranks == 2 then
					extra += 1
				end
			end
			expect(extra / 10000).toBeCloseTo(K.luckyChancePerHolder, 0.015)
		end)
	end)
end
