--!strict
-- バランスの成績表（MB。tools/balance）：目標の表と計算・判定・上書きがずれていないか
local Data = require("../src/data")
local Judge = require("../tools/balance/Judge")
local Metrics = require("../tools/balance/Metrics")
local Overrides = require("../tools/balance/Overrides")
local Experience = require("../tools/balance/Experience")
local MasterData = require("../src/core/MasterData")
local Score = require("../tools/balance/Score")

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
	describe("体験スコア（D-301）", function()
		it("D-301 スコアの表の指標はすべて体験の指標として計算できる", function()
			for _, m in Score.metrics(Data.ExperienceScores) do
				expect(table.find(Metrics.EXPERIENCE, m) ~= nil).toBe(true)
			end
		end)
		it(
			"D-301 良い線で100点・悪い線で0点・その間は直線（小さいほど良い指標も）",
			function()
				expect(Score.item(60, 60, 180)).toBe(100)
				expect(Score.item(180, 60, 180)).toBe(0)
				expect(Score.item(120, 60, 180)).toBe(50)
				expect(Score.item(30, 60, 180)).toBe(100)
				expect(Score.item(0.4, 0.6, 0.2)).toBeCloseTo(50, 1e-9)
				expect(Score.item(nil, 1, 0)).toBe(nil)
			end
		)
		it("D-301 分類は指標の平均、総合は分類の重みつき平均", function()
			local es = {
				categories = {
					{
						id = "a",
						weight = 1,
						items = { { metric = "x", good = 10, bad = 0 }, { metric = "y", good = 10, bad = 0 } },
					},
					{ id = "b", weight = 3, items = { { metric = "z", good = 10, bad = 0 } } },
				},
			}
			local s = Score.profile(es, { x = 10, y = 0, z = 10 })
			expect(s.categories.a).toBe(50)
			expect(s.categories.b).toBe(100)
			expect(s.total).toBe(87.5)
		end)
		it("D-301 スコアの表の検証：good と bad が同じ・未知の型は失敗", function()
			local d = clone(Data)
			d.ExperienceScores.profiles = { "casual" }
			d.ExperienceScores.categories[1].items[1].bad = d.ExperienceScores.categories[1].items[1].good
			local paths = {}
			for _, e in MasterData.validate(d) do
				if e.level == "error" then
					paths[e.path] = true
				end
			end
			expect(paths["ExperienceScores.profiles[1]"]).toBe(true)
			expect(paths["ExperienceScores.categories[1].items[1]"]).toBe(true)
		end)
		it(
			"D-301 出来事の数え方：留守の出来事は次のログインに数え、初めてのレアリティは節目",
			function()
				local c = Experience.new()
				local on = Experience.collector(c)
				on({ type = "Login", at = 0 }, true)
				on({ type = "ChestsOpened", at = 30, opened = 1, normal = { { rank = 1 } }, special = {} }, true)
				on({ type = "LevelUp", at = 40 }, true)
				on({ type = "Logout", at = 100 }, true)
				on({ type = "DungeonUnlocked", at = 500, dungeonId = "dng_ruins" }, false)
				on({ type = "Login", at = 1000 }, true)
				on({ type = "Logout", at = 1100 }, true)
				expect(#c.sessions[1].moments).toBe(2)
				expect(c.sessions[1].moments[1].kind).toBe("big")
				expect(#c.sessions[2].moments).toBe(1)
				expect(c.sessions[2].moments[1].at).toBe(1000)
				expect(c.seen["dungeon:dng_ruins"]).toBe(true)
				local m = Experience.finish(c, 1100, 10)
				expect(m.sessionsWithBigShare).toBe(1)
				expect(m.firstChestSec).toBe(30)
			end
		)
	end)
	describe("揺れの扱い（MX）", function()
		it("D-291 seed の順の値と標準誤差を残す（出なかった seed は false）", function()
			local a = Judge.aggregate({ 10, false, 14 }, 3)
			expect(a.mean).toBe(12)
			expect(a.missing).toBe(1)
			expect(a.values[2]).toBe(false)
			expect(a.se).toBeCloseTo(2, 1e-9)
		end)
		it("D-295 標準誤差を合わせた幅の2倍以内の差は揺れの範囲", function()
			expect(Judge.withinNoise(10, 11, 0.5, 0.5)).toBe(true)
			expect(Judge.withinNoise(10, 13, 0.5, 0.5)).toBe(false)
			expect(Judge.withinNoise(10, 11, nil, nil)).toBe(false)
		end)
		it("D-295 揺れの範囲の差は基準の警告にしない", function()
			local t = { id = "bal_x", name = "x", decision = "D-295", metric = "milestoneDays", judge = "baseline" }
			local now = Judge.aggregate({ { a = 10 }, { a = 14 } }, 2)
			local base = { a = { mean = 8, se = 2 } }
			expect(Judge.judge(t, "core", now, base, nil).status).toBe("pass")
		end)
		it("D-301 seed ごとの点数から分類と総合の標準誤差を出す", function()
			local es = { categories = { { id = "a", weight = 1, items = { { metric = "x", good = 10, bad = 0 } } } } }
			local perSeed = { Score.profile(es, { x = 4 }), Score.profile(es, { x = 6 }) }
			local n = Score.noise(es, perSeed)
			expect(n.categories.a).toBeCloseTo(10, 1e-9)
			expect(n.total).toBeCloseTo(10, 1e-9)
		end)
	end)
end
