--!strict
local Formulas = require("../src/core/Formulas")
local Fixtures = require("./helpers/Fixtures")

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local K = master.K

	describe("ダメージ", function()
		it("D-007 攻撃力−防御", function()
			expect(Formulas.damage(30, 10, K)).toBe(20)
		end)
		it("D-007 最低ダメージは攻撃力の10%", function()
			expect(Formulas.damage(50, 100, K)).toBe(5)
		end)
		it("D-007 最低ダメージは1", function()
			expect(Formulas.damage(3, 100, K)).toBe(1)
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
		it("D-033 個体補正：頑健で最大HP+10%", function()
			expect(Formulas.memberSnapshot(def("job_warrior", { "gift_sturdy" }), master).maxHp).toBe(55)
		end)
		it("D-033 個体補正は1性能あたり+30%まで", function()
			local m = Fixtures.master(function(d)
				for _, g in d.Gifts do
					if g.id == "gift_swift" then
						g.effect.value = 0.5
					end
				end
			end)
			local s = Formulas.memberSnapshot(def("job_warrior", { "gift_swift" }), m)
			expect(s.agi).toBe(13)
		end)
		it("D-023 退魔の才：アンデッドへの攻撃力+10%", function()
			local s = Formulas.memberSnapshot(def("job_warrior", { "gift_exorcist" }), master)
			expect(Formulas.attackAgainst(s, "undead")).toBe(22)
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
		it("D-017 罠ダメージは罠Lvで増える", function()
			expect(Formulas.trapDamage(100, 1, K)).toBe(15)
			expect(Formulas.trapDamage(100, 3, K)).toBe(math.floor(100 * 0.15 * 1.5))
		end)
		it("D-018 泉は最大HPの25%", function()
			expect(Formulas.fountainHeal(100, K)).toBe(25)
		end)
		it("D-015 宝箱ランクは5で止まる", function()
			expect(Formulas.chestRank(4, 3)).toBe(5)
			expect(Formulas.chestRank(1, 2)).toBe(3)
		end)
		it("Q-004 幸運の発動率は所持者数×15%、上限40%", function()
			expect(Formulas.luckyChance(1, K)).toBeCloseTo(0.15)
			expect(Formulas.luckyChance(4, K)).toBeCloseTo(0.40)
		end)
		it("D-021 俊敏が高いほど移動が速い", function()
			local d = master.dungeons.dng_graveyard
			local slow = Formulas.travelSeconds({ Fixtures.snap({ agi = 0 }) }, d, K)
			local fast = Formulas.travelSeconds({ Fixtures.snap({ agi = 50 }) }, d, K)
			expect(slow).toBe(30)
			expect(fast).toBe(15)
		end)
		it("D-021 道案内は対象地形で移動時間×0.8（重複しない）", function()
			local d = master.dungeons.dng_graveyard -- outdoor
			local guide = { terrainTag = "outdoor", value = 0.8, giftId = "gift_guide" }
			local sec, giftId = Formulas.travelSeconds({
				Fixtures.snap({ agi = 0, travel = { guide } }),
				Fixtures.snap({ agi = 0, travel = { guide } }),
			}, d, K)
			expect(sec).toBe(24)
			expect(giftId).toBe("gift_guide")
			local tower = master.dungeons.dng_tower -- indoor
			local sec2 = Formulas.travelSeconds({ Fixtures.snap({ agi = 0, travel = { guide } }) }, tower, K)
			expect(sec2).toBe(70)
		end)
	end)
end
