--!strict
-- ログインの流れ（S-01 まとめ・帰還の獲得演出・カットイン・カレンダー。D-132・D-208・D-281）
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
		it(
			"D-281 まとめは受け取った報酬の合計だけ：ゴールドは自動売却の分を足し、宝箱の数を合わせる",
			function()
				local s = Game.newState(master, 1, T0)
				local uid = firstUid(s)
				local sum = LoginFlow.summarize({
					{ type = "ExpeditionReturned", partyIndex = 1, chests = 3, gold = 100, itemsSoldGold = 20 },
					{ type = "ExpeditionReturned", partyIndex = 2, chests = 2, gold = 50 },
					{ type = "LevelUp", uid = uid, level = 2 },
				}, s, T0, master)
				expect(sum.show).toBe(true)
				expect(sum.gold).toBe(170)
				expect(sum.chests).toBe(5)
				-- パーティの行・メンバーの顔は持たない（D-281）
				expect((sum :: any).parties).toBe(nil)
			end
		)
		it(
			"D-281 帰ったパーティごとに帰還の出来事をまとめ、番号の順に並べる（閉じたあとの獲得演出の順）",
			function()
				local s = Game.newState(master, 1, T0)
				local sum = LoginFlow.summarize({
					{ type = "ExpeditionReturned", partyIndex = 2, chests = 1, gold = 10 },
					{ type = "ExpeditionReturned", partyIndex = 1, chests = 3, gold = 100 },
					{ type = "ExpeditionReturned", partyIndex = 2, chests = 2, gold = 50 },
				}, s, T0, master)
				expect(#sum.returned).toBe(2)
				expect(sum.returned[1].partyIndex).toBe(1)
				expect(#sum.returned[1].events).toBe(1)
				expect(sum.returned[2].partyIndex).toBe(2)
				expect(#sum.returned[2].events).toBe(2)
			end
		)
		it(
			"D-281 宝箱はレアリティごとの数（出来事に chestsByRank があるとき）。ないときはレアリティを表さない1つ（D-087）",
			function()
				local s = Game.newState(master, 1, T0)
				local sum = LoginFlow.summarize({
					{
						type = "ExpeditionReturned",
						partyIndex = 1,
						chests = 4,
						gold = 0,
						chestsByRank = { [3] = 1, [1] = 3 },
					},
					{ type = "ExpeditionReturned", partyIndex = 2, chests = 2, gold = 0 },
				}, s, T0, master)
				expect(sum.show).toBe(true)
				expect(#sum.chestsByRank).toBe(3)
				expect(sum.chestsByRank[1].rank).toBe(1)
				expect(sum.chestsByRank[1].n).toBe(3)
				expect(sum.chestsByRank[2].rank).toBe(3)
				expect(sum.chestsByRank[2].n).toBe(1)
				expect(sum.chestsByRank[3].rank).toBe(nil)
				expect(sum.chestsByRank[3].n).toBe(2)
			end
		)
		it(
			"D-281 受け取った報酬がなければまとめを出さない（留守の時間だけでは出さない。休息ボーナスは廃止：D-280）",
			function()
				local s = Game.newState(master, 1, T0)
				s.lastSavedAt = T0
				local sum = LoginFlow.summarize({}, s, T0 + 4 * 3600, master)
				expect(sum.show).toBe(false)
				expect(#sum.returned).toBe(0)
				-- 何も持ち帰らなかった帰還（撤退など）は、まとめは出さず獲得演出の対象にだけなる
				local none = LoginFlow.summarize(
					{ { type = "ExpeditionReturned", partyIndex = 1, chests = 0, gold = 0 } },
					s,
					T0,
					master
				)
				expect(none.show).toBe(false)
				expect(#none.returned).toBe(1)
			end
		)
		it(
			"カットインは最大1回：ダンジョンの解放を先に、なければギルドLv（報酬は合わせる）。D-281 ギルドLv だけではまとめを出さない",
			function()
				local s = Game.newState(master, 1, T0)
				local a = LoginFlow.summarize({
					{ type = "GuildLevelUp", level = 5, rewards = { itm_slot_ticket = 3 } },
					{ type = "GuildLevelUp", level = 6, rewards = { itm_slot_ticket = 3 } },
				}, s, T0, master)
				expect(a.show).toBe(false)
				expect(a.guildLevel).toBe(6)
				local c = a.cutIn :: any
				expect(c.kind).toBe("guild")
				expect(c.level).toBe(6)
				expect(c.rewards.itm_slot_ticket).toBe(6)
				local b = LoginFlow.summarize({
					{ type = "GuildLevelUp", level = 5, rewards = {} },
					{ type = "DungeonUnlocked", dungeonId = "dng_a" },
					{ type = "DungeonUnlocked", dungeonId = "dng_b" },
				}, s, T0, master)
				local d = b.cutIn :: any
				expect(d.kind).toBe("dungeon")
				expect(d.dungeonId).toBe("dng_b")
			end
		)
		it(
			"D-208 ④ 受け取り箱に届いたもの（ログインボーナスなど）があればまとめを出し、カレンダーへも渡す",
			function()
				local s = Game.newState(master, 1, T0)
				local sum = LoginFlow.summarize(
					{ { type = "LoginBonus", day = 3, cycle = 1, inboxUid = "inb_9" } },
					s,
					T0,
					master
				)
				expect(sum.show).toBe(true)
				expect(sum.inboxCount).toBe(1)
				expect((sum.loginBonus :: any).day).toBe(3)
			end
		)
		it(
			"D-281 受け取り箱に届いた物を、ゴールド → 宝箱 → アイテム（id の順）→ ユニークで、中身ごとに合わせて並べる",
			function()
				local s = Game.newState(master, 1, T0)
				s.inbox = {
					{
						uid = "inb_1",
						source = "login",
						at = T0,
						rewards = {
							gold = 300,
							items = { itm_slot_ticket = 2 },
							chests = { { pileKey = "special:login", rank = 2, count = 1 } },
						},
					},
					-- 要約（Game.query.inbox）の形：中身が件の直下、宝箱はランクなし（D-087）
					{
						uid = "inb_2",
						source = "quest",
						at = T0,
						gold = 200,
						items = { itm_slot_ticket = 1, itm_potion_appearance_keep = 1 },
						chests = { { pileKey = "special:quest", count = 2 } },
					},
					{ uid = "inb_old", source = "quest", at = T0, rewards = { gold = 999 } }, -- 前から残っている件は数えない
				}
				local sum = LoginFlow.summarize({
					{ type = "LoginBonus", day = 1, cycle = 1, inboxUid = "inb_1" },
					{ type = "QuestBonus", period = "daily", inboxUid = "inb_2" },
				}, s, T0, master)
				expect(sum.inboxCount).toBe(2)
				local lines = sum.inbox
				expect(#lines).toBe(5)
				expect(lines[1].kind).toBe("gold")
				expect(lines[1].n).toBe(500)
				expect(lines[2].kind).toBe("chest")
				expect(lines[2].rank).toBe(2)
				expect(lines[2].n).toBe(1)
				expect(lines[3].kind).toBe("chest")
				expect(lines[3].rank).toBe(nil) -- ランクの分からない箱は最後に1つ
				expect(lines[3].n).toBe(2)
				expect(lines[4].id).toBe("itm_potion_appearance_keep")
				expect(lines[5].id).toBe("itm_slot_ticket")
				expect(lines[5].n).toBe(3)
				-- 受け取り箱の分は「受け取った合計」（gold・chests）には足さない
				expect(sum.gold).toBe(0)
				expect(sum.chests).toBe(0)
			end
		)
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
end
