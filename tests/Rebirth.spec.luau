--!strict
local Formulas = require("../src/core/Formulas")
local Game = require("../src/core/Game")
local Rebirth = require("../src/core/Rebirth")
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
	local function exec(s: any, cmd: any)
		return Game.execute(s, cmd, ctx())
	end

	-- 隊列1の冒険者を上限レベルにした状態
	local function atCap(seed: number?)
		local s = Game.newState(master, seed or 1, T0)
		local uid = s.parties[1].slots[1]
		local adv = s.adventurers[uid]
		adv.level = adv.levelCap
		adv.baseStats = { str = 100, mag = 20, agi = 40, dex = 30, hp = 200 }
		s.gold = 10 ^ 9 -- 転生費用（D-080）
		return s, uid, adv
	end

	describe("転生の開始（07章 §2、D-071）", function()
		it("D-071 上限レベルに達していないと転生できない", function()
			local s = Game.newState(master, 1, T0)
			expect(exec(s, { type = "RebirthStart", adventurerUid = s.parties[1].slots[1] }).error).toBe(
				"LEVEL_NOT_AT_CAP"
			)
		end)
		it("D-080 転生には転生回数に応じたゴールドが要る", function()
			local s, uid, adv = atCap()
			adv.rebirthCount = 2
			adv.levelCap = K.levelCapInitial + 2 * K.levelCapPerRebirth
			adv.level = adv.levelCap
			local cost = K.rebirthCost[3]
			s.gold = cost - 1
			expect(exec(s, { type = "RebirthStart", adventurerUid = uid }).error).toBe("NOT_ENOUGH_GOLD")
			s.gold = cost
			expect(exec(s, { type = "RebirthStart", adventurerUid = uid }).ok).toBeTruthy()
			expect(s.gold).toBe(0)
		end)
		it("D-071 上限100では転生できない", function()
			local s, uid, adv = atCap()
			adv.levelCap = K.levelCapMax
			adv.level = K.levelCapMax
			expect(exec(s, { type = "RebirthStart", adventurerUid = uid }).error).toBe("MAX_REBIRTH")
		end)
		it(
			"D-051 通常転生は性別を固定して見た目を引き直す（直前と同じは出ない）",
			function()
				for seed = 1, 30 do
					local s, uid, adv = atCap(seed)
					exec(s, { type = "RebirthStart", adventurerUid = uid })
					local newId = s.rebirthSession.newAppearanceId
					expect(newId ~= adv.appearanceId).toBeTruthy()
					expect(master.appearances[newId].gender).toBe(adv.gender)
					expect(master.appearances[newId].outfitClass).toBe(master.jobs[adv.jobId].outfitClass)
				end
			end
		)
		it("見た目維持ポーションを使うと姿を維持し、ポーションを1個消費", function()
			local s, uid, adv = atCap()
			expect(exec(s, { type = "RebirthStart", adventurerUid = uid, useKeepPotion = true }).error).toBe(
				"NO_POTION"
			)
			s.items.itm_potion_appearance_keep = 1
			expect(exec(s, { type = "RebirthStart", adventurerUid = uid, useKeepPotion = true }).ok).toBeTruthy()
			expect(s.rebirthSession.newAppearanceId).toBe(adv.appearanceId)
			expect(s.items.itm_potion_appearance_keep).toBe(0)
		end)
		it("転生の途中はそのパーティを派遣できない", function()
			local s, uid = atCap()
			exec(s, { type = "RebirthStart", adventurerUid = uid })
			expect(exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }).error).toBe(
				"ADVENTURER_IN_REBIRTH"
			)
		end)
	end)

	describe("転生スロット（D-072、Q-009、D-086）", function()
		it("Q-009 引き継ぎは素の値の1/2（切り捨て）", function()
			local s, uid = atCap()
			exec(s, { type = "RebirthStart", adventurerUid = uid })
			expect(s.rebirthSession.inherited).toEqual({ str = 50, mag = 10, agi = 20, dex = 15, hp = 100 })
		end)
		it("D-072 加算分は 0〜転生前の値×30%", function()
			local rng = Rng.new(1)
			local base = { str = 100, mag = 20, agi = 40, dex = 30, hp = 200 }
			for _ = 1, 2000 do
				local b = Rebirth.rollBonus(base, 1, rng, master)
				expect(b.str).toBeBetween(0, 30)
				expect(b.hp).toBeBetween(0, 60)
			end
		end)
		it("D-072 統計: 後半の転生ほど大きな値が出にくい（平均＝上限/(p+1)）", function()
			local rng = Rng.new(2)
			local n = 20000
			for _, count in { 1, 8 } do
				local sum = 0
				for _ = 1, n do
					sum += Formulas.rollRebirthBonus(1000, count, rng, K)
				end
				local p = Formulas.rebirthBonusSkew(count, K)
				expect(sum / n).toBeCloseTo(300 / (p + 1), 6)
			end
		end)
		it("Q-009 無料3回、その後はチケット", function()
			local s, uid = atCap()
			exec(s, { type = "RebirthStart", adventurerUid = uid })
			for _ = 1, K.rebirthFreeRerolls do
				expect(exec(s, { type = "RebirthReroll" }).ok).toBeTruthy()
			end
			expect(exec(s, { type = "RebirthReroll" }).error).toBe("NO_TICKET")
			s.items.itm_slot_ticket = 1
			expect(exec(s, { type = "RebirthReroll" }).ok).toBeTruthy()
			expect(s.items.itm_slot_ticket).toBe(0)
		end)
		it(
			"D-086 引き直すと直前の結果だけが比較用に残る（良い方は自動で残らない）",
			function()
				local s, uid = atCap()
				s.items.itm_slot_ticket = 30
				exec(s, { type = "RebirthStart", adventurerUid = uid })
				for _ = 1, 30 do
					local before = s.rebirthSession.currentBonus
					exec(s, { type = "RebirthReroll" })
					expect(s.rebirthSession.previousBonus).toEqual(before)
				end
			end
		)
		it("D-086 良い結果を残すには、その場で採用するしかない", function()
			local s, uid = atCap()
			s.items.itm_slot_ticket = 10
			exec(s, { type = "RebirthStart", adventurerUid = uid })
			local first = s.rebirthSession.currentBonus
			exec(s, { type = "RebirthReroll" })
			exec(s, { type = "RebirthReroll" })
			local r = s.rebirthSession
			expect(r.previousBonus == first or r.currentBonus == first).toBe(false)
		end)
	end)

	describe("転生の確定（07章 §2、D-024、D-071）", function()
		it("D-071 Lv1・上限+10・転生回数+1・値＝引き継ぎ＋加算", function()
			local s, uid, adv = atCap()
			exec(s, { type = "RebirthStart", adventurerUid = uid })
			local r = s.rebirthSession
			local expected = {}
			for k, v in r.inherited do
				expected[k] = v + r.currentBonus[k]
			end
			local newApp = r.newAppearanceId
			expect(exec(s, { type = "RebirthChoose", which = "current" }).ok).toBeTruthy()
			adv = s.adventurers[uid]
			expect(adv.level).toBe(1)
			expect(adv.levelCap).toBe(K.levelCapInitial + K.levelCapPerRebirth)
			expect(adv.rebirthCount).toBe(1)
			expect(adv.baseStats).toEqual(expected)
			expect(adv.appearanceId).toBe(newApp)
			expect(s.rebirthSession).toBe(nil)
		end)
		it("D-024 2回目の転生でギフトが1つ増える（1回目は増えない）", function()
			local s, uid, adv = atCap()
			local before = #adv.giftIds
			exec(s, { type = "RebirthStart", adventurerUid = uid })
			exec(s, { type = "RebirthChoose", which = "current" })
			adv = s.adventurers[uid]
			expect(#adv.giftIds).toBe(before)
			adv.level = adv.levelCap
			exec(s, { type = "RebirthStart", adventurerUid = uid })
			local r = exec(s, { type = "RebirthChoose", which = "current" })
			adv = s.adventurers[uid]
			expect(#adv.giftIds).toBe(before + 1)
			expect((r.events :: any)[1].giftAdded).toBe(adv.giftIds[#adv.giftIds])
		end)
		it("D-071 転生後は周回の倍率で必要経験値が変わる", function()
			expect(Formulas.expToNext(10, K, 3)).toBe(math.floor(100 * 10 ^ 1.5 * K.expCycleMult[4]))
		end)
		it("ユニークは見た目が固定（維持ポーションは使えない）", function()
			local s = Game.newState(master, 1, T0)
			local uid = s.parties[1].slots[1]
			local adv = s.adventurers[uid]
			adv.uniqueId = "uni_garrett"
			adv.appearanceId = "uni_garrett"
			adv.level = adv.levelCap
			s.gold = 10 ^ 9
			s.items.itm_potion_appearance_keep = 1
			expect(exec(s, { type = "RebirthStart", adventurerUid = uid, useKeepPotion = true }).error).toBe(
				"UNIQUE_APPEARANCE_FIXED"
			)
			exec(s, { type = "RebirthStart", adventurerUid = uid })
			expect(s.rebirthSession.newAppearanceId).toBe("uni_garrett")
		end)
	end)

	describe("転職（03章 §4、D-045、D-052）", function()
		local function setup()
			local s = Game.newState(master, 1, T0)
			local uid = s.parties[1].slots[1] -- 戦士
			return s, uid, s.adventurers[uid]
		end
		it("転職ポーションが必要で、使うと1個減る", function()
			local s, uid, adv = setup()
			expect(exec(s, { type = "ChangeJob", adventurerUid = uid, jobId = "job_knight" }).error).toBe("NO_POTION")
			s.items.itm_potion_job_knight = 1
			expect(exec(s, { type = "ChangeJob", adventurerUid = uid, jobId = "job_knight" }).ok).toBeTruthy()
			adv = s.adventurers[uid]
			expect(adv.jobId).toBe("job_knight")
			expect(s.items.itm_potion_job_knight).toBe(0)
		end)
		it("同じ職業には転職できない", function()
			local s, uid = setup()
			s.items.itm_potion_job_warrior = 1
			expect(exec(s, { type = "ChangeJob", adventurerUid = uid, jobId = "job_warrior" }).error).toBe("SAME_JOB")
		end)
		it("D-052 見た目・レベル・ステータスは維持し、装備できない品は倉庫へ", function()
			local s, uid, adv = setup()
			local app, level, stats = adv.appearanceId, adv.level, table.clone(adv.baseStats)
			local sword = adv.equipment.weapon
			s.items.itm_potion_job_mage = 1
			local r = exec(s, { type = "ChangeJob", adventurerUid = uid, jobId = "job_mage" })
			expect(r.ok).toBeTruthy()
			adv = s.adventurers[uid]
			expect(adv.appearanceId).toBe(app)
			expect(adv.level).toBe(level)
			expect(adv.baseStats).toEqual(stats)
			expect(adv.equipment.weapon).toBe(nil)
			expect(s.equipment[sword].equippedBy).toBe(nil)
		end)
		it("D-045 転職後のレベルアップは新しい職業の成長", function()
			local s, uid, adv = setup()
			s.items.itm_potion_job_mage = 1
			exec(s, { type = "ChangeJob", adventurerUid = uid, jobId = "job_mage" })
			adv = s.adventurers[uid]
			local before = adv.baseStats.mag
			require("../src/core/Growth").addExp(adv, 100000, Rng.new(1), master)
			local levels = adv.level - 1
			expect(adv.baseStats.mag - before >= levels * 4).toBeTruthy()
		end)
		it("ユニーク：固有職業は転職不可、それ以外は同じ系統内のみ", function()
			local s, uid, adv = setup()
			s.items.itm_potion_job_knight = 1
			s.items.itm_potion_job_mage = 1
			adv.uniqueId = "uni_garrett" -- jobChange = line（戦士系）
			expect(exec(s, { type = "ChangeJob", adventurerUid = uid, jobId = "job_mage" }).error).toBe(
				"UNIQUE_JOB_RESTRICTED"
			)
			expect(exec(s, { type = "ChangeJob", adventurerUid = uid, jobId = "job_knight" }).ok).toBeTruthy()
			adv = s.adventurers[uid]
			adv.uniqueId = "uni_bran" -- jobChange = none
			s.items.itm_potion_job_warrior = 1
			expect(exec(s, { type = "ChangeJob", adventurerUid = uid, jobId = "job_warrior" }).error).toBe(
				"UNIQUE_JOB_RESTRICTED"
			)
		end)
	end)

	describe("見た目変更ポーション（07章 §3、D-051）", function()
		it("どちらを選んでも1個消費し、prev を選べば姿は変わらない", function()
			local s = Game.newState(master, 1, T0)
			local uid = s.parties[1].slots[1]
			local adv = s.adventurers[uid]
			local app = adv.appearanceId
			s.items.itm_potion_appearance_change = 1
			expect(exec(s, { type = "ChangeAppearance", adventurerUid = uid }).ok).toBeTruthy()
			expect(s.items.itm_potion_appearance_change).toBe(0)
			local newId = s.appearanceSession.currentId
			expect(master.appearances[newId].gender).toBe(adv.gender)
			expect(newId ~= app).toBeTruthy()
			exec(s, { type = "ChangeAppearanceChoose", which = "previous" })
			expect(adv.appearanceId).toBe(app)
		end)
		it("cur を選べば新しい姿になる", function()
			local s = Game.newState(master, 1, T0)
			local uid = s.parties[1].slots[1]
			s.items.itm_potion_appearance_change = 1
			exec(s, { type = "ChangeAppearance", adventurerUid = uid })
			local newId = s.appearanceSession.currentId
			exec(s, { type = "ChangeAppearanceChoose", which = "current" })
			expect(s.adventurers[uid].appearanceId).toBe(newId)
		end)
		it("ユニークは見た目を変えられない", function()
			local s = Game.newState(master, 1, T0)
			local uid = s.parties[1].slots[1]
			s.adventurers[uid].uniqueId = "uni_garrett"
			s.items.itm_potion_appearance_change = 1
			expect(exec(s, { type = "ChangeAppearance", adventurerUid = uid }).error).toBe("UNIQUE_CANNOT_CHANGE")
		end)
	end)
end
