--!strict
-- バランスの成績表（MB。tools/balance）：目標の表と計算・判定・上書きがずれていないか
local Data = require("../src/data")
local Judge = require("../tools/balance/Judge")
local Metrics = require("../tools/balance/Metrics")
local Overrides = require("../tools/balance/Overrides")

local SIM_METRICS = { stageClearRate = true, stageMedianSeconds = true, earlyUnlockClearRate = true }

local function clone(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = clone(x)
	end
	return out
end

local function agg(values: { any }): any
	return Judge.aggregate(values, #values)
end

return function(suite)
	local describe, it, expect = suite.describe, suite.it, suite.expect

	describe("目標の表と計算", function()
		it(
			"D-291 目標の表の指標はすべてツールで計算できる（仕様を足したら計算も足す）",
			function()
				for _, row in Data.BalanceTargets.targets do
					if row.source == "autoplay" then
						expect(Metrics.autoplay[row.metric] ~= nil).toBe(true)
					else
						expect(SIM_METRICS[row.metric]).toBe(true)
					end
				end
			end
		)
	end)

	describe("判定", function()
		local function row(over: any): any
			local r = { id = "bal_x", name = "x", decision = "D-291", metric = "daysToMaxGrowth" }
			for k, v in over do
				r[k] = v
			end
			return r
		end

		it("D-291 暦日数は seed の平均が目標の ±10% なら合格、外れれば不合格", function()
			local t = row({ judge = "near", byProfile = { core = 30 }, tol = 0.10 })
			expect(Judge.judge(t, "core", agg({ 28, 34 }), nil, 45).status).toBe("pass")
			expect(Judge.judge(t, "core", agg({ 34, 36 }), nil, 45).status).toBe("fail")
		end)
		it("D-291 1つの seed でも最大の育成に届かなければ不合格（未到達）", function()
			local t = row({ judge = "near", byProfile = { core = 30 }, tol = 0.10 })
			local r = Judge.judge(t, "core", agg({ 30, false }), nil, 45)
			expect(r.status).toBe("fail")
			expect(string.find(r.summary, "未到達", 1, true) ~= nil).toBe(true)
		end)
		it("D-292 10倍以上（atLeast）と D-296 3日分まで（atMost）", function()
			local lo = row({ metric = "onlineRatioChests", judge = "atLeast", value = 10 })
			expect(Judge.judge(lo, "core", agg({ 9.8 }), nil, nil).status).toBe("fail")
			expect(Judge.judge(lo, "core", agg({ 10.2 }), nil, nil).status).toBe("pass")
			local hi = row({ metric = "maxBalanceDays", judge = "atMost", value = 3 })
			expect(Judge.judge(hi, "core", agg({ 2.9 }), nil, nil).status).toBe("pass")
			expect(Judge.judge(hi, "core", agg({ 3.1 }), nil, nil).status).toBe("fail")
		end)
		it("D-293 配分は書いた列だけを ±tolPt で判定する", function()
			local t =
				row({ metric = "shareTools", judge = "share", columns = { adventure = 50, quest = 20 }, tolPt = 5 })
			local ok = Judge.judge(t, "core", agg({ { adventure = 53, quest = 18, guild = 9 } }), nil, nil)
			expect(ok.status).toBe("pass")
			expect(#ok.details).toBe(2)
			local ng = Judge.judge(t, "core", agg({ { adventure = 80, quest = 5 } }), nil, nil)
			expect(ng.status).toBe("fail")
		end)
		it("D-294 sim の指標はダンジョンごとに判定し、byDungeon が value より優先", function()
			local t = row({
				metric = "stageClearRate",
				judge = "near",
				value = 0.6,
				byDungeon = { dng_graveyard = 0.97 },
				tolAbs = 0.1,
			})
			local r = Judge.judge(t, nil, agg({ { dng_graveyard = 0.95, dng_ruins = 0.62 } }), nil, nil)
			expect(r.status).toBe("pass")
			local r2 = Judge.judge(t, nil, agg({ { dng_graveyard = 0.62 } }), nil, nil)
			expect(r2.status).toBe("fail")
		end)
		it("D-295 基準の判定：基準がなければ info、幅を超えてずれたら警告", function()
			local t = row({ metric = "milestoneDays", judge = "baseline" })
			local now = agg({ { ["初めての転生"] = 2.0, ["パーティ枠 → 3"] = 5.0 } })
			expect(Judge.judge(t, "core", now, nil, nil).status).toBe("info")
			local base = { ["初めての転生"] = { mean = 1.9 }, ["パーティ枠 → 3"] = { mean = 5.1 } }
			expect(Judge.judge(t, "core", now, base, nil).status).toBe("pass")
			local moved = { ["初めての転生"] = { mean = 1.0 }, ["パーティ枠 → 3"] = { mean = 5.1 } }
			expect(Judge.judge(t, "core", now, moved, nil).status).toBe("warn")
		end)
	end)

	describe("値の上書き", function()
		it("配列の中は id で探して上書きし、無いパスはエラー", function()
			local d = clone(Data)
			Overrides.apply(d, { Overrides.parse("Dungeons.dng_ruins.unlockGold=500") })
			local found
			for _, dg in d.Dungeons do
				if dg.id == "dng_ruins" then
					found = dg.unlockGold
				end
			end
			expect(found).toBe(500)
			expect(function()
				Overrides.apply(d, { Overrides.parse("Constants.noSuchValue=1") })
			end).toThrow("見つからない")
		end)
	end)
end
