--!strict
local MasterData = require("../src/core/MasterData")
local Data = require("../src/data")

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

local function errorsOf(data: any): { any }
	local out = {}
	for _, i in MasterData.validate(data) do
		if i.level == "error" then
			table.insert(out, i)
		end
	end
	return out
end

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("本番データ", function()
		it("検証を通る", function()
			local errs = errorsOf(clone(Data))
			if #errs > 0 then
				error(MasterData.formatIssues(errs))
			end
		end)
		it("load できる", function()
			expect(MasterData.load(clone(Data))).toBeTruthy()
		end)
	end)

	describe("壊れたデータで起動しない（04章 §2）", function()
		it("D-014 イベント確率の合計が1でなければ失敗", function()
			local d = clone(Data)
			d.Constants.eventWeights[1].weight = 0.5
			expect(function()
				MasterData.load(d)
			end).toThrow("Constants.eventWeights")
		end)
		it("D-005 被弾率が4要素でなければ失敗", function()
			local d = clone(Data)
			table.remove(d.Constants.hitWeights)
			expect(function()
				MasterData.load(d)
			end).toThrow("Constants.hitWeights")
		end)
		it("確率の表に辞書を使うと失敗", function()
			local d = clone(Data)
			d.Constants.eventWeights = { chest = { weight = 1 } }
			expect(function()
				MasterData.load(d)
			end).toThrow("辞書は使わない")
		end)
		it("負の重みで失敗", function()
			local d = clone(Data)
			d.Constants.eventWeights[2].weight = -0.1
			expect(#errorsOf(d) > 0).toBeTruthy()
		end)
		it("D-085 宝箱の出現率の表がレアリティの数より長いと失敗", function()
			local d = clone(Data)
			d.Dungeons[1].chestRarityWeights = { 1, 1, 1, 1, 1, 1, 1 }
			expect(#errorsOf(d) > 0).toBeTruthy()
		end)
		it("D-085 レアリティを増やしたら倍率の表も伸ばす必要がある", function()
			local d = clone(Data)
			table.insert(d.Rarities, { id = "rar_test", rank = #d.Rarities + 1, name = "テスト" })
			expect(#errorsOf(d) > 0).toBeTruthy()
			table.insert(d.Constants.equipRarityMult, 5)
			table.insert(d.Constants.sellRarityMult, 20)
			expect(#errorsOf(d)).toBe(0)
		end)
		it("D-090 演出が入る割合が基準（10〜15%）から外れると失敗", function()
			local d = clone(Data)
			d.Dungeons[1].chestEffectMinRarity = 1 -- 全部演出になる
			expect(function()
				MasterData.load(d)
			end).toThrow("演出が入る割合")
		end)
		it("D-024 ギフト追加回数が上限を超えると失敗", function()
			local d = clone(Data)
			d.Constants.giftMax = 3
			expect(function()
				MasterData.load(d)
			end).toThrow("giftMax")
		end)
		it("Q-006 雇用の範囲で min > max なら失敗", function()
			local d = clone(Data)
			d.Constants.hireStatRange.str.min = d.Constants.hireStatRange.str.max + 1
			expect(function()
				MasterData.load(d)
			end).toThrow("hireStatRange.str")
		end)
		it("必須の定数が欠けると失敗", function()
			local d = clone(Data)
			d.Constants.maxTurns = nil
			expect(function()
				MasterData.load(d)
			end).toThrow("Constants.maxTurns")
		end)
	end)

	describe("検証の補助", function()
		it("id の重複と接頭辞を検出する", function()
			local c = MasterData._newChecker()
			c:uniqueIds("Jobs", { { id = "job_a" }, { id = "job_a" }, { id = "x_b" } }, "job_")
			expect(#c.issues).toBe(2)
		end)
		it("存在しない参照を検出する", function()
			local c = MasterData._newChecker()
			c:ref("Dungeons[1].monster", "mon_none", { mon_a = true })
			expect(#c.issues).toBe(1)
		end)
	end)
end
