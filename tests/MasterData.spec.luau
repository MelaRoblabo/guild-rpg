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
			table.insert(d.Rarities, { id = "rar_test", rank = #d.Rarities + 1, name = "テスト", nameEn = "Test" })
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
		it("D-231 ⑥ 英語名が欠けている・日本語のままだと失敗", function()
			local d = clone(Data)
			d.Jobs[1].nameEn = nil
			d.Names.m[1] = "アルド"
			local errs = errorsOf(d)
			local paths = {}
			for _, e in errs do
				paths[e.path] = true
			end
			expect(paths["Jobs[1].nameEn"]).toBe(true)
			expect(paths["Names.m[1]"]).toBe(true)
		end)
		it(
			"D-042 見た目の画像は rbxassetid://<数字> の形でなければ失敗（無いのはよい）",
			function()
				local d = clone(Data)
				d.Appearances[1].imageId = "87081995123632"
				d.Appearances[2].imageId = nil
				local paths = {}
				for _, e in errorsOf(d) do
					paths[e.path] = true
				end
				expect(paths["Appearances[1].imageId"]).toBe(true)
				expect(paths["Appearances[2].imageId"]).toBe(nil)
			end
		)
		it(
			"D-291 バランスの目標の表：決定ID・判定の仕方・型・配分の列が正しくなければ失敗",
			function()
				local d = clone(Data)
				local rows = d.BalanceTargets.targets
				rows[1].decision = "なし"
				rows[2].judge = "maybe"
				rows[3].profiles = { "casual" }
				local share
				for _, r in rows do
					if r.judge == "share" then
						share = r
						break
					end
				end
				share.columns.shop = 10
				local paths = {}
				for _, e in errorsOf(d) do
					paths[e.path] = true
				end
				expect(paths["BalanceTargets.targets[1].decision"]).toBe(true)
				expect(paths["BalanceTargets.targets[2].judge"]).toBe(true)
				expect(paths["BalanceTargets.targets[3].profiles[1]"]).toBe(true)
			end
		)
		it(
			"D-291 バランスの目標の表：near に幅がない・存在しないダンジョンを指すと失敗",
			function()
				local d = clone(Data)
				for _, r in d.BalanceTargets.targets do
					if r.id == "bal_days_to_max_growth" then
						r.tol = nil
					elseif r.id == "bal_stage_clear" then
						r.byDungeon.dng_none = 0.5
					end
				end
				local msgs = {}
				for _, e in errorsOf(d) do
					table.insert(msgs, e.path .. " " .. e.message)
				end
				local all = table.concat(msgs, "\n")
				expect(string.find(all, "tol", 1, true) ~= nil).toBe(true)
				expect(string.find(all, "dng_none", 1, true) ~= nil).toBe(true)
			end
		)
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
