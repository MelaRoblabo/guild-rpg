--!strict
local Appearance = require("../src/core/Appearance")
local Game = require("../src/core/Game")
local Hiring = require("../src/core/Hiring")
local Rng = require("../src/core/Rng")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1767225600

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local K = master.K

	local function ctx()
		return { now = T0, master = master, online = true }
	end

	local function newState(gold: number?)
		local s = Game.newState(master, 1, T0)
		s.gold = gold or 100000
		return s
	end

	local function exec(s: any, cmd: any)
		return Game.execute(s, cmd, ctx())
	end

	local function count(tbl: any): number
		local n = 0
		for _ in tbl do
			n += 1
		end
		return n
	end

	describe("雇用の開始（02章 §3）", function()
		it("Q-006 雇用費を払い、候補が候補枠の数だけ出る", function()
			local s = newState(1000)
			local r = exec(s, { type = "HireStart" })
			expect(r.ok).toBeTruthy()
			expect(s.gold).toBe(1000 - K.hireCost)
			expect(#s.hireSession.candidates).toBe(s.expansions.candidateSlots)
		end)
		it("お金が足りなければ始められない", function()
			local s = newState(K.hireCost - 1)
			expect(exec(s, { type = "HireStart" }).error).toBe("NOT_ENOUGH_GOLD")
		end)
		it("所属枠がいっぱいなら始められない", function()
			local s = newState()
			s.expansions.rosterSize = count(s.adventurers)
			expect(exec(s, { type = "HireStart" }).error).toBe("ROSTER_FULL")
		end)
		it("雇用の途中は二重に始められない", function()
			local s = newState()
			exec(s, { type = "HireStart" })
			expect(exec(s, { type = "HireStart" }).error).toBe("SESSION_EXISTS")
		end)
		it("D-050 / D-042 候補の見た目は性別・職業区分と一致し、レア職は出ない", function()
			local s = newState()
			for _ = 1, 50 do
				s.hireSession = nil
				exec(s, { type = "HireStart" })
				for _, c in s.hireSession.candidates do
					if c.kind == "general" then
						local a = master.appearances[c.appearanceId]
						expect(a.gender).toBe(c.gender)
						expect(a.outfitClass).toBe(master.jobs[c.jobId].outfitClass)
						expect(master.jobs[c.jobId].isRare).toBe(false)
						expect(#c.giftIds).toBe(1)
					end
				end
			end
		end)
	end)

	describe("面接と引き直し（02章 §3、Q-006）", function()
		local function started()
			local s = newState()
			exec(s, { type = "HireStart" })
			-- 一般の候補を選ぶ
			for i, c in s.hireSession.candidates do
				if c.kind == "general" then
					exec(s, { type = "HirePick", candidateIndex = i })
					return s
				end
			end
			error("一般の候補がいない")
		end

		it("Q-006 面接でステータスを抽選する（範囲内）", function()
			local s = started()
			local r = s.hireSession.currentRoll
			for _, k in { "str", "mag", "agi", "dex" } do
				expect(r[k]).toBeBetween(K.hireStatRange[k].min, K.hireStatRange[k].max)
			end
			expect(r.hp).toBeBetween(K.hireStatRange.hp.min, K.hireStatRange.hp.max)
		end)
		it("D-081 ステータスの範囲はギルドレベルに関係なく一定", function()
			local s = started()
			s.guild.level = 100
			local rng = Rng.new(3)
			local maxStr = 0
			for _ = 1, 2000 do
				maxStr = math.max(maxStr, Hiring.rollStats(rng, master).str)
			end
			expect(maxStr).toBe(K.hireStatRange.str.max)
		end)
		it("面接する候補は1人だけ（選び直せない）", function()
			local s = started()
			expect(exec(s, { type = "HirePick", candidateIndex = 1 }).error).toBe("ALREADY_PICKED")
		end)
		it("Q-006 無料で3回引き直せ、4回目からチケットを消費する", function()
			local s = started()
			for _ = 1, K.hireFreeRerolls do
				expect(exec(s, { type = "HireReroll" }).ok).toBeTruthy()
			end
			expect(exec(s, { type = "HireReroll" }).error).toBe("NO_TICKET")
			s.items.itm_slot_ticket = 2
			expect(exec(s, { type = "HireReroll" }).ok).toBeTruthy()
			expect(s.items.itm_slot_ticket).toBe(1)
		end)
		it("引き直すと直前の結果が prev、新しい結果が cur になる", function()
			local s = started()
			local first = table.clone(s.hireSession.currentRoll)
			exec(s, { type = "HireReroll" })
			expect(s.hireSession.previousRoll).toEqual(first)
		end)
		it("prev を選ぶと前回の結果で雇用される", function()
			local s = started()
			local first = table.clone(s.hireSession.currentRoll)
			exec(s, { type = "HireReroll" })
			local before = count(s.adventurers)
			local r = exec(s, { type = "HireChoose", which = "previous" })
			expect(r.ok).toBeTruthy()
			expect(count(s.adventurers)).toBe(before + 1)
			local adv = s.adventurers[(r.events :: any)[1].uid]
			expect(adv.baseStats).toEqual(first)
			expect(adv.level).toBe(1)
			expect(adv.levelCap).toBe(K.levelCapInitial)
			expect(s.hireSession).toBe(nil)
		end)
		it("引き直す前は prev を選べない", function()
			local s = started()
			expect(exec(s, { type = "HireChoose", which = "previous" }).error).toBe("INVALID_CHOICE")
		end)
		it("やめると雇用費は戻らない", function()
			local s = newState(1000)
			exec(s, { type = "HireStart" })
			exec(s, { type = "HireCancel" })
			expect(s.gold).toBe(1000 - K.hireCost)
			expect(s.hireSession).toBe(nil)
		end)
	end)

	describe("特別な訪問者（D-055）", function()
		it("ユニークはステータス固定で引き直せない。名前も変えられない", function()
			local m = Fixtures.master(function(d)
				d.Constants.specialVisitorChance = 1
			end)
			local s = Game.newState(m, 1, T0)
			s.gold = 100000
			Game.execute(s, { type = "HireStart" }, { now = T0, master = m, online = true })
			local c = s.hireSession.candidates[1]
			expect(c.kind).toBe("unique")
			Game.execute(s, { type = "HirePick", candidateIndex = 1 }, { now = T0, master = m, online = true })
			expect(s.hireSession.currentRoll).toEqual(m.uniques[c.uniqueId].baseStats)
			local r = Game.execute(s, { type = "HireReroll" }, { now = T0, master = m, online = true })
			expect(r.error).toBe("UNIQUE_FIXED_STATS")
			local r2 = Game.execute(
				s,
				{ type = "HireChoose", which = "current" },
				{ now = T0, master = m, online = true }
			)
			local uid = (r2.events :: any)[1].uid
			expect(s.adventurers[uid].uniqueId).toBe(c.uniqueId)
			local r3 = Game.execute(
				s,
				{ type = "Rename", adventurerUid = uid, name = "x" },
				{ now = T0, master = m, online = true }
			)
			expect(r3.error).toBe("UNIQUE_CANNOT_RENAME")
		end)
		it("同じユニークは候補に重複して出ない", function()
			local m = Fixtures.master(function(d)
				d.Constants.specialVisitorChance = 1
			end)
			local s = Game.newState(m, 2, T0)
			s.gold = 100000
			Game.execute(s, { type = "HireStart" }, { now = T0, master = m, online = true })
			local seen = {}
			for _, c in s.hireSession.candidates do
				if c.kind == "unique" then
					expect(seen[c.uniqueId]).toBe(nil)
					seen[c.uniqueId] = true
				end
			end
		end)
	end)

	describe("見た目と名前（D-050〜D-054）", function()
		it(
			"D-050 統計: 性別半々、美形15/普通50/ブサイク20/亜人15%（2万回、誤差±1.5%）",
			function()
				local rng = Rng.new(11)
				local g, l = { m = 0, f = 0 }, { bea = 0, nor = 0, ugl = 0, dem = 0 }
				local n = 20000
				for _ = 1, n do
					local a = Appearance.roll(nil, "phy", rng, master)
					g[a.gender] += 1
					l[a.looks] += 1
				end
				expect(g.m / n).toBeCloseTo(0.5, 0.015)
				expect(l.bea / n).toBeCloseTo(0.15, 0.015)
				expect(l.nor / n).toBeCloseTo(0.50, 0.015)
				expect(l.ugl / n).toBeCloseTo(0.20, 0.015)
				expect(l.dem / n).toBeCloseTo(0.15, 0.015)
			end
		)
		it("D-051 性別を固定でき、直前と同じ見た目は出ない", function()
			local rng = Rng.new(12)
			for _ = 1, 2000 do
				local a = Appearance.roll("f", "mag", rng, master, "chr_f_nor_mag_01")
				expect(a.gender).toBe("f")
				expect(a.appearanceId ~= "chr_f_nor_mag_01").toBeTruthy()
			end
		end)
		it("D-054 亜人は亜人用の名前リスト", function()
			local rng = Rng.new(13)
			for _ = 1, 200 do
				local name = Appearance.rollName("m", "dem", rng, master)
				expect(table.find(master.raw.Names.dem, name) ~= nil).toBeTruthy()
			end
		end)
		it("D-260 名前を引くとき、使ってほしくない名前は出ない", function()
			local rng = Rng.new(14)
			local list = master.raw.Names.m
			local taken = {}
			for i = 2, #list do
				taken[list[i]] = true -- 1つ目だけ残す
			end
			for _ = 1, 50 do
				expect(Appearance.rollName("m", "nor", rng, master, taken)).toBe(list[1])
			end
		end)
		it("D-260 同じ回の候補で名前が重ならない", function()
			local s = newState(1000)
			s.expansions.candidateSlots = 3
			for seed = 1, 300 do
				local cs = Hiring.rollCandidates(s, Rng.new(seed), master, T0)
				local seen = {}
				for _, c in cs do
					expect(seen[c.name]).toBe(nil)
					seen[c.name] = true
				end
			end
		end)
	end)

	describe("名前変更・解雇（02章、Q-020）", function()
		it("名前は1〜12文字", function()
			local s = newState()
			local uid = s.parties[1].slots[1]
			expect(exec(s, { type = "Rename", adventurerUid = uid, name = "ロングネームの冒険者さん" }).ok).toBeTruthy()
			expect(
				exec(
					s,
					{ type = "Rename", adventurerUid = uid, name = "とても長すぎる名前の冒険者です" }
				).error
			).toBe("INVALID_NAME")
		end)
		it("Q-020 解雇すると装備は倉庫へ戻り、パーティの枠が空く", function()
			local s = newState()
			local uid = s.parties[1].slots[2]
			local weapon = s.adventurers[uid].equipment.weapon
			expect(exec(s, { type = "Dismiss", adventurerUid = uid }).ok).toBeTruthy()
			expect(s.adventurers[uid]).toBe(nil)
			expect(s.parties[1].slots[2]).toBe("")
			expect(s.equipment[weapon].equippedBy).toBe(nil)
		end)
		it("Q-020 保護中・探索中は解雇できない", function()
			local s = newState()
			local uid = s.parties[1].slots[1]
			exec(s, { type = "SetLock", uid = uid, locked = true })
			expect(exec(s, { type = "Dismiss", adventurerUid = uid }).error).toBe("ADVENTURER_LOCKED")
			exec(s, { type = "SetLock", uid = uid, locked = false })
			exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" })
			expect(exec(s, { type = "Dismiss", adventurerUid = uid }).error).toBe("ADVENTURER_ON_EXPEDITION")
		end)
	end)
end
