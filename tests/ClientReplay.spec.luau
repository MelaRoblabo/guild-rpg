--!strict
-- 探索ウィンドウの再生（D-026・D-115・D-236）：core の探索ログから見せる中身を作る
local Game = require("../src/core/Game")
local Party = require("../src/core/Party")
local Replay = require("../src/client/party/Replay")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1_800_000_000

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local K = master.K

	local function expedition(): (any, any, { number }, { number })
		local s = Game.newState(master, 1, T0)
		local r = Game.execute(
			s,
			{ type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" },
			{ now = T0, master = master, online = true }
		)
		assert(r.ok, "出発できない")
		local e = nil
		for _, x in s.expeditions do
			e = x
		end
		local slots, maxHp = {}, {}
		for _, uid in e.memberUids do
			local _, slot = Party.find(s, uid)
			table.insert(slots, slot)
			table.insert(maxHp, Game.query.snapshot(s, uid, master).maxHp)
		end
		return s, e, slots, maxHp
	end

	describe("D-026 再生の位置（Replay.at）", function()
		it("行きの移動中は outbound、満タンの HP", function()
			local _, e, slots, maxHp = expedition()
			local st = Replay.at(e.log, slots, maxHp, e.departAt + 0.5, K)
			expect(st.phase).toBe("outbound")
			expect(st.hp[1]).toBe(maxHp[1])
		end)
		it(
			"D-236 戦闘のフロアはターンとモンスターの HP の割合、終わりは記録どおりの HP",
			function()
				local _, e, slots, maxHp = expedition()
				local f = nil
				for _, x in e.log.floors do
					if x.kind == "battle" and x.turns and #x.turns > 0 then
						f = x
						break
					end
				end
				assert(f, "戦闘のフロアがない")
				local first = Replay.at(e.log, slots, maxHp, e.departAt + f.startOffset + 0.1, K)
				expect(first.phase).toBe("floor")
				expect(first.kind).toBe("battle")
				expect(first.turn).toBe(1)
				expect(first.monsterRatio ~= nil and first.monsterRatio <= 1).toBe(true)
				local last = Replay.at(e.log, slots, maxHp, e.departAt + f.startOffset + f.duration - 0.01, K)
				expect(last.turn).toBe(#f.turns)
				for i, v in f.hpAfter do
					expect(last.hp[i]).toBe(v)
				end
			end
		)
		it("D-236 帰り道は残り時間と持ち帰る宝箱、帰ったら returned", function()
			local _, e, slots, maxHp = expedition()
			local back = e.departAt + e.log.travelSeconds + e.log.replaySeconds + 0.5
			local st = Replay.at(e.log, slots, maxHp, back, K)
			expect(st.phase).toBe("inbound")
			expect(st.remaining > 0).toBe(true)
			local n = 0
			for _, f in e.log.floors do
				if f.gained and f.gained.chestTo >= f.gained.chestFrom then
					n += f.gained.chestTo - f.gained.chestFrom + 1
				end
			end
			expect(st.chests).toBe(n)
			expect(Replay.at(e.log, slots, maxHp, e.returnAt + 1, K).phase).toBe("returned")
		end)
	end)
end
