--!strict
-- 画面の通知の仕組み（src/client/ui/Signal。D-227 ①）
local Signal = require("../src/client/ui/Signal")

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("D-227 Signal", function()
		it("D-227 つないだ順に呼ぶ", function()
			local s = Signal.new()
			local got = {}
			s:connect(function(v)
				table.insert(got, "a" .. v)
			end)
			s:connect(function(v)
				table.insert(got, "b" .. v)
			end)
			s:fire(1)
			expect(table.concat(got, ",")).toBe("a1,b1")
		end)
		it(
			"D-227 通知の途中で外された受け手は呼ばない（閉じた画面を描かない）",
			function()
				local s = Signal.new()
				local got = {}
				local second
				s:connect(function()
					table.insert(got, "a")
					second.disconnect()
				end)
				second = s:connect(function()
					table.insert(got, "b")
				end)
				s:fire()
				expect(table.concat(got, ",")).toBe("a")
			end
		)
		it("D-227 1つの受け手のエラーで、残りの受け手と送り手を止めない", function()
			local s = Signal.new()
			local got = {}
			s:connect(function()
				error("boom")
			end)
			s:connect(function()
				table.insert(got, "b")
			end)
			local ok = pcall(function()
				s:fire()
			end)
			expect(ok).toBe(true)
			expect(table.concat(got, ",")).toBe("b")
		end)
	end)
end
