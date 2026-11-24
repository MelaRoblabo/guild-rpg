--!strict
-- ログインの流れ（S-01 まとめ・カットイン・カレンダー。D-132・D-208）
local Game = require("../src/core/Game")
local LoginFlow = require("../src/client/login/LoginFlow")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1_800_000_000

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()

	local function firstUid(s: any): string
		for _, uid in s.parties[1].slots do
			if uid then
				return uid
			end
		end
		error("no member")
	end

	describe("D-132 ログイン時のまとめは1枚（LoginFlow.summarize）", function()
		it("帰還をパーティごとに合わせ、ゴールドは自動売却の分を足す", function()
			local s = Game.newState(master, 1, T0)
			local uid = firstUid(s)
			local sum = LoginFlow.summarize({
				{ type = "ExpeditionReturned", partyIndex = 1, chests = 3, gold = 100, itemsSoldGold = 20 },
				{ type = "ExpeditionReturned", partyIndex = 1, chests = 2, gold = 50 },
				{ type = "LevelUp", uid = uid, level = 2 },
			}, s)
			expect(sum.show).toBe(true)
			expect(sum.gold).toBe(170)
			expect(sum.chests).toBe(5)
			local p = sum.parties[1]
			expect(p.index).toBe(1)
			expect(p.moved).toBe(true)
			expect(p.chests).toBe(5)
			local up = false
			for _, m in p.members do
				if m.uid == uid then
					up = m.up
				end
			end
			expect(up).toBe(true)
		end)
		it(
			"メンバーのいないパーティは出さず、帰らなかったパーティは moved = false（D-161）",
			function()
				local s = Game.newState(master, 1, T0)
				local sum = LoginFlow.summarize({}, s)
				expect(sum.show).toBe(false)
				for _, p in sum.parties do
					expect(#p.members > 0).toBe(true)
					expect(p.moved).toBe(false)
				end
			end
		)
		it(
			"カットインは最大1回：ダンジョンの解放を先に、なければギルドLv（報酬は合わせる）",
			function()
				local s = Game.newState(master, 1, T0)
				local a = LoginFlow.summarize({
					{ type = "GuildLevelUp", level = 5, rewards = { itm_slot_ticket = 3 } },
					{ type = "GuildLevelUp", level = 6, rewards = { itm_slot_ticket = 3 } },
				}, s)
				expect(a.show).toBe(true)
				expect(a.guildLevel).toBe(6)
				local c = a.cutIn :: any
				expect(c.kind).toBe("guild")
				expect(c.level).toBe(6)
				expect(c.rewards.itm_slot_ticket).toBe(6)
				local b = LoginFlow.summarize({
					{ type = "GuildLevelUp", level = 5, rewards = {} },
					{ type = "DungeonUnlocked", dungeonId = "dng_a" },
					{ type = "DungeonUnlocked", dungeonId = "dng_b" },
				}, s)
				local d = b.cutIn :: any
				expect(d.kind).toBe("dungeon")
				expect(d.dungeonId).toBe("dng_b")
			end
		)
		it("D-208 ログインボーナスだけならまとめは出さず、カレンダーへ渡す", function()
			local s = Game.newState(master, 1, T0)
			local sum = LoginFlow.summarize({ { type = "LoginBonus", day = 3, cycle = 1 } }, s)
			expect(sum.show).toBe(false)
			expect((sum.loginBonus :: any).day).toBe(3)
		end)
	end)

	describe("D-155 カレンダーの1日分の中身（LoginFlow.dayRewards）", function()
		it(
			"ゴールド → 宝箱 → チケット → ほかのアイテムの順。ゴールドは goldOf で額にする",
			function()
				local lines = LoginFlow.dayRewards({
					goldMult = 50,
					chests = { { pileKey = "special:login", count = 300 }, { pileKey = "special:login", count = 200 } },
					items = { itm_potion_appearance_keep = 1, itm_slot_ticket = 5, itm_potion_appearance_change = 1 },
				}, function(m)
					return m * 10
				end)
				expect(#lines).toBe(5)
				expect(lines[1].kind).toBe("gold")
				expect(lines[1].n).toBe(500)
				expect(lines[2].kind).toBe("chest")
				expect(lines[2].n).toBe(500)
				expect(lines[3].id).toBe("itm_slot_ticket")
				expect(lines[4].id).toBe("itm_potion_appearance_change")
				expect(lines[5].id).toBe("itm_potion_appearance_keep")
			end
		)
		it("マスの状態：受け取った日より前は past・同じ日は today・後は future", function()
			expect(LoginFlow.cellState(2, 4)).toBe("past")
			expect(LoginFlow.cellState(4, 4)).toBe("today")
			expect(LoginFlow.cellState(6, 4)).toBe("future")
		end)
	end)

	describe("D-162 休息ボーナスの輪", function()
		it("上限に対する割合（0〜1）", function()
			local s = Game.newState(master, 1, T0)
			s.restBonusSeconds = master.K.restBonusMaxSeconds / 2
			expect(LoginFlow.restShare(s, master)).toBe(0.5)
			s.restBonusSeconds = master.K.restBonusMaxSeconds * 3
			expect(LoginFlow.restShare(s, master)).toBe(1)
		end)
	end)
end
