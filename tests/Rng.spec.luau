--!strict
local Rng = require("../src/core/Rng")

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("固定値（08章：Roblox上でも同じ値になること）", function()
		-- Python の独立した参照実装で算出した値
		it("seed=1 の先頭5個", function()
			local r = Rng.new(1)
			expect({ r:nextU32(), r:nextU32(), r:nextU32(), r:nextU32(), r:nextU32() }).toEqual({
				2442144158,
				3238099751,
				3819917871,
				2104621829,
				2021136066,
			})
		end)
		it("seed=12345 の先頭5個", function()
			local r = Rng.new(12345)
			expect({ r:nextU32(), r:nextU32(), r:nextU32(), r:nextU32(), r:nextU32() }).toEqual({
				518667457,
				440444462,
				4232892992,
				3757857622,
				3939018813,
			})
		end)
		it("seed=2^32-1 の先頭5個", function()
			local r = Rng.new(4294967295)
			expect({ r:nextU32(), r:nextU32(), r:nextU32(), r:nextU32(), r:nextU32() }).toEqual({
				835879718,
				1921286648,
				2356205009,
				1885780724,
				980451116,
			})
		end)
		it("derive の固定値", function()
			expect(Rng.derive(12345, 0)).toBe(1517774591)
			expect(Rng.derive(12345, 1)).toBe(430482993)
			expect(Rng.derive(0, 7)).toBe(687500557)
		end)
	end)

	describe("性質", function()
		it("同じシードなら同じ列（D-026 結果の再現性）", function()
			local a, b = Rng.new(777), Rng.new(777)
			for _ = 1, 1000 do
				expect(a:nextU32()).toBe(b:nextU32())
			end
		end)
		it("mul32 は 2^32 を法とする積と一致", function()
			expect(Rng._mul32(0xFFFFFFFF, 0xFFFFFFFF)).toBe(1)
			expect(Rng._mul32(0x12345678, 0x9ABCDEF0)).toBe(0x242D2080)
			expect(Rng._mul32(65536, 65536)).toBe(0)
		end)
		it("float は [0,1)", function()
			local r = Rng.new(5)
			for _ = 1, 10000 do
				local f = r:float()
				expect(f >= 0 and f < 1).toBeTruthy()
			end
		end)
		it("int は両端を含み、範囲外を出さない", function()
			local r = Rng.new(9)
			local seenMin, seenMax = false, false
			for _ = 1, 5000 do
				local v = r:int(3, 6)
				expect(v).toBeBetween(3, 6)
				seenMin = seenMin or v == 3
				seenMax = seenMax or v == 6
			end
			expect(seenMin and seenMax).toBeTruthy()
		end)
		it("chance(0) は偽、chance(1) は真", function()
			local r = Rng.new(1)
			expect(r:chance(0)).toBeFalsy()
			expect(r:chance(1)).toBeTruthy()
		end)
		it("統計: pickWeighted が重みに近い（10万回、誤差±1%）", function()
			local r = Rng.new(2024)
			local entries = { { id = "a", weight = 0.6 }, { id = "b", weight = 0.3 }, { id = "c", weight = 0.1 } }
			local counts = { a = 0, b = 0, c = 0 }
			local n = 100000
			for _ = 1, n do
				local e = r:pickWeighted(entries, function(x)
					return x.weight
				end)
				counts[e.id] += 1
			end
			expect(counts.a / n).toBeCloseTo(0.6, 0.01)
			expect(counts.b / n).toBeCloseTo(0.3, 0.01)
			expect(counts.c / n).toBeCloseTo(0.1, 0.01)
		end)
	end)
end
