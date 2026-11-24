--!strict
-- S-15 の攻略ヒントと適性の4人（D-048・D-114・D-235 ①②）
local AutoEquip = require("../src/core/AutoEquip")
local ExclusiveGift = require("../src/core/ExclusiveGift")
local Formulas = require("../src/core/Formulas")
local Game = require("../src/core/Game")
local Hint = require("../src/client/party/Hint")
local Party = require("../src/core/Party")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1_800_000_000

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local deps = {
		weights = AutoEquip.weights,
		snapshot = Game.query.snapshot,
		busy = Party.isAdventurerBusy,
		partySnapshots = Game.query.partySnapshots,
		trapEvadeRate = Formulas.trapEvadeRate,
		travelSeconds = Formulas.travelSeconds,
		partyTravelMult = function(snaps, m)
			return ExclusiveGift.partyEffects(snaps, m).travelMult
		end,
	}

	describe("D-048 攻略ヒント", function()
		it("多い種族は出現の重みの多い順（呪われた修道院はアンデッドが先）", function()
			local list = Hint.races(master.dungeons["dng_abbey"], master)
			expect(list[1].word).toBe("Undead")
		end)
		it("D-235 ② 物理防御＝魔法防御なら有利なし、低い方を突ける区分が有利", function()
			expect(Hint.favored(master.dungeons["dng_labyrinth"])).toBe(nil)
			local abbey = master.dungeons["dng_abbey"]
			local fav = Hint.favored(abbey)
			expect(fav == (if abbey.base.pdef < abbey.base.mdef then "physical" else "magic")).toBe(true)
		end)
	end)

	describe("D-114 適性の4人（Hint.suited）", function()
		it("有利な区分の人を先に、そのあと Lv の高い順", function()
			local s = Game.newState(master, 1, T0)
			local abbey = master.dungeons["dng_abbey"]
			local fav = Hint.favored(abbey)
			local list = Hint.suited(s, abbey, false, master, deps)
			expect(#list).toBe(4)
			local first = s.adventurers[list[1]]
			expect(master.jobs[first.jobId].attackType).toBe(fav)
		end)
		it("D-235 ① 編成では探索中の人を除く", function()
			local s = Game.newState(master, 1, T0)
			local ctx = { now = T0, master = master, online = true }
			expect(Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx).ok).toBe(
				true
			)
			local list = Hint.suited(s, master.dungeons["dng_graveyard"], true, master, deps)
			for _, uid in list do
				expect(Party.isAdventurerBusy(s, uid)).toBe(false)
			end
		end)
	end)

	describe("パーティからの見込み（Hint.forParty）", function()
		it("罠の避けやすさは 0〜1、移動時間は正", function()
			local s = Game.newState(master, 1, T0)
			local evade, travel = Hint.forParty(s, 1, master.dungeons["dng_graveyard"], master, deps)
			expect(evade > 0 and evade < 1).toBe(true)
			expect(travel > 0).toBe(true)
		end)
	end)
end
