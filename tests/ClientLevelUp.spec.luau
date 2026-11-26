--!strict
-- レベルが上がった冒険者の印（D-246 ④）
local LevelUpMarks = require("../src/client/hub/LevelUpMarks")

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local LIT = LevelUpMarks.LIT_SECONDS

	describe("D-246 ④ パーティの面で上がった人の Lv を一度光らせる", function()
		it("上がっていない人は光らない", function()
			LevelUpMarks.clear()
			expect(LevelUpMarks.lit("adv_1", 100)).toBe(false)
		end)
		it("初めて見たときから決まった間だけ光り、その後は消える", function()
			LevelUpMarks.clear()
			LevelUpMarks.note("adv_1")
			expect(LevelUpMarks.lit("adv_1", 100)).toBe(true)
			expect(LevelUpMarks.lit("adv_1", 100 + LIT / 2)).toBe(true) -- 面を作り直しても続く
			expect(LevelUpMarks.lit("adv_1", 100 + LIT)).toBe(false)
			expect(LevelUpMarks.lit("adv_1", 200)).toBe(false) -- 一度きり
		end)
		it("見るまでは待つ（帰還からしばらく経って面を開いても光る）", function()
			LevelUpMarks.clear()
			LevelUpMarks.note("adv_2")
			expect(LevelUpMarks.lit("adv_2", 5000)).toBe(true)
		end)
		it("もう一度上がれば、また光る", function()
			LevelUpMarks.clear()
			LevelUpMarks.note("adv_3")
			LevelUpMarks.lit("adv_3", 10)
			LevelUpMarks.lit("adv_3", 10 + LIT)
			LevelUpMarks.note("adv_3")
			expect(LevelUpMarks.lit("adv_3", 50)).toBe(true)
		end)
	end)
	describe("D-269 ③ Adventurers のボタンの ▲ の札", function()
		it(
			"上がった人がいれば、一覧を開くまで残る（パーティの面で光り終わっても）",
			function()
				LevelUpMarks.clear()
				expect(LevelUpMarks.anyUnseen()).toBe(false)
				LevelUpMarks.note("adv_4")
				LevelUpMarks.lit("adv_4", 10)
				LevelUpMarks.lit("adv_4", 10 + LIT)
				expect(LevelUpMarks.anyUnseen()).toBe(true)
				LevelUpMarks.seenAll()
				expect(LevelUpMarks.anyUnseen()).toBe(false)
			end
		)
	end)
end
