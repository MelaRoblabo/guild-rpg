--!strict
-- 他のプレイヤーの馬車の位置とまとめ方（D-026・D-127・D-213 ⑮）
local OtherCarts = require("../src/client/world/OtherCarts")

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("D-026 他のプレイヤーの馬車の位置（OtherCarts.position）", function()
		local p = { departAt = 1000, travelSeconds = 100, totalSeconds = 500 }
		it("行き・ダンジョンの中・帰りを、出発時刻と時間だけで求める", function()
			local a = OtherCarts.position(p, 1050) :: any
			expect(a.state).toBe("moving")
			expect(a.along).toBe(0.5)
			local b = OtherCarts.position(p, 1200) :: any
			expect(b.state).toBe("exploring")
			expect(b.along).toBe(1)
			local c = OtherCarts.position(p, 1450) :: any
			expect(c.state).toBe("returning")
			expect(c.along).toBe(0.5)
		end)
		it("帰ったら nil（馬車を消す）", function()
			expect(OtherCarts.position(p, 1500)).toBe(nil)
		end)
	end)

	describe("D-127 重なる他人の馬車は「＋N」にまとめる（OtherCarts.cluster）", function()
		it("半径の中はまとめ、離れていれば別にする", function()
			local g = OtherCarts.cluster({
				{ x = 0, y = 0, key = "a" },
				{ x = 10, y = 5, key = "b" },
				{ x = 300, y = 0, key = "c" },
				{ x = 2, y = 2, key = "d" },
			}, 30)
			expect(#g).toBe(2)
			expect(#g[1].keys).toBe(3)
			expect(g[1].keys[2]).toBe("b")
			expect(g[2].keys[1]).toBe("c")
		end)
	end)
end
