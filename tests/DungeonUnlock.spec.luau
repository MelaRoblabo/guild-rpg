--!strict
-- ダンジョンの解放（Q-026・D-279）：踏破での無料解放は残し、前のダンジョンが解放済みならゴールドで先に解放できる
local Game = require("../src/core/Game")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1_800_000_000

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()

	local function ctx(now: number)
		return { now = now, master = master, online = true }
	end
	local function newState(): any
		return Game.newState(master, 1, T0)
	end
	local list = master.dungeonList
	local first, second, third = list[1], list[2], list[3]

	local function unlock(s: any, id: string): any
		return Game.execute(s, { type = "UnlockDungeon", dungeonId = id }, ctx(T0))
	end

	describe("D-279 ゴールドで先に解放する", function()
		it(
			"D-279 2番目以降のダンジョンには解放の金額がある（1番目は最初から解放）",
			function()
				expect(first.unlockGold).toBe(nil)
				for i = 2, #list do
					expect(list[i].unlockAfterClear).toBe(list[i - 1].id)
					expect((list[i].unlockGold or 0) > 0).toBe(true)
				end
			end
		)
		it(
			"D-279 前のダンジョンが解放済みなら、踏破の前でも unlockGold を払って解放する",
			function()
				local s = newState()
				expect(s.unlockedDungeons[second.id]).toBe(nil)
				s.gold = second.unlockGold + 7
				local r = unlock(s, second.id)
				expect(r.ok).toBe(true)
				expect(s.unlockedDungeons[second.id]).toBe(true)
				expect(s.gold).toBe(7)
				expect(s.clearedDungeons[first.id]).toBe(nil)
				expect(r.events[1].type).toBe("DungeonUnlocked")
				expect(r.events[1].dungeonId).toBe(second.id)
				expect(r.events[1].gold).toBe(second.unlockGold)
			end
		)
		it("D-279 ゴールドが足りなければ解放しない（NOT_ENOUGH_GOLD）", function()
			local s = newState()
			s.gold = second.unlockGold - 1
			local r = unlock(s, second.id)
			expect(r.ok).toBe(false)
			expect(r.error).toBe("NOT_ENOUGH_GOLD")
			expect(s.unlockedDungeons[second.id]).toBe(nil)
			expect(s.gold).toBe(second.unlockGold - 1)
		end)
		it("D-279 前のダンジョンが未解放なら解放しない（DUNGEON_PREV_LOCKED）", function()
			local s = newState()
			s.gold = 10 ^ 9
			local r = unlock(s, third.id)
			expect(r.ok).toBe(false)
			expect(r.error).toBe("DUNGEON_PREV_LOCKED")
			expect(s.gold).toBe(10 ^ 9)
		end)
		it(
			"D-279 解放済みはもう一度解放できない・ないダンジョンは DUNGEON_NOT_FOUND",
			function()
				local s = newState()
				s.gold = 10 ^ 9
				expect(unlock(s, first.id).error).toBe("DUNGEON_ALREADY_UNLOCKED")
				expect(unlock(s, "dng_nowhere").error).toBe("DUNGEON_NOT_FOUND")
			end
		)
		it("D-279 先に解放したダンジョンへそのまま出発できる", function()
			local s = newState()
			s.gold = second.unlockGold
			unlock(s, second.id)
			local r = Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = second.id }, ctx(T0))
			expect(r.ok).toBe(true)
		end)
	end)
end
