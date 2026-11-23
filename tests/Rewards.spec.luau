--!strict
-- 報酬（M7b-4 前半）：受け取り箱（D-164, D-176）、特別な宝箱（D-166, D-171, D-185）、クエスト（D-153, D-179）、
-- ログインボーナス（D-155, D-169）、プレイ時間（D-154）、セーブの移行 v7 → 8
local serde = require("@lune/serde")

local Calendar = require("../src/core/Calendar")
local Chest = require("../src/core/Chest")
local CommandText = require("../src/core/CommandText")
local Game = require("../src/core/Game")
local Hiring = require("../src/core/Hiring")
local Inbox = require("../src/core/Inbox")
local MasterData = require("../src/core/MasterData")
local Migration = require("../src/core/Migration")
local Protocol = require("../src/core/Protocol")
local Quest = require("../src/core/Quest")
local Rng = require("../src/core/Rng")
local Data = require("../src/data")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1767225600 -- 2026-01-01 00:00 UTC（木曜）
local DAY = 86400

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local K = master.K

	local function ctx(now: number, online: boolean?, m: any?)
		return { now = now, master = m or master, online = if online == nil then true else online }
	end
	local function exec(s: any, cmd: any, now: number?, m: any?): any
		return Game.execute(s, cmd, ctx(now or T0, true, m))
	end
	local function newState(seed: number?, m: any?)
		return Game.newState(m or master, seed or 1, T0)
	end
	local function rngOf(seed: number): () -> Rng.Rng
		return function()
			return Rng.new(seed)
		end
	end
	local function eventsOf(events: { any }, typ: string): { any }
		local out = {}
		for _, e in events do
			if e.type == typ then
				table.insert(out, e)
			end
		end
		return out
	end
	local function errorsOf(m: (any) -> ()): string
		local d = Fixtures.clone(Data)
		m(d)
		local lines = {}
		for _, i in MasterData.validate(d) do
			if i.level == "error" then
				table.insert(lines, i.path .. " " .. i.message)
			end
		end
		return table.concat(lines, "\n")
	end
	-- ログイン用のユニーク（acquire = "login"）を足したマスターデータ。中身は未決（Q-025）なのでテストだけで作る
	local function masterWithLoginUniques(n: number): any
		return Fixtures.master(function(d)
			for i = 1, n do
				table.insert(d.Uniques, {
					id = `uni_test_login_{i}`,
					name = `ログイン{i}`,
					gender = "f",
					appearanceId = `uni_test_login_{i}`,
					jobId = "job_mage",
					baseStats = { str = 6, mag = 20, agi = 14, dex = 14, hp = 50 },
					giftIds = { "gift_lucky" },
					acquire = "login",
					loginOrder = i,
					jobChange = "line",
				})
			end
		end)
	end
	local function rosterCount(s: any): number
		local n = 0
		for _ in s.adventurers do
			n += 1
		end
		return n
	end
	local function fillRoster(s: any, m: any)
		while rosterCount(s) < s.expansions.rosterSize do
			local uid = `adv_{s.nextUid}`
			s.nextUid += 1
			s.adventurers[uid] = Hiring.newAdventurer(uid, {
				name = "x",
				gender = "m",
				appearanceId = "chr_m_nor_phy_01",
				jobId = "job_warrior",
				giftIds = {},
			}, { str = 1, mag = 1, agi = 1, dex = 1, hp = 20 }, T0, m)
		end
	end

	describe("受け取り箱（D-164, D-176）", function()
		it(
			"D-164 ゴールド・アイテム・宝箱をまとめて受け取る。宝箱は宝箱の山へ入る",
			function()
				local s = newState()
				-- ゴールドは係数（D-190）：まだどこも踏破していないので古い墓地の基準 × 1
				expect(master.dungeons.dng_graveyard.rewardGoldBase).toBe(100)
				Inbox.push(s, "quest", T0, {
					goldMult = 1,
					items = { itm_slot_ticket = 2 },
					chests = { { pileKey = "special:quest", rank = 2, count = 3 } },
				}, rngOf(1), master)
				Inbox.push(
					s,
					"playtime",
					T0,
					{ chests = { { pileKey = "special:playtime", count = 4 } } },
					rngOf(2),
					master
				)
				expect(#s.inbox).toBe(2)
				local gold0 = s.gold
				local r = exec(s, { type = "ClaimInbox" })
				expect(r.ok).toBeTruthy()
				expect(s.gold).toBe(gold0 + 100)
				expect(s.items.itm_slot_ticket).toBe(2)
				expect(Chest.count(s, "special:quest", 2)).toBe(3)
				expect(Chest.pileTotal(s, "special:playtime")).toBe(4)
				expect(#s.inbox).toBe(0)
				local ev = r.events[1]
				expect(ev.type).toBe("InboxClaimed")
				expect(ev.gold).toBe(100)
				expect(ev.chests).toEqual({
					{ pileKey = "special:quest", count = 3 },
					{ pileKey = "special:playtime", count = 4 },
				})
				expect(ev.remaining).toBe(0)
			end
		)
		it("D-164 空の受け取り箱は INBOX_EMPTY（状態は変えない）", function()
			local s = newState()
			local before = Game._deepClone(s)
			expect(exec(s, { type = "ClaimInbox" }).error).toBe("INBOX_EMPTY")
			expect(s).toEqual(before)
		end)
		it(
			"D-166 rank を省いた宝箱は届いたときに表でランクを決め、山×ランクでまとめる",
			function()
				local s = newState()
				local e = Inbox.push(
					s,
					"quest",
					T0,
					{ chests = { { pileKey = "special:quest", count = 50 } } },
					rngOf(7),
					master
				)
				local total = 0
				local prev = 0
				for _, c in e.rewards.chests do
					expect(c.pileKey).toBe("special:quest")
					expect(c.rank > prev).toBeTruthy() -- ランクの低い順・重複なし
					expect(master.specialChests["special:quest"].rarityWeights[c.rank] > 0).toBeTruthy()
					prev = c.rank
					total += c.count
				end
				expect(total).toBe(50)
				-- 同じ乱数なら同じ結果
				local s2 = newState()
				local e2 = Inbox.push(
					s2,
					"quest",
					T0,
					{ chests = { { pileKey = "special:quest", count = 50 } } },
					rngOf(7),
					master
				)
				expect(e2.rewards.chests).toEqual(e.rewards.chests)
			end
		)
		it(
			"D-176 所属枠がいっぱいのユニークは受け取り箱に残し、ほかは受け取る。期限はない",
			function()
				local m = masterWithLoginUniques(1)
				local s = newState(1, m)
				Inbox.push(s, "login", T0, { goldMult = 0.5 }, rngOf(1), m, "uni_test_login_1") -- 100 × 0.5（D-190）
				fillRoster(s, m)
				local gold0 = s.gold
				local r = exec(s, { type = "ClaimInbox" }, T0, m)
				expect(r.ok).toBeTruthy()
				expect(s.gold).toBe(gold0 + 50)
				expect(#s.inbox).toBe(1)
				expect(s.inbox[1].rewards).toEqual({ uniqueId = "uni_test_login_1" })
				expect(r.events[1].blocked).toBe("ROSTER_FULL")
				expect(r.events[1].remaining).toBe(1)
				-- 何日たっても残る。枠が空けば受け取れる
				Game.advance(s, ctx(T0 + 30 * DAY, true, m))
				local found = false
				for _, e in s.inbox do
					found = found or e.rewards.uniqueId == "uni_test_login_1"
				end
				expect(found).toBeTruthy()
				s.expansions.rosterSize += 1
				local r2 = exec(s, { type = "ClaimInbox" }, T0 + 30 * DAY, m)
				expect(r2.ok).toBeTruthy()
				local joined = eventsOf(r2.events, "UniqueJoined")
				expect(#joined).toBe(1)
				expect(s.adventurers[joined[1].uid].uniqueId).toBe("uni_test_login_1")
				for _, e in s.inbox do
					expect(e.rewards.uniqueId).toBe(nil)
				end
			end
		)
		it("D-087 受け取り箱の要約・Protocol の要約に宝箱のランクを出さない", function()
			local s = newState()
			Inbox.push(
				s,
				"quest",
				T0,
				{ chests = { { pileKey = "special:quest", rank = 3, count = 2 } } },
				rngOf(1),
				master
			)
			local sum = Game.query.inbox(s)
			expect(sum[1].chests).toEqual({ { pileKey = "special:quest", count = 2 } })
			local v = Protocol.view(s, master)
			expect(string.find(serde.encode("json", v.inbox), "rank", 1, true)).toBe(nil)
			expect(Protocol.validateCommand({ type = "ClaimInbox" })).toBe(true)
			expect(CommandText.parse("claim")).toEqual({ type = "ClaimInbox" })
		end)
	end)

	describe("特別な宝箱（D-166, D-171, D-185）", function()
		it(
			"D-166 special:quest・login・playtime・raid の山を開けられる。演出は行の effectMinRarity 以上",
			function()
				for _, key in { "special:quest", "special:login", "special:playtime", "special:raid" } do
					local s = newState()
					s.settings.autoSell.enabled = false
					local line = master.specialChests[key].effectMinRarity
					Chest.add(s, key, line, 1)
					Chest.add(s, key, line - 1, 1)
					local r = exec(s, { type = "OpenChests", pileKey = key })
					expect(r.ok).toBeTruthy()
					local ev = r.events[1]
					expect(ev.opened).toBe(2)
					expect(#ev.special).toBe(1)
					expect(ev.special[1].rank).toBe(line)
					expect(#ev.normal).toBe(1)
					expect(ev.normal[1].rank).toBe(line - 1)
					expect(ev.remaining).toBe(0)
				end
			end
		)
		it(
			"D-171 中身のアイテムレベルは開けたときに踏破している一番深いダンジョンの tier",
			function()
				local function openLevel(cleared: { string }): number
					local s = newState()
					s.settings.autoSell.enabled = false
					for _, id in cleared do
						s.clearedDungeons[id] = true
					end
					Chest.add(s, "special:quest", 1, 1)
					local r = exec(s, { type = "OpenChests", pileKey = "special:quest" })
					local uid = r.events[1].normal[1].equipmentUids[1]
					return s.equipment[uid].itemLevel
				end
				expect(openLevel({ "dng_graveyard" })).toBe(master.dungeons.dng_graveyard.tier)
				expect(openLevel({ "dng_graveyard", "dng_ruins", "dng_tower" })).toBe(master.dungeons.dng_tower.tier)
				-- 並びに関係なく tier の最大
				expect(openLevel({ "dng_tower", "dng_graveyard" })).toBe(master.dungeons.dng_tower.tier)
				-- まだどこも踏破していなければダンジョンの並びの先頭＝古い墓地（D-187）
				expect(openLevel({})).toBe(master.dungeonList[1].tier)
				-- 山は数だけを保存するので、届いた後に深く踏破すれば深い方で決まる
				local s = newState()
				s.settings.autoSell.enabled = false
				s.clearedDungeons.dng_graveyard = true
				Chest.add(s, "special:login", 1, 2)
				exec(s, { type = "OpenChests", pileKey = "special:login", count = 1 })
				s.clearedDungeons.dng_castle = true
				local r = exec(s, { type = "OpenChests", pileKey = "special:login", count = 1 })
				expect(s.equipment[r.events[1].normal[1].equipmentUids[1]].itemLevel).toBe(
					master.dungeons.dng_castle.tier
				)
			end
		)
		it(
			"D-171 D-185 レアダンジョンの山は相当するダンジョンの表と演出ライン rareChestEffectMinRarity で開ける",
			function()
				local m = Fixtures.master(function(d)
					for _, g in d.Dungeons do
						if g.id == "dng_tower" then
							g.rareChestEffectMinRarity = 2 -- アンコモン以上 28%（20〜30% の中）
						end
					end
				end)
				local s = newState(1, m)
				s.settings.autoSell.enabled = false
				Chest.add(s, "special:rare:dng_tower", 2, 1)
				Chest.add(s, "special:rare:dng_tower", 1, 1)
				local r = exec(s, { type = "OpenChests", pileKey = "special:rare:dng_tower" }, T0, m)
				expect(r.ok).toBeTruthy()
				local ev = r.events[1]
				expect(#ev.special).toBe(1)
				expect(ev.special[1].rank).toBe(2)
				local uid = ev.special[1].equipmentUids[1]
				expect(s.equipment[uid].itemLevel).toBe(m.dungeons.dng_tower.tier)
				-- 演出ラインを持たないダンジョンの山は開けられない（D-188 で本番データは全ダンジョンが持つので、読み込んだ後に外す）
				m.dungeons.dng_castle.rareChestEffectMinRarity = nil
				Chest.add(s, "special:rare:dng_castle", 1, 1)
				expect(exec(s, { type = "OpenChests", pileKey = "special:rare:dng_castle" }, T0, m).error).toBe(
					"PILE_NOT_FOUND"
				)
				expect(exec(s, { type = "OpenChests", pileKey = "special:rare:dng_nope" }, T0, m).error).toBe(
					"PILE_NOT_FOUND"
				)
			end
		)
		it(
			"D-166 演出率の検査は行ごとの基準（D-090 の 10〜15% は普通のダンジョンだけ）",
			function()
				-- 本番の表は通る（レイドは 30% で 10〜15% の外だが、行の基準 20〜40% の中）
				expect(errorsOf(function(_d) end)).toBe("")
				local e = errorsOf(function(d)
					for _, row in d.SpecialChests do
						if row.id == "spc_quest" then
							row.effectMinRarity = 4 -- エピック以上 5%（基準 15〜25% の外）
						end
					end
				end)
				expect(string.find(e, "SpecialChests[3].effectMinRarity", 1, true) ~= nil).toBeTruthy()
				-- レアダンジョンの演出ラインは rareDungeonEffectRate（20〜30%）で検査する（D-171）
				local e2 = errorsOf(function(d)
					for _, g in d.Dungeons do
						if g.id == "dng_castle" then
							g.rareChestEffectMinRarity = 4 -- エピック以上 10%（D-188 の表 62/16/12/10）
						end
					end
				end)
				expect(string.find(e2, "rareChestEffectMinRarity", 1, true) ~= nil).toBeTruthy()
				-- レアダンジョンの行は表を持たない
				local e3 = errorsOf(function(d)
					d.SpecialChests[1].rarityWeights = { 1 }
				end)
				expect(string.find(e3, "SpecialChests[1].rarityWeights", 1, true) ~= nil).toBeTruthy()
			end
		)
		it(
			"D-166 報酬の宝箱は表を持つ特別な宝箱の山だけ。売却用アイテムは報酬にしない",
			function()
				local e = errorsOf(function(d)
					d.Quests[1].rewards = { chests = { { pileKey = "dng_graveyard", count = 1 } } }
				end)
				expect(string.find(e, "Quests[1].rewards.chests[1].pileKey", 1, true) ~= nil).toBeTruthy()
				local e2 = errorsOf(function(d)
					d.LoginBonus.days[1] = { items = { itm_bone_fragment = 1 } }
				end)
				expect(string.find(e2, "LoginBonus.days[1].items", 1, true) ~= nil).toBeTruthy()
			end
		)
	end)

	describe("クエスト（D-153, D-179）", function()
		local function today(s: any)
			Game.advance(s, ctx(T0))
		end
		it(
			"D-153 デイリー3つ・ウィークリーは questWeeklyCount 個。重複なし、量は amountPerParty × パーティ数",
			function()
				local s = newState()
				s.expansions.partySlots = 3
				today(s)
				expect(#s.quests.daily.entries).toBe(K.questDailyCount)
				expect(#s.quests.weekly.entries).toBe(K.questWeeklyCount)
				expect(s.quests.daily.dayIndex).toBe(Calendar.dayIndex(T0))
				expect(s.quests.weekly.weekIndex).toBe(Calendar.weekIndex(T0))
				for _, period in { "daily", "weekly" } do
					local seen = {}
					for _, e in s.quests[period].entries do
						local row = master.quests[e.questId]
						expect(row.period).toBe(period)
						expect(seen[e.questId]).toBe(nil)
						seen[e.questId] = true
						expect(e.target).toBe(row.amountPerParty * 3)
						expect(e.progress).toBe(0)
						expect(e.done).toBe(false)
					end
				end
			end
		)
		it("D-153 転生のお題はウィークリーだけ（検証）", function()
			for seed = 1, 40 do
				for _, e in Quest.draw({ seed = seed, expansions = { partySlots = 1 } }, "daily", 100 + seed, master) do
					expect(master.quests[e.questId].kind ~= "rebirths").toBeTruthy()
				end
			end
			local err = errorsOf(function(d)
				d.Quests[1].kind = "rebirths"
			end)
			expect(string.find(err, "Quests[1].kind", 1, true) ~= nil).toBeTruthy()
		end)
		it(
			"D-153 お題は calendarSeed・日の番号・プレイヤーで決まる（同じ日・同じ人は同じ）",
			function()
				local a = Quest.draw({ seed = 11, expansions = { partySlots = 1 } }, "daily", 500, master)
				local b = Quest.draw({ seed = 11, expansions = { partySlots = 1 } }, "daily", 500, master)
				expect(a).toEqual(b)
				-- 日・人・calendarSeed のどれかが違えば変わりうる
				local function differs(f: (number) -> { any }): boolean
					local first = f(1)
					for i = 2, 40 do
						if not Protocol.deepEqual(f(i), first) then
							return true
						end
					end
					return false
				end
				expect(differs(function(i)
					return Quest.draw({ seed = 11, expansions = { partySlots = 1 } }, "daily", 500 + i, master)
				end)).toBeTruthy()
				expect(differs(function(i)
					return Quest.draw({ seed = i, expansions = { partySlots = 1 } }, "daily", 500, master)
				end)).toBeTruthy()
				expect(differs(function(i)
					local m = Fixtures.master(function(d)
						d.Constants.calendarSeed = i
					end)
					return Quest.draw({ seed = 11, expansions = { partySlots = 1 } }, "daily", 500, m)
				end)).toBeTruthy()
				-- 乱数の回数（rngCounter）は使わない
				local s = newState()
				local counter = s.rngCounter
				Quest.refresh(s, T0, master)
				expect(s.rngCounter).toBe(counter)
			end
		)
		it(
			"D-153 日が変わったら入れ替え、同じ日は引き直さない。ウィークリーは週（月曜）まで続く",
			function()
				local s = newState()
				today(s)
				s.quests.daily.entries[1].progress = 1
				local weekly = Fixtures.clone(s.quests.weekly)
				Game.advance(s, ctx(T0 + 3600))
				expect(s.quests.daily.entries[1].progress).toBe(1) -- 同じ日は変わらない
				Game.advance(s, ctx(T0 + DAY))
				expect(s.quests.daily.dayIndex).toBe(Calendar.dayIndex(T0 + DAY))
				for _, e in s.quests.daily.entries do
					expect(e.progress).toBe(0)
				end
				expect(s.quests.weekly).toEqual(weekly) -- 木曜 → 金曜は同じ週
				Game.advance(s, ctx(T0 + 4 * DAY)) -- 2026-01-05 月曜
				expect(s.quests.weekly.weekIndex).toBe(weekly.weekIndex + 1)
			end
		)
		it(
			"D-179 探索の回数はオンライン中の出発で数える（Dispatch と自動再派遣）。留守番は数えない（D-161）",
			function()
				local s = newState()
				today(s)
				s.quests.daily.entries =
					{ { questId = "qst_daily_expeditions", target = 100, progress = 0, done = false } }
				s.quests.weekly.entries = {}
				exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" })
				expect(s.quests.daily.entries[1].progress).toBe(1)
				exec(s, { type = "SetAutoRepeat", partyIndex = 1, dungeonId = "dng_graveyard" })
				local e = Game.query.expeditionOf(s, 1)
				Game.advance(s, ctx(e.returnAt))
				expect(s.quests.daily.entries[1].progress).toBe(2) -- 自動再派遣の出発
				-- ログアウト中の留守番
				s.lastSavedAt = e.returnAt
				local before = s.quests.daily.entries[1].progress
				local events = Game.advance(s, ctx(e.returnAt + 3 * 3600, false))
				expect(#eventsOf(events, "AutoDispatched") > 0).toBeTruthy()
				expect(s.quests.daily.entries[1].progress).toBe(before)
			end
		)
		it("D-153 宝箱を開けた数・雇用・トレーニング・踏破・転生を数える", function()
			local s = newState()
			today(s)
			s.gold = 10 ^ 9
			s.quests.daily.entries = {
				{ questId = "qst_daily_chests", target = 100, progress = 0, done = false },
				{ questId = "qst_daily_hires", target = 100, progress = 0, done = false },
				{ questId = "qst_daily_trainings", target = 100, progress = 0, done = false },
				{ questId = "qst_daily_clears", target = 100, progress = 0, done = false },
			}
			s.quests.weekly.entries = { { questId = "qst_weekly_rebirths", target = 100, progress = 0, done = false } }
			Chest.add(s, "dng_graveyard", 1, 3)
			exec(s, { type = "OpenChests", pileKey = "dng_graveyard" })
			expect(s.quests.daily.entries[1].progress).toBe(3)
			exec(s, { type = "HireStart" })
			exec(s, { type = "HirePick", candidateIndex = 1 })
			exec(s, { type = "HireChoose", which = "current" })
			expect(s.quests.daily.entries[2].progress).toBe(1)
			local uid = s.parties[1].slots[1]
			exec(s, { type = "Train", adventurerUid = uid, sessions = 2 })
			expect(s.quests.daily.entries[3].progress).toBe(2)
			exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" })
			local e = Game.query.expeditionOf(s, 1)
			e.log.result = "clear"
			Game.advance(s, ctx(e.returnAt))
			expect(s.quests.daily.entries[4].progress).toBe(1)
			-- 転生
			local adv = s.adventurers[uid]
			adv.level = adv.levelCap
			expect(exec(s, { type = "RebirthStart", adventurerUid = uid }, e.returnAt).ok).toBeTruthy()
			expect(exec(s, { type = "RebirthChoose", which = "current" }, e.returnAt).ok).toBeTruthy()
			expect(s.quests.weekly.entries[1].progress).toBe(1)
		end)
		it(
			"D-191 トレーニングは行った回数で数える（1コマンドの回数ぶん。ゴールドが尽きて止まったら実際の回数）",
			function()
				local s = newState()
				today(s)
				s.gold = 10 ^ 9
				s.quests.daily.entries =
					{ { questId = "qst_daily_trainings", target = 1000, progress = 0, done = false } }
				s.quests.weekly.entries = {}
				local uid = s.parties[1].slots[1]
				expect(exec(s, { type = "Train", adventurerUid = uid, sessions = 3 }).ok).toBeTruthy()
				expect(s.quests.daily.entries[1].progress).toBe(3)
				expect(exec(s, { type = "Train", adventurerUid = uid, sessions = 1 }).ok).toBeTruthy()
				expect(s.quests.daily.entries[1].progress).toBe(4)
				-- ゴールドが2回分しかなければ2回で止まり、2回と数える
				local adv = s.adventurers[uid]
				local c1 = Game.query.trainingSessionCost(adv.level, master)
				s.gold = c1 * 2 + (c1 - 1) -- 2回目以降にレベルが上がっても足りるとは限らないので、実際の回数で確かめる
				local r = exec(s, { type = "Train", adventurerUid = uid, sessions = 50 })
				expect(r.ok).toBeTruthy()
				local done = r.events[1].sessions
				expect(done < 50).toBeTruthy()
				expect(s.quests.daily.entries[1].progress).toBe(4 + done)
			end
		)
		it("D-153 D-164 達成したら報酬を受け取り箱へ。全部達成でボーナス", function()
			local s = newState()
			today(s)
			s.inbox = {}
			s.quests.daily.entries = {
				{ questId = "qst_daily_expeditions", target = 1, progress = 0, done = false },
				{ questId = "qst_daily_chests", target = 2, progress = 0, done = false },
			}
			local r = exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" })
			local done = eventsOf(r.events, "QuestCompleted")
			expect(#done).toBe(1)
			expect(done[1].questId).toBe("qst_daily_expeditions")
			expect(#s.inbox).toBe(1)
			expect(s.inbox[1].source).toBe("quest")
			-- ゴールドは基準のダンジョン（未踏破なので古い墓地）× goldMult（D-190）
			expect(s.inbox[1].rewards.gold).toBe(
				math.floor(
					master.dungeons.dng_graveyard.rewardGoldBase * master.quests.qst_daily_expeditions.rewards.goldMult
				)
			)
			expect(s.quests.daily.bonusDone).toBe(false)
			-- 達成済みは数えない（量を超えない）
			exec(s, { type = "SetAutoRepeat", partyIndex = 1, dungeonId = nil })
			Chest.add(s, "dng_graveyard", 1, 5)
			local r2 = exec(s, { type = "OpenChests", pileKey = "dng_graveyard" })
			expect(s.quests.daily.entries[2].progress).toBe(2)
			expect(#eventsOf(r2.events, "QuestCompleted")).toBe(1)
			expect(#eventsOf(r2.events, "QuestBonus")).toBe(1)
			expect(s.quests.daily.bonusDone).toBe(true)
			expect(#s.inbox).toBe(3)
			expect(s.inbox[3].rewards.items).toEqual(K.questDailyBonus.items)
		end)
		it("D-161 留守中の帰還（踏破）はクエストに数えない", function()
			local s = newState()
			today(s)
			s.quests.daily.entries = { { questId = "qst_daily_clears", target = 10, progress = 0, done = false } }
			exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" })
			local e = Game.query.expeditionOf(s, 1)
			e.log.result = "clear"
			s.lastSavedAt = T0
			Game.advance(s, ctx(e.returnAt + 60, false))
			expect(s.quests.daily.entries[1].progress).toBe(0)
		end)
	end)

	describe("ログインボーナス（D-155, D-169）", function()
		it(
			"D-155 その日の最初のオンラインの advance で1日分を受け取り箱へ。同じ日は二度進めない",
			function()
				local s = newState()
				local events = Game.advance(s, ctx(T0))
				local lb = eventsOf(events, "LoginBonus")
				expect(#lb).toBe(1)
				expect(lb[1].day).toBe(1)
				expect(#s.inbox).toBe(1)
				expect(s.inbox[1].source).toBe("login")
				expect(s.inbox[1].rewards.gold).toBe(
					math.floor(master.dungeons.dng_graveyard.rewardGoldBase * master.loginBonus.days[1].goldMult) -- D-190
				)
				expect(s.login.day).toBe(2)
				expect(s.login.lastDayIndex).toBe(Calendar.dayIndex(T0))
				expect(#eventsOf(Game.advance(s, ctx(T0 + 3600)), "LoginBonus")).toBe(0)
				expect(Game.query.loginCalendar(s, T0 + 3600, master).receivedToday).toBe(true)
			end
		)
		it("D-155 留守の計算（offline の advance）では進めない", function()
			local s = newState()
			Game.advance(s, ctx(T0 + DAY, false))
			expect(s.login.lastDayIndex).toBe(-1)
			expect(#s.inbox).toBe(0)
		end)
		it("D-155 途切れても戻らない。7日目の次は1日目・次の周", function()
			local s = newState()
			local days = {}
			local now = T0
			for _ = 1, 8 do
				for _, e in eventsOf(Game.advance(s, ctx(now)), "LoginBonus") do
					table.insert(days, e.day)
				end
				now += 3 * DAY -- 2日空けても戻らない
			end
			expect(days).toEqual({ 1, 2, 3, 4, 5, 6, 7, 1 })
			expect(s.login.cycle).toBe(2)
			expect(s.login.day).toBe(2)
		end)
		it(
			"D-155 7日目はログイン用のユニーク（loginOrder の順に1周1人）。いなければレアな宝箱＋チケット",
			function()
				-- 本番データにはログイン用のユニークがいない（中身は未決：Q-025）→ fallback
				local s = newState()
				s.login.day = 7
				Game.advance(s, ctx(T0))
				local entry = s.inbox[#s.inbox]
				expect(entry.rewards.uniqueId).toBe(nil)
				expect(entry.rewards.items).toEqual(master.loginBonus.fallback.items)
				local fb = master.loginBonus.fallback.chests[1]
				expect(fb.pileKey).toBe("special:login")
				expect(fb.rank).toBe(3) -- レアな宝箱（D-155）
				expect(entry.rewards.chests).toEqual({ { pileKey = "special:login", rank = 3, count = fb.count } })
				-- ログイン用のユニークが2人いれば、1周目は1人目、2周目は2人目、3周目は一巡した後なので fallback
				local m = masterWithLoginUniques(2)
				local s2 = newState(1, m)
				local got = {}
				local now = T0
				for _ = 1, 21 do
					for _, e in eventsOf(Game.advance(s2, ctx(now, true, m)), "LoginBonus") do
						if e.day == 7 then
							table.insert(got, e.uniqueId or "fallback")
						end
					end
					now += DAY
				end
				expect(got).toEqual({ "uni_test_login_1", "uni_test_login_2", "fallback" })
			end
		)
		it(
			"D-155 D-176 ユニークも受け取り箱経由。持っている（届いている）ときは fallback",
			function()
				local m = masterWithLoginUniques(1)
				local s = newState(1, m)
				s.login.day = 7
				Game.advance(s, ctx(T0, true, m))
				expect(s.inbox[#s.inbox].rewards.uniqueId).toBe("uni_test_login_1")
				expect(rosterCount(s)).toBe(4) -- まだ加入していない
				-- 次の周（2周目）のユニークはいない（一巡した後）ので、カレンダーに出すユニークもない
				expect(Game.query.loginCalendar(s, T0, m).uniqueId).toBe(nil)
				exec(s, { type = "ClaimInbox" }, T0, m)
				expect(Inbox.hasUnique(s, "uni_test_login_1")).toBe(true)
				-- 持っているユニークの周が来たら fallback
				local s2 = newState(1, m)
				local uid = `adv_{s2.nextUid}`
				s2.nextUid += 1
				s2.adventurers[uid] = Hiring.newAdventurer(uid, {
					uniqueId = "uni_test_login_1",
					name = "x",
					gender = "f",
					appearanceId = "a",
					jobId = "job_mage",
					giftIds = {},
				}, { str = 1, mag = 1, agi = 1, dex = 1, hp = 20 }, T0, m)
				s2.login.day = 7
				Game.advance(s2, ctx(T0, true, m))
				expect(s2.inbox[#s2.inbox].rewards.uniqueId).toBe(nil)
				expect(s2.inbox[#s2.inbox].rewards.items).toEqual(m.loginBonus.fallback.items)
			end
		)
		it("D-155 ログイン用のユニークは雇用（特別な訪問者）に出さない", function()
			local m = Fixtures.master(function(d)
				d.Constants.specialVisitorChance = 1
				for _, u in d.Uniques do
					if u.acquire == "visitor" then
						u.acquire = "login"
						u.loginOrder = #u.name -- 重ならない番号
					end
				end
			end)
			local s = newState(1, m)
			for seed = 1, 20 do
				for _, c in Hiring.rollCandidates(s, Rng.new(seed), m, T0) do
					expect(c.kind).toBe("general")
				end
			end
		end)
		it(
			"D-155 D-169 Uniques の acquire は visitor・firstClear:<dng>・login だけ。loginOrder は重ならない",
			function()
				local e = errorsOf(function(d)
					d.Uniques[1].acquire = "guildLevel:10"
				end)
				expect(string.find(e, "Uniques[1].acquire", 1, true) ~= nil).toBeTruthy()
				local e2 = errorsOf(function(d)
					d.Uniques[1].acquire = "login"
					d.Uniques[1].loginOrder = 1
					d.Uniques[2].acquire = "login"
					d.Uniques[2].loginOrder = 1
				end)
				expect(string.find(e2, "loginOrder", 1, true) ~= nil).toBeTruthy()
				local e3 = errorsOf(function(d)
					d.Uniques[3].acquire = "firstClear:dng_nope"
				end)
				expect(string.find(e3, "Uniques[3].acquire", 1, true) ~= nil).toBeTruthy()
			end
		)
	end)

	describe("プレイ時間（D-154）", function()
		it(
			"D-154 オンラインの経過秒を足し、段階に届いたら受け取り箱へ（宝箱は special:playtime）",
			function()
				local s = newState()
				Game.advance(s, ctx(T0))
				s.inbox = {}
				local events = Game.advance(s, ctx(T0 + 5 * 60))
				local pr = eventsOf(events, "PlaytimeReward")
				expect(#pr).toBe(1)
				expect(pr[1].minutes).toBe(5)
				expect(s.playtime.seconds).toBe(300)
				expect(s.playtime.claimedSteps).toBe(1)
				expect(s.inbox[1].source).toBe("playtime")
				-- まとめて進めば届いた段階を全部
				local events2 = Game.advance(s, ctx(T0 + 31 * 60))
				local mins = {}
				for _, e in eventsOf(events2, "PlaytimeReward") do
					table.insert(mins, e.minutes)
				end
				expect(mins).toEqual({ 10, 20, 30 })
				local sawPlaytimeChest = false
				for _, entry in s.inbox do
					for _, c in entry.rewards.chests or {} do
						expect(c.pileKey).toBe("special:playtime")
						sawPlaytimeChest = true
					end
				end
				expect(sawPlaytimeChest).toBeTruthy()
			end
		)
		it("D-154 1日2時間まで。それより先の段階はない", function()
			local s = newState()
			Game.advance(s, ctx(T0))
			Game.advance(s, ctx(T0 + 5 * 3600))
			expect(s.playtime.seconds).toBe(K.playtimeDailyCapSeconds)
			expect(s.playtime.claimedSteps).toBe(#master.playtimeRewards)
			expect(Game.query.playtime(s, master).nextMinutes).toBe(nil)
		end)
		it(
			"D-154 留守の時間は数えない。ログイン直後の最初の advance も足さない。ログアウトではリセットしない",
			function()
				local s = newState()
				Game.advance(s, ctx(T0))
				Game.advance(s, ctx(T0 + 600))
				expect(s.playtime.seconds).toBe(600)
				s.lastSavedAt = T0 + 600 -- ログアウト
				Game.advance(s, ctx(T0 + 3 * 3600, false)) -- ログイン（留守の計算）
				expect(s.playtime.seconds).toBe(600)
				Game.advance(s, ctx(T0 + 3 * 3600)) -- ログイン直後の最初のオンラインの advance
				expect(s.playtime.seconds).toBe(600)
				Game.advance(s, ctx(T0 + 3 * 3600 + 60))
				expect(s.playtime.seconds).toBe(660)
			end
		)
		it("D-154 D-168 日の区切りで 0 に戻し、区切りより後の分だけ数える", function()
			local s = newState()
			Game.advance(s, ctx(T0 + DAY - 600, false)) -- 日の終わりにログイン
			Game.advance(s, ctx(T0 + DAY - 600))
			Game.advance(s, ctx(T0 + DAY - 300))
			expect(s.playtime.seconds).toBe(300)
			Game.advance(s, ctx(T0 + DAY + 120))
			expect(s.playtime.dayIndex).toBe(Calendar.dayIndex(T0 + DAY))
			expect(s.playtime.seconds).toBe(120)
			expect(s.playtime.claimedSteps).toBe(0)
		end)
	end)

	describe("セーブの移行 version 7 → 8（M7b-4）", function()
		it(
			"D-164 D-153 D-155 D-154 受け取り箱・クエスト・ログインボーナス・プレイ時間を初期値で足す",
			function()
				local s = newState()
				s.version = 7
				s.quests, s.login, s.playtime, s.inbox = nil, nil, nil, nil
				Migration.migrate(s, master)
				expect(s.version).toBe(Migration.CURRENT) -- 7 → 8 → 以降の版（v8 → 9 は Social.spec、v9 → 10 は MapEvent.spec）
				expect(Migration.CURRENT >= 8).toBeTruthy()
				expect(s.quests).toEqual(Quest.newState())
				expect(s.login).toEqual({ lastDayIndex = -1, day = 1, cycle = 1 })
				expect(s.playtime).toEqual({ dayIndex = -1, seconds = 0, claimedSteps = 0 })
				expect(s.inbox).toEqual({})
				-- 次のオンラインの advance で1日目・今日のクエスト
				Game.advance(s, ctx(T0))
				expect(s.login.day).toBe(2)
				expect(#s.quests.daily.entries).toBe(K.questDailyCount)
				-- JSON にして戻しても動く
				local decoded = serde.decode("json", serde.encode("json", s))
				Game.advance(decoded, ctx(T0 + DAY))
				expect(decoded.login.day).toBe(3)
			end
		)
		it("D-164 新規のセーブは version 8 の項目を初期値で持つ", function()
			local s = newState()
			expect(s.version).toBe(Migration.CURRENT)
			expect(s.inbox).toEqual({})
			expect(s.login).toEqual({ lastDayIndex = -1, day = 1, cycle = 1 })
		end)
	end)
end
