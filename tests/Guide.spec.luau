--!strict
-- 初回の誘導の進み（D-244 ①）
local Game = require("../src/core/Game")
local Protocol = require("../src/core/Protocol")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1_800_000_000

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local function ctx()
		return { now = T0, master = master, online = true }
	end

	describe("D-244 ① 初回の誘導の済んだ段（SetGuideStep・Game.query.guideStep）", function()
		it("新しいセーブは 0。進めた段を保存し、要約にも入る", function()
			local s = Game.newState(master, 1, T0)
			expect(Game.query.guideStep(s)).toBe(0)
			expect(Game.execute(s, { type = "SetGuideStep", step = 2 }, ctx()).ok).toBe(true)
			expect(Game.query.guideStep(s)).toBe(2)
			expect(Protocol.view(s, master).guideStep).toBe(2)
		end)
		it("戻らない（小さい段を送っても変わらない）", function()
			local s = Game.newState(master, 1, T0)
			Game.execute(s, { type = "SetGuideStep", step = 3 }, ctx())
			Game.execute(s, { type = "SetGuideStep", step = 1 }, ctx())
			expect(Game.query.guideStep(s)).toBe(3)
		end)
		it(
			"保存がなく一度でも帰還したセーブ（誘導の前から遊んでいる）は全部済んだ扱い",
			function()
				local s = Game.newState(master, 1, T0)
				s.stats.firstReturnAt = T0
				expect(Game.query.guideStep(s)).toBe(Game.GUIDE_DONE)
			end
		)
		it("形の検証：段は 1 以上の整数", function()
			expect((Protocol.validateCommand({ type = "SetGuideStep", step = 1 }))).toBe(true)
			expect((Protocol.validateCommand({ type = "SetGuideStep", step = 0 }))).toBe(false)
		end)
	end)
end
