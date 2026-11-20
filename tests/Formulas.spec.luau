--!strict
local Formulas = require("../src/core/Formulas")
local Fixtures = require("./helpers/Fixtures")

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local K = master.K

	describe("ダメージ", function()
		it("D-068 ダメージ＝攻撃力²÷(攻撃力＋防御)", function()
			expect(Formulas.damage(30, 10, K)).toBe(22)
		end)
		it("D-068 防御が攻撃力と同じなら半分", function()
			expect(Formulas.damage(50, 50, K)).toBe(25)
		end)
		it("D-068 防御0なら攻撃力そのまま、最低1", function()
			expect(Formulas.damage(40, 0, K)).toBe(40)
			expect(Formulas.damage(1, 1000, K)).toBe(1)
			expect(Formulas.damage(0, 0, K)).toBe(1)
		end)
		it("D-010 クリティカル率＝技巧/(技巧+200)", function()
			expect(Formulas.critRate(50, K)).toBeCloseTo(0.2)
		end)
		it("D-010 クリティカル率の上限30%", function()
			expect(Formulas.critRate(10000, K)).toBe(0.30)
		end)
		it("D-010 クリティカルは1.5倍（切り捨て）", function()
			expect(Formulas.critDamage(15, K)).toBe(22)
		end)
	end)

	describe("モンスター", function()
		it("D-003 戦闘フロアごとに+20%", function()
			expect(Formulas.monsterScale(1, K)).toBeCloseTo(1.0)
			expect(Formulas.monsterScale(2, K)).toBeCloseTo(1.2)
			expect(Formulas.monsterScale(3, K)).toBeCloseTo(1.4)
		end)
		it("D-003 パラメータと戦闘報酬に倍率を掛ける", function()
			local d = master.dungeons.dng_graveyard
			local s = Formulas.monsterStats(d, 3, K)
			expect(s.hp).toBe(math.floor(d.base.hp * 1.4))
			expect(s.gold).toBe(math.floor(d.battleReward.gold * 1.4))
		end)
	end)

	describe("メンバーの実効値", function()
		local function def(jobId: string, gifts: { string }?, equipment: any?)
			return {
				uid = "a",
				slot = 1,
				jobId = jobId,
				baseStats = { str = 20, mag = 30, agi = 10, dex = 10, hp = 50 },
				giftIds = gifts or {},
				equipment = equipment or {},
			}
		end

		it("D-037 物理攻撃職は腕力、魔法攻撃職は魔力", function()
			expect(Formulas.memberSnapshot(def("job_warrior"), master).atk).toBe(20)
			expect(Formulas.memberSnapshot(def("job_mage"), master).atk).toBe(30)
			expect(Formulas.memberSnapshot(def("job_priest"), master).atk).toBe(30)
			expect(Formulas.memberSnapshot(def("job_thief"), master).atk).toBe(20)
		end)
		it("D-047 攻撃力＝能力＋武器補正（ダンジョン補正なし）", function()
			local s = Formulas.memberSnapshot(
				def("job_warrior", nil, { weapon = { baseId = "eq_wpn_sword", rarity = 1, grade = 0 } }),
				master
			)
			expect(s.atk).toBe(26)
		end)
		it("Q-020 装備性能＝基本値×レアリティ係数×(1+0.1×グレード)", function()
			local s = Formulas.memberSnapshot(
				def("job_warrior", nil, { armor = { baseId = "eq_arm_chainmail", rarity = 3, grade = 2 } }),
				master
			)
			expect(s.pdef).toBe(math.floor(6 * 1.7 * 1.2))
		end)
		it("D-008 防具が物理防御・魔法防御を持つ", function()
			local s = Formulas.memberSnapshot(
				def("job_mage", nil, { armor = { baseId = "eq_arm_robe", rarity = 1, grade = 0 } }),
				master
			)
			expect(s.pdef).toBe(1)
			expect(s.mdef).toBe(5)
		end)
		it("D-070 個体補正：頑健で最大HP+25%", function()
			expect(Formulas.memberSnapshot(def("job_warrior", { "gift_sturdy" }), master).maxHp).toBe(62)
		end)
		it("D-070 個体補正は1性能あたり+50%まで", function()
			local m = Fixtures.master(function(d)
				for _, g in d.Gifts do
					if g.id == "gift_swift" then
						g.effect.value = 0.9
					end
				end
			end)
			local s = Formulas.memberSnapshot(def("job_warrior", { "gift_swift" }), m)
			expect(s.agi).toBe(15)
		end)
		it("D-070 退魔の才：アンデッドへの攻撃力+30%", function()
			local s = Formulas.memberSnapshot(def("job_warrior", { "gift_exorcist" }), master)
			expect(Formulas.attackAgainst(s, "undead")).toBe(26)
			expect(Formulas.attackAgainst(s, "beast")).toBe(20)
		end)
		it("D-060 癒しの：回復量が上がる", function()
			local s = Formulas.memberSnapshot(
				def("job_priest", nil, {
					weapon = {
						baseId = "eq_wpn_mace",
						rarity = 1,
						grade = 0,
						modifierId = "mod_healing",
						modifierValue = 0.1,
					},
				}),
				master
			)
			expect(Formulas.healAmount(s, K)).toBe(math.floor(30 * 0.3 * 1.1))
		end)
	end)

	describe("イベント・移動", function()
		it("D-017 罠の回避率＝技巧合計/(技巧合計＋罠Lv×K)", function()
			expect(Formulas.trapEvadeRate(30, 3, K)).toBeCloseTo(30 / (30 + 3 * K.trapK))
		end)
		it("D-067 罠ダメージは最大HP×20%（ダンジョンごとに上書き可）", function()
			expect(Formulas.trapDamage(100, { trapDamageRate = nil }, K)).toBe(20)
			expect(Formulas.trapDamage(100, { trapDamageRate = 0.3 }, K)).toBe(30)
		end)
		it("D-018 泉は最大HPの25%", function()
			expect(Formulas.fountainHeal(100, K)).toBe(25)
		end)
		it("D-015 宝箱ランクは5で止まる", function()
			expect(Formulas.chestRank(4, 3)).toBe(5)
			expect(Formulas.chestRank(1, 2)).toBe(3)
		end)
		it("D-070 幸運の発動率は所持者数×30%、上限60%", function()
			expect(Formulas.luckyChance(1, K)).toBeCloseTo(0.30)
			expect(Formulas.luckyChance(4, K)).toBeCloseTo(0.60)
		end)
		it("D-069 片道秒＝距離×10×clamp(基準俊敏÷平均俊敏, 0.6, 1.4)", function()
			local d = master.dungeons.dng_graveyard
			local slow = Formulas.travelSeconds({ Fixtures.snap({ agi = 1 }) }, d, K)
			local same = Formulas.travelSeconds({ Fixtures.snap({ agi = d.refAgi }) }, d, K)
			local fast = Formulas.travelSeconds({ Fixtures.snap({ agi = 100000 }) }, d, K)
			expect(slow).toBe(math.ceil(d.distance * 10 * 1.4))
			expect(same).toBe(math.ceil(d.distance * 10))
			expect(fast).toBe(math.ceil(d.distance * 10 * 0.6))
		end)
		it("D-070 道案内は対象地形で移動時間×0.7（重複しない）", function()
			local d = master.dungeons.dng_graveyard -- outdoor
			local guide = { terrainTag = "outdoor", value = 0.7, giftId = "gift_guide" }
			local sec, giftId = Formulas.travelSeconds({
				Fixtures.snap({ agi = d.refAgi, travel = { guide } }),
				Fixtures.snap({ agi = d.refAgi, travel = { guide } }),
			}, d, K)
			expect(sec).toBe(math.ceil(d.distance * 10 * 0.7))
			expect(giftId).toBe("gift_guide")
			local tower = master.dungeons.dng_tower -- indoor
			local sec2 = Formulas.travelSeconds({ Fixtures.snap({ agi = tower.refAgi, travel = { guide } }) }, tower, K)
			expect(sec2).toBe(math.ceil(tower.distance * 10))
		end)
		it("D-069 装備はアイテムレベルが1上がるごとに1.3倍", function()
			expect(Formulas.equipMult(1, 0, 3, K)).toBeCloseTo(1.69)
		end)
	end)
end
