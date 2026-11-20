--!strict
local Combat = require("../src/core/Combat")
local Rng = require("../src/core/Rng")
local Fixtures = require("./helpers/Fixtures")

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local K = Fixtures.master().K
	local M = Fixtures.memberState

	describe("行動順と被弾", function()
		it("D-004 俊敏の降順、同値は隊列順", function()
			local members = {
				M({ slot = 1, agi = 5 }),
				M({ slot = 2, agi = 9 }),
				M({ slot = 3, agi = 9 }),
				M({ slot = 4, agi = 1 }),
			}
			local order = {}
			for _, m in Combat.actionOrder(members) do
				table.insert(order, m.slot)
			end
			expect(order).toEqual({ 2, 3, 1, 4 })
		end)
		it("D-004 戦闘不能者は行動しない", function()
			local members = { M({ slot = 1 }, 0), M({ slot = 2 }) }
			expect(#Combat.actionOrder(members)).toBe(1)
		end)
		it("D-005 統計: 被弾率 45/25/20/10%（10万回、誤差±1%）", function()
			local members = { M({ slot = 1 }), M({ slot = 2 }), M({ slot = 3 }), M({ slot = 4 }) }
			local rng = Rng.new(3)
			local counts = { 0, 0, 0, 0 }
			local n = 100000
			for _ = 1, n do
				local m = Combat.pickTarget(members, rng, K)
				counts[m.slot] += 1
			end
			expect(counts[1] / n).toBeCloseTo(0.45, 0.01)
			expect(counts[2] / n).toBeCloseTo(0.25, 0.01)
			expect(counts[3] / n).toBeCloseTo(0.20, 0.01)
			expect(counts[4] / n).toBeCloseTo(0.10, 0.01)
		end)
		it("D-005 統計: 戦闘不能者を除いて按分する（隊列1が倒れたら 25:20:10）", function()
			local members = { M({ slot = 1 }, 0), M({ slot = 2 }), M({ slot = 3 }), M({ slot = 4 }) }
			local rng = Rng.new(4)
			local counts = { 0, 0, 0, 0 }
			local n = 100000
			for _ = 1, n do
				counts[Combat.pickTarget(members, rng, K).slot] += 1
			end
			expect(counts[1]).toBe(0)
			expect(counts[2] / n).toBeCloseTo(25 / 55, 0.01)
			expect(counts[4] / n).toBeCloseTo(10 / 55, 0.01)
		end)
	end)

	describe("戦闘の結果", function()
		it("D-002 モンスターを倒せば勝利", function()
			local r = Combat.run({ M({ atk = 200 }) }, Fixtures.monster({ hp = 100 }), Rng.new(1), K)
			expect(r.outcome).toBe("win")
			expect(#r.turns).toBe(1)
		end)
		it("D-004 味方全員が先に行動し、倒せばモンスターは攻撃しない", function()
			local r = Combat.run(
				{ M({ atk = 60 }), M({ slot = 2, atk = 60 }) },
				Fixtures.monster({ hp = 100 }),
				Rng.new(1),
				K
			)
			expect(r.outcome).toBe("win")
			expect(r.turns[1].monster).toBe(nil)
		end)
		it("D-002 全滅で wipe", function()
			local members = { M({ atk = 1, maxHp = 5 }) }
			local r = Combat.run(members, Fixtures.monster({ hp = 10000, atk = 100 }), Rng.new(1), K)
			expect(r.outcome).toBe("wipe")
			expect(members[1].hp).toBe(0)
		end)
		it("D-009 30ターンで打ち切り（timeout）", function()
			local r = Combat.run(
				{ M({ atk = 1, maxHp = 100000 }) },
				Fixtures.monster({ hp = 100000, atk = 1, pdef = 100 }),
				Rng.new(1),
				K
			)
			expect(r.outcome).toBe("timeout")
			expect(#r.turns).toBe(30)
		end)
		it("D-008 モンスターの攻撃種別に対応する防御を引く", function()
			local phys = { M({ maxHp = 1000, pdef = 8, mdef = 0 }) }
			Combat.run(phys, Fixtures.monster({ hp = 100000, atk = 10, attackType = "physical" }), Rng.new(1), K)
			local mag = { M({ maxHp = 1000, pdef = 0, mdef = 8 }) }
			Combat.run(mag, Fixtures.monster({ hp = 100000, atk = 10, attackType = "magic" }), Rng.new(1), K)
			-- 1ターンあたり 2 ダメージ × 30 ターン
			expect(phys[1].hp).toBe(1000 - 60)
			expect(mag[1].hp).toBe(1000 - 60)
		end)
		it("D-037 魔法攻撃職は魔法防御を引く", function()
			local r = Combat.run(
				{ M({ attackType = "magic", atk = 50 }) },
				Fixtures.monster({ hp = 10000, pdef = 0, mdef = 40 }),
				Rng.new(1),
				K
			)
			expect(r.turns[1].actions[1].amount).toBe(10)
		end)
	end)

	describe("支援系", function()
		it("D-034 HP70%未満の味方がいれば、HP割合が最も低い味方を回復", function()
			local members = {
				M({ slot = 1, maxHp = 100 }, 60),
				M({ slot = 2, maxHp = 100 }, 50),
				M({ slot = 3, heals = true, mag = 100 }),
			}
			local target = Combat.healTarget(members, K)
			expect(target and target.slot).toBe(2)
		end)
		it("D-034 全員70%以上なら回復しない", function()
			local members = { M({ slot = 1, maxHp = 100 }, 70), M({ slot = 2, heals = true }) }
			expect(Combat.healTarget(members, K)).toBe(nil)
		end)
		it("D-034 回復対象がいなければ攻撃する", function()
			local r = Combat.run({ M({ heals = true, atk = 500 }) }, Fixtures.monster(), Rng.new(1), K)
			expect(r.turns[1].actions[1].kind).toBe("attack")
		end)
		it("D-022 回復は最大HPを超えない", function()
			local members = {
				M({ slot = 1, maxHp = 100, agi = 1 }, 60),
				M({ slot = 2, heals = true, mag = 1000, agi = 99 }),
			}
			local r = Combat.run(members, Fixtures.monster({ hp = 100000, atk = 1 }), Rng.new(1), K)
			local a = r.turns[1].actions[1]
			expect(a.kind).toBe("heal")
			expect(a.amount).toBe(40)
		end)
	end)
end
