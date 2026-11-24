--!strict
-- クエストの画面の見せ方（D-233）
local Calendar = require("../src/core/Calendar")
local QuestView = require("../src/client/quest/QuestView")
local Fixtures = require("./helpers/Fixtures")

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local deps = { nextDayStart = Calendar.nextDayStart, nextWeekStart = Calendar.nextWeekStart }

	describe("D-233 ② 区切りまでの残り時間", function()
		it("Daily は時間、Weekly は日、1時間を切ったら分", function()
			local dayStart = Calendar.dayStart(1_800_000_000)
			local now = dayStart + 10 * 3600 -- 区切りまで14時間
			expect(QuestView.left("daily", now, deps)).toBe("14h")
			expect(QuestView.left("daily", dayStart + 86400 - 600, deps)).toBe("10m")
			local w = QuestView.left("weekly", now, deps)
			expect(string.sub(w, -1) == "d" or string.sub(w, -1) == "h").toBe(true)
		end)
	end)

	describe("D-233 ④ 行の報酬の札", function()
		it("宝箱があれば宝箱の数（デイリーは60）", function()
			local row = master.quests["qst_daily_expeditions"]
			local r = QuestView.mainReward(row.rewards)
			expect(r ~= nil and r.kind == "chest").toBe(true)
			expect((r :: any).n).toBe(60)
		end)
	end)
end
