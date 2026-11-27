--!strict
-- 報酬のゴールド（D-190、06章 §22）：プレイ時間・クエスト・ログインボーナス・フレンドボタンのゴールドは
-- 踏破した一番深いダンジョンに応じて増える。基準は D-187（未踏破なら古い墓地）
local Chest = require("../src/core/Chest")
local Formulas = require("../src/core/Formulas")
local Friend = require("../src/core/Friend")
local Game = require("../src/core/Game")
local MasterData = require("../src/core/MasterData")
local Quest = require("../src/core/Quest")
local Rng = require("../src/core/Rng")
local Data = require("../src/data")
local Templates = require("../tools/sim/DungeonTemplates")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1767225600 -- 2026-01-01 00:00 UTC

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local K = master.K

	local function ctx(now: number, friendCount: number?)
		return { now = now, master = master, online = true, friendCount = friendCount }
	end
	local function newState()
		return Game.newState(master, 1, T0)
	end
	local function clearUpTo(s: any, n: number)
		for i = 1, n do
			s.clearedDungeons[master.dungeonList[i].id] = true
			s.unlockedDungeons[master.dungeonList[i].id] = true
		end
	end
	local function goldOf(s: any, mult: number): number
		return math.floor(Chest.baseDungeon(s, master).rewardGoldBase * mult)
	end
	local function errorsOf(m: (any) -> ()): string
		local d = Fixtures.clone(Data)
		m(d)
		local lines = {}
		for _, i in MasterData.validate(d) do
			if i.level == "error" then
				table.insert(lines, i.path .. " " .. i.message)
			end
		end
		return table.concat(lines, "\n")
	end
	local function has(s: string, part: string): boolean
		return string.find(s, part, 1, true) ~= nil
	end
	local function noRng(): Rng.Rng
		return Rng.new(1)
	end

	describe("報酬のゴールドの式（D-190、06章 §22）", function()
		it("D-190 D-198 ゴールド = floor(基準のダンジョンの rewardGoldBase × 係数)", function()
			for _, d in master.dungeonList do
				expect(Formulas.rewardGold(d, 1, K)).toBe(d.rewardGoldBase)
				expect(Formulas.rewardGold(d, 2.5, K)).toBe(math.floor(d.rewardGoldBase * 2.5))
			end
			expect(Formulas.rewardGold(master.dungeons.dng_graveyard, 0, K)).toBe(0)
		end)
		it("D-190 深いダンジョンほど基準のゴールドが大きい（仮の値）", function()
			local prev = 0
			for _, d in master.dungeonList do
				expect(d.rewardGoldBase > prev).toBeTruthy()
				prev = d.rewardGoldBase
			end
		end)
		it("D-187 D-190 基準は踏破した一番深いダンジョン。未踏破なら古い墓地", function()
			local s = newState()
			expect(Chest.baseDungeon(s, master).id).toBe("dng_graveyard")
			clearUpTo(s, 5)
			expect(Chest.baseDungeon(s, master).id).toBe(master.dungeonList[5].id)
		end)
	end)

	describe("報酬ごとのゴールド（D-190）", function()
		it(
			"D-190 ログインボーナスのゴールドは受け取り箱に入れたときの踏破で決まる",
			function()
				local mult = master.loginBonus.days[1].goldMult
				expect(mult ~= nil).toBeTruthy()
				local a = newState()
				Game.advance(a, ctx(T0))
				expect(a.inbox[1].rewards.gold).toBe(math.floor(master.dungeons.dng_graveyard.rewardGoldBase * mult))
				local b = newState()
				clearUpTo(b, 6)
				Game.advance(b, ctx(T0))
				expect(b.inbox[1].rewards.gold).toBe(math.floor(master.dungeonList[6].rewardGoldBase * mult))
				expect(b.inbox[1].rewards.gold > a.inbox[1].rewards.gold).toBeTruthy()
				-- 額は入れたときに決まり、後で深く踏破しても変わらない
				local before = b.inbox[1].rewards.gold
				clearUpTo(b, 10)
				local gold0 = b.gold
				expect(Game.execute(b, { type = "ClaimInbox" }, ctx(T0)).ok).toBeTruthy()
				expect(b.gold).toBe(gold0 + before)
			end
		)
		it("D-190 プレイ時間のゴールドは踏破に応じて増える", function()
			local step = master.playtimeRewards[1]
			expect(step.rewards.goldMult ~= nil).toBeTruthy()
			local function playtimeGold(n: number): number
				local s = newState()
				clearUpTo(s, n)
				Game.advance(s, ctx(T0))
				s.inbox = {}
				Game.advance(s, ctx(T0 + step.minutes * 60))
				expect(s.inbox[1].source).toBe("playtime")
				expect(s.inbox[1].rewards.gold).toBe(goldOf(s, step.rewards.goldMult))
				return s.inbox[1].rewards.gold
			end
			expect(playtimeGold(0) < playtimeGold(4)).toBeTruthy()
			expect(playtimeGold(4) < playtimeGold(12)).toBeTruthy()
		end)
		it(
			"D-190 クエストのゴールドは踏破に応じて増える（全部達成のボーナスも同じ形）",
			function()
				local row = master.quests.qst_daily_expeditions
				expect(row.rewards.goldMult ~= nil).toBeTruthy()
				local function questGold(n: number): number
					local s = newState()
					clearUpTo(s, n)
					s.quests.daily = {
						dayIndex = 0,
						entries = { { questId = row.id, target = 1, progress = 0, done = false } },
						bonusDone = true,
					}
					s.quests.weekly = { weekIndex = 0, entries = {}, bonusDone = true }
					Quest.count(s, "expeditions", 1, T0, master, noRng, {})
					local got = Quest.claim(s, "daily", row.id, master, noRng) -- D-286：クエストの面で受け取る
					expect(got.gold).toBe(goldOf(s, row.rewards.goldMult))
					return got.gold
				end
				expect(questGold(0)).toBe(
					math.floor(master.dungeons.dng_graveyard.rewardGoldBase * row.rewards.goldMult)
				)
				expect(questGold(8) > questGold(0)).toBeTruthy()
			end
		)
		it("D-190 フレンドボタンのゴールドは踏破に応じて増える", function()
			local function expected(s: any, n: number): number
				local c = math.min(n, K.friendRewardMaxFriends)
				return goldOf(s, K.friendRewardGoldMult * (1 + K.friendRewardBonusPerFriend * (c - 1)))
			end
			local a = newState()
			local b = newState()
			clearUpTo(b, 7)
			for n = 1, 4 do
				expect(Friend.gold(a, n, master)).toBe(expected(a, n))
				expect(Friend.gold(b, n, master)).toBe(expected(b, n))
				expect(Friend.gold(b, n, master) > Friend.gold(a, n, master)).toBeTruthy()
			end
			expect(Friend.gold(b, 0, master)).toBe(0)
			-- 押したときに入る額・画面用の見込みも同じ
			local gold0 = b.gold
			local r = Game.execute(b, { type = "ClaimFriendReward" }, ctx(T0, 2))
			expect(r.ok).toBeTruthy()
			expect(r.events[1].gold).toBe(expected(b, 2))
			expect(b.gold).toBe(gold0 + expected(b, 2))
			expect(Game.query.friend(b, T0, 2, master).gold).toBe(expected(b, 2))
		end)
	end)

	describe("マスターデータの検証（D-190）", function()
		it("D-190 本番データは通り、報酬に固定額のゴールド（gold）は置かない", function()
			expect(errorsOf(function(_d) end)).toBe("")
			expect(has(
				errorsOf(function(d)
					d.Quests[1].rewards = { gold = 500 }
				end),
				"Quests[1].rewards"
			)).toBeTruthy()
			expect(has(
				errorsOf(function(d)
					d.PlaytimeRewards[1].rewards = { goldMult = -1 }
				end),
				"PlaytimeRewards[1].rewards.goldMult"
			)).toBeTruthy()
			expect(has(
				errorsOf(function(d)
					d.Constants.friendRewardGoldMult = nil
				end),
				"Constants.friendRewardGoldMult"
			)).toBeTruthy()
		end)
		it(
			"D-190 D-198 rewardGoldBase はすべてのダンジョンに1つずつ（ダンジョンの行に持ち、Constants には置かない）",
			function()
				expect(has(
					errorsOf(function(d)
						d.Dungeons[#d.Dungeons].rewardGoldBase = nil
					end),
					`Dungeons[{#Data.Dungeons}].rewardGoldBase`
				)).toBeTruthy()
				expect(has(
					errorsOf(function(d)
						d.Dungeons[1].rewardGoldBase = -1
					end),
					"Dungeons[1].rewardGoldBase"
				)).toBeTruthy()
				expect(has(
					errorsOf(function(d)
						d.Dungeons[1].rewardGoldBase = 1.5
					end),
					"Dungeons[1].rewardGoldBase"
				)).toBeTruthy()
				-- 古い置き場所（Constants.rewardGoldBase）に残っていたら止める（D-198）
				expect(has(
					errorsOf(function(d)
						d.Constants.rewardGoldBase = { dng_graveyard = 100 }
					end),
					"Constants.rewardGoldBase"
				)).toBeTruthy()
			end
		)
		it(
			"D-198 D-188 Dungeons の rewardGoldBase・宝箱の表はダンジョンのひな形（DungeonTemplates）の値を写したもの",
			function()
				expect(#Templates).toBe(#Data.Dungeons)
				for i, tpl in Templates do
					local d = Data.Dungeons[i]
					expect(d.id).toBe(tpl.id)
					expect(d.rewardGoldBase).toBe(tpl.rewardGoldBase)
					-- 宝箱の表と2本の演出ラインも写す（D-085, D-188）
					expect(d.chestRarityWeights).toEqual(tpl.chestRarityWeights)
					expect(d.chestEffectMinRarity).toBe(tpl.chestEffectMinRarity)
					expect(d.rareChestEffectMinRarity).toBe(tpl.rareChestEffectMinRarity)
				end
			end
		)
	end)
end
