--!strict
-- 他のプレイヤーに見せる公開情報（D-108・D-121・D-151、11章（システム）§6）
local Game = require("../src/core/Game")
local Protocol = require("../src/core/Protocol")
local World = require("../src/core/World")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1_800_000_000

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()

	local function dispatched(): any
		local s = Game.newState(master, 1, T0)
		local r = Game.execute(
			s,
			{ type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" },
			{ now = T0, master = master, online = true }
		)
		assert(r.ok, "出発できない")
		return s
	end

	describe("D-121 WorldChanged の公開情報（World.publicInfo）", function()
		it("探索中のパーティだけを、位置を求める時刻と時間だけで返す", function()
			local s = dispatched()
			local info = World.publicInfo(s, 42, T0 + 1)
			expect(info.userId).toBe(42)
			expect(info.guildLevel).toBe(s.guild.level)
			expect(#info.parties).toBe(1)
			local p = info.parties[1] :: any
			expect(p.index).toBe(1)
			expect(p.dungeonId).toBe("dng_graveyard")
			expect(p.departAt).toBe(T0)
			expect(p.totalSeconds > p.travelSeconds).toBe(true)
			-- 隠す情報（探索ログ・宝箱・HP・メンバー）は入れない
			local keys = {}
			for k in p do
				table.insert(keys, k)
			end
			expect(#keys).toBe(5)
		end)
		it("帰る時刻を過ぎたパーティ・待機のパーティは入れない", function()
			local s = dispatched()
			local total = (World.publicInfo(s, 1, T0).parties[1] :: any).totalSeconds
			expect(#World.publicInfo(s, 1, T0 + total).parties).toBe(0)
			expect(#World.publicInfo(Game.newState(master, 1, T0), 1, T0).parties).toBe(0)
		end)
		it("変わったときだけ送る（World.same）", function()
			local s = dispatched()
			local a = World.publicInfo(s, 1, T0)
			local b = World.publicInfo(s, 1, T0 + 5)
			expect(World.same(a, b)).toBe(true)
			local c = World.publicInfo(Game.newState(master, 1, T0), 1, T0)
			expect(World.same(a, c)).toBe(false)
			expect(World.same(nil, nil)).toBe(true)
			expect(World.same(a, nil)).toBe(false)
		end)
	end)

	describe("D-108 Inspect の詳細（World.inspect）", function()
		it("メンバーの name・jobId・level・appearanceId とギルドLvだけを返す", function()
			local s = dispatched()
			local d = World.inspect(s, 1, T0 + 1) :: any
			expect(d ~= nil).toBe(true)
			expect(d.guildLevel).toBe(s.guild.level)
			expect(d.dungeonId).toBe("dng_graveyard")
			expect(#d.members > 0).toBe(true)
			for _, m in d.members do
				local n = 0
				for _ in m do
					n += 1
				end
				expect(n).toBe(4)
				expect(type(m.name)).toBe("string")
				expect(type(m.level)).toBe("number")
			end
		end)
		it(
			"Inspect の形：Studio のテストのプレイヤー（番号がマイナス）も受け付け、パーティの番号がなければ断る",
			function()
				expect((Protocol.validateCommand({ type = "Inspect", userId = 12345, partyIndex = 1 }))).toBe(true)
				expect((Protocol.validateCommand({ type = "Inspect", userId = -2, partyIndex = 1 }))).toBe(true)
				expect((Protocol.validateCommand({ type = "Inspect", userId = 12345 }))).toBe(false)
			end
		)
		it("探索中でなければ nil（NOT_FOUND）", function()
			local s = Game.newState(master, 1, T0)
			expect(World.inspect(s, 1, T0)).toBe(nil)
			expect(World.inspect(dispatched(), 2, T0)).toBe(nil)
		end)
	end)
end
