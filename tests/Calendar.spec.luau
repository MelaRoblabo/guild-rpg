--!strict
-- 日・週の番号（D-168、06章 §11）
local Calendar = require("../src/core/Calendar")

local T0 = 1767225600 -- 2026-01-01（木）00:00 UTC ＝ 日本の朝9時
local DAY = 86400
local MONDAY = T0 + 4 * DAY -- 2026-01-05（月）00:00 UTC

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("日・週の区切り（D-168）", function()
		it("D-168 日の番号は UTC 0時で切り替わる（日をまたぐ瞬間）", function()
			expect(Calendar.dayIndex(T0)).toBe(T0 // DAY)
			expect(Calendar.dayIndex(T0 - 1)).toBe(Calendar.dayIndex(T0) - 1)
			expect(Calendar.dayIndex(T0 + DAY - 1)).toBe(Calendar.dayIndex(T0))
			expect(Calendar.dayIndex(T0 + DAY)).toBe(Calendar.dayIndex(T0) + 1)
		end)
		it("D-168 日本時間では朝9時が日の区切り", function()
			-- T0 は日本時間 2026-01-01 09:00:00。08:59:59 は前の日、翌朝 08:59:59 まで同じ日
			local JST_9AM = T0
			expect(Calendar.dayIndex(JST_9AM - 1)).toBe(Calendar.dayIndex(JST_9AM) - 1)
			expect(Calendar.dayIndex(JST_9AM + DAY - 1)).toBe(Calendar.dayIndex(JST_9AM))
		end)
		it("D-168 週の番号は月曜の UTC 0時で切り替わる（日曜→月曜）", function()
			local w = Calendar.weekIndex(MONDAY)
			expect(Calendar.weekIndex(MONDAY - 1)).toBe(w - 1) -- 日曜 23:59:59
			expect(Calendar.weekIndex(MONDAY + 7 * DAY - 1)).toBe(w) -- 次の日曜 23:59:59 まで同じ週
			expect(Calendar.weekIndex(MONDAY + 7 * DAY)).toBe(w + 1)
			-- 木〜日は同じ週、その前の月曜から同じ週
			expect(Calendar.weekIndex(T0)).toBe(w - 1)
			expect(Calendar.weekIndex(T0 - 3 * DAY)).toBe(w - 1)
			expect(Calendar.weekIndex(T0 - 3 * DAY - 1)).toBe(w - 2)
		end)
		it("D-168 式どおり：weekIndex = floor((dayIndex + 3) / 7)", function()
			expect(Calendar.weekIndex(0)).toBe(0) -- 1970-01-01（木）
			expect(Calendar.weekIndex(4 * DAY - 1)).toBe(0) -- 1970-01-04（日）
			expect(Calendar.weekIndex(4 * DAY)).toBe(1) -- 1970-01-05（月）
			for d = 0, 30 do
				local now = T0 + d * DAY + 12345
				expect(Calendar.weekIndex(now)).toBe((Calendar.dayIndex(now) + 3) // 7)
			end
		end)
		it("D-168 次の日の区切りの時刻", function()
			expect(Calendar.nextDayStart(T0)).toBe(T0 + DAY)
			expect(Calendar.nextDayStart(T0 + DAY - 1)).toBe(T0 + DAY)
			expect(Calendar.nextDayStart(T0 - 1)).toBe(T0)
		end)
	end)
end
