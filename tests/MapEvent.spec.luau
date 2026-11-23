--!strict
-- マップイベント（M7b-4 後半・担当B）：時間帯（D-152）、レアダンジョン（D-152, D-171, D-185）、
-- レイドボス（D-152, D-179, D-164）、旅の商人（D-152, D-167, D-175, D-179）、留守中（D-161）、セーブの移行
local serde = require("@lune/serde")

local Chest = require("../src/core/Chest")
local CommandText = require("../src/core/CommandText")
local Expedition = require("../src/core/Expedition")
local Game = require("../src/core/Game")
local Hiring = require("../src/core/Hiring")
local Inventory = require("../src/core/Inventory")
local MapEvent = require("../src/core/MapEvent")
local MasterData = require("../src/core/MasterData")
local Merchant = require("../src/core/Merchant")
local Migration = require("../src/core/Migration")
local Party = require("../src/core/Party")
local Protocol = require("../src/core/Protocol")
local Raid = require("../src/core/Raid")
local Data = require("../src/data")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1767225600 -- 2026-01-01 00:00 UTC

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local K = master.K

	local function ctx(now: number, online: boolean?, m: any?)
		return { now = now, master = m or master, online = if online == nil then true else online }
	end
	local function exec(s: any, cmd: any, now: number, m: any?): any
		return Game.execute(s, cmd, ctx(now, true, m))
	end
	local function newState(seed: number?, m: any?)
		return Game.newState(m or master, seed or 1, T0)
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
	-- T0 以降で最初の、その種類の時間帯
	local function findSlot(kind: string, m: any?): number
		local mm = m or master
		local slot = MapEvent.slotOf(T0, mm.K)
		while MapEvent.eventAt(slot, mm).kind ~= kind do
			slot += 1
		end
		return slot
	end
	local function startOf(slot: number): number
		return MapEvent.startOf(slot, K)
	end
	-- パーティ2を足し、新しく雇った4人を入れる
	local function addParty(s: any, m: any?)
		local mm = m or master
		local i = #s.parties + 1
		s.parties[i] = { index = i, slots = Party.newSlots(), autoRepeat = nil }
		s.expansions.partySlots = i
		for slot = 1, 4 do
			local uid = `adv_{s.nextUid}`
			s.nextUid += 1
			s.adventurers[uid] = Hiring.newAdventurer(uid, {
				name = "x",
				gender = "m",
				appearanceId = "chr_m_nor_phy_01",
				jobId = "job_warrior",
				giftIds = {},
			}, { str = 20, mag = 1, agi = 10, dex = 5, hp = 60 }, T0, mm)
			s.parties[i].slots[slot] = uid
		end
		return i
	end
	local function clearUpTo(s: any, n: number)
		for i = 1, n do
			s.clearedDungeons[master.dungeonList[i].id] = true
			s.unlockedDungeons[master.dungeonList[i].id] = true
		end
	end
	-- 受け取り箱のうちレイドの件（ログインボーナスなども届くので分ける）
	local function raidInbox(s: any): { any }
		local out = {}
		for _, entry in s.inbox do
			if entry.source == "raid" then
				table.insert(out, entry)
			end
		end
		return out
	end
	local function expeditionOf(s: any, partyIndex: number): any
		return Game.query.expeditionOf(s, partyIndex)
	end

	describe("マップイベントの時間帯（D-152、06章 §12）", function()
		it("D-152 5分ごとに1つ。出発できるのは出てから3分間、1分前に予告", function()
			local slot = MapEvent.slotOf(T0 + 10, K)
			expect(slot).toBe(math.floor((T0 + 10) / K.mapEventIntervalSeconds))
			local q = Game.query.mapEvent(startOf(slot) + 10, master)
			expect(q.current.eventSlot).toBe(slot)
			expect(q.current.open).toBe(true)
			expect(q.current.closesIn).toBe(K.mapEventWindowSeconds - 10)
			expect(q.next).toBe(nil) -- 予告の前
			expect(q.nextAt).toBe(startOf(slot + 1))
			-- 3分を過ぎたら締め切り、残り1分で次の予告
			local q2 = Game.query.mapEvent(startOf(slot) + K.mapEventWindowSeconds, master)
			expect(q2.current.open).toBe(false)
			expect(q2.current.closesIn).toBe(0)
			expect(q2.next).toBe(nil)
			local q3 = Game.query.mapEvent(startOf(slot + 1) - K.mapEventNoticeSeconds, master)
			expect(q3.next.eventSlot).toBe(slot + 1)
			expect(q3.next.startsIn).toBe(K.mapEventNoticeSeconds)
			expect(q3.next.kind).toBe(MapEvent.eventAt(slot + 1, master).kind)
		end)
		it(
			"D-152 種類・場所・時刻は calendarSeed と時間帯の番号で全員共通（プレイヤーの seed に依らない）",
			function()
				local slot = MapEvent.slotOf(T0, K)
				for i = 0, 20 do
					local a = MapEvent.eventAt(slot + i, master)
					local b = MapEvent.eventAt(slot + i, master)
					expect(a).toEqual(b)
					expect(master.mapEventKinds[a.kindId] ~= nil).toBe(true)
				end
				-- calendarSeed を変えると並びが変わる
				local other = Fixtures.master(function(d)
					d.Constants.calendarSeed = 12345
				end)
				local same = 0
				for i = 0, 40 do
					if MapEvent.eventAt(slot + i, master).kind == MapEvent.eventAt(slot + i, other).kind then
						same += 1
					end
				end
				expect(same < 41).toBe(true)
			end
		)
		it("D-152 3種類（レアダンジョン・レイドボス・旅の商人）がどれも出る", function()
			local seen = {}
			local slot = MapEvent.slotOf(T0, K)
			for i = 0, 200 do
				seen[MapEvent.eventAt(slot + i, master).kind] = true
			end
			expect(seen.rareDungeon).toBe(true)
			expect(seen.raid).toBe(true)
			expect(seen.merchant).toBe(true)
		end)
		it("D-152 種類の割合が 0 の種類は出ない", function()
			local m = Fixtures.master(function(d)
				for _, e in d.Constants.mapEventKindWeights do
					e.weight = if e.id == "mev_merchant" then 1 else 0
				end
			end)
			local slot = MapEvent.slotOf(T0, m.K)
			for i = 0, 30 do
				expect(MapEvent.eventAt(slot + i, m).kind).toBe("merchant")
			end
		end)
	end)

	describe("DispatchEvent の受付（D-152, D-179）", function()
		it(
			"D-152 締め切り後・過ぎた時間帯は EVENT_WINDOW_CLOSED、まだの時間帯と商人は EVENT_NOT_ACTIVE",
			function()
				local slot = findSlot("rareDungeon")
				local s = newState()
				expect(exec(s, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot }, startOf(slot) - 1).error).toBe(
					"EVENT_NOT_ACTIVE"
				)
				expect(
					exec(
						s,
						{ type = "DispatchEvent", partyIndex = 1, eventSlot = slot },
						startOf(slot) + K.mapEventWindowSeconds
					).error
				).toBe("EVENT_WINDOW_CLOSED")
				expect(
					exec(s, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot }, startOf(slot + 1) + 1).error
				).toBe("EVENT_WINDOW_CLOSED")
				local m = findSlot("merchant")
				expect(exec(s, { type = "DispatchEvent", partyIndex = 1, eventSlot = m }, startOf(m) + 1).error).toBe(
					"EVENT_NOT_ACTIVE"
				)
				-- 締め切りの1秒前は出発できる
				expect(
					exec(
						s,
						{ type = "DispatchEvent", partyIndex = 1, eventSlot = slot },
						startOf(slot) + K.mapEventWindowSeconds - 1
					).ok
				).toBe(true)
			end
		)
		it("D-152 探索中・空のパーティは出発できない", function()
			local slot = findSlot("rareDungeon")
			local s = newState()
			expect(exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, startOf(slot)).ok).toBe(
				true
			)
			expect(exec(s, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot }, startOf(slot)).error).toBe(
				"PARTY_BUSY"
			)
			local s2 = newState()
			s2.parties[1].slots = Party.newSlots()
			expect(exec(s2, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot }, startOf(slot)).error).toBe(
				"PARTY_EMPTY"
			)
		end)
	end)

	describe("レアダンジョン（D-152, D-171, D-185）", function()
		it(
			"D-152 D-171 強さは踏破済みの一番深いダンジョン、宝箱の山は1段上の special:rare",
			function()
				local s = newState()
				expect(MapEvent.rareDungeonTarget(s, master)).toEqual({
					dungeonId = "dng_graveyard",
					pileKey = "special:rare:dng_graveyard",
				}) -- まだどこも踏破していない（要確認）
				clearUpTo(s, 2)
				expect(MapEvent.rareDungeonTarget(s, master)).toEqual({
					dungeonId = "dng_ruins",
					pileKey = "special:rare:dng_tower",
				})
			end
		)
		it("D-185 天空の玉座を踏破した後は相当ダンジョンも天空の玉座のまま", function()
			local s = newState()
			clearUpTo(s, #master.dungeonList)
			expect(MapEvent.rareDungeonTarget(s, master)).toEqual({
				dungeonId = "dng_sky_throne",
				pileKey = "special:rare:dng_sky_throne",
			})
		end)
		it("D-152 出発し、宝箱は special:rare の山に入る。日替わりの特性は当てない", function()
			local slot = findSlot("rareDungeon")
			local s = newState()
			clearUpTo(s, 1)
			local r = exec(s, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot }, startOf(slot) + 5)
			expect(r.ok).toBe(true)
			local ev = eventsOf(r.events, "EventDispatched")[1]
			expect(ev.kind).toBe("rareDungeon")
			expect(ev.pileKey).toBe("special:rare:dng_ruins")
			local e = expeditionOf(s, 1)
			expect(e.dungeonId).toBe("dng_graveyard")
			expect(e.eventSlot).toBe(slot)
			expect(e.dailyTraitId).toBe(nil)
			expect(e.log.chestMult).toBe(K.rareDungeonChestMult)
			local n = #e.log.rewards.chests
			Game.advance(s, ctx(e.returnAt))
			expect(Chest.pileTotal(s, "special:rare:dng_ruins")).toBe(n)
			expect(Chest.pileTotal(s, "dng_graveyard")).toBe(0)
		end)
		it(
			"D-152 D-173 宝箱の数は rareDungeonChestMult 倍（端数は確率で切り上げ）。倍率がなければ乱数の消費は今までと同じ",
			function()
				local s = newState()
				local snaps = Party.snapshots(s, 1, master)
				local base, more, total = 0, 0, 0
				for seed = 1, 200 do
					local input = { seed = seed, departAt = T0, dungeonId = "dng_graveyard", members = snaps }
					local plain = Expedition.simulate(input, master)
					local withMult = table.clone(input)
					withMult.chestMult = 1.5
					local rare = Expedition.simulate(withMult, master)
					-- 増やす前の宝箱は同じ（倍率の判定は最後）
					for i, c in plain.rewards.chests do
						expect(rare.rewards.chests[i].rank).toBe(c.rank)
					end
					expect(#rare.rewards.chests).toBe(#plain.rewards.chests + (rare.eventChests or 0))
					expect(#rare.traitChestSources).toBe(rare.eventChests)
					base += #plain.rewards.chests
					more += rare.eventChests or 0
					total += #rare.rewards.chests
					expect(plain.eventChests).toBe(nil)
				end
				-- 1個あたり 50% で +1
				expect(more / base > 0.4 and more / base < 0.6).toBe(true)
				expect(total).toBe(base + more)
				-- 2倍なら必ずちょうど2倍
				local log2 = Expedition.simulate(
					{ seed = 3, departAt = T0, dungeonId = "dng_graveyard", members = snaps, chestMult = 2 },
					master
				)
				expect(log2.eventChests * 2).toBe(#log2.rewards.chests)
			end
		)
		it("D-152 1パーティ1回まで。別のパーティは出発できる", function()
			local slot = findSlot("rareDungeon")
			local s = newState()
			local p2 = addParty(s)
			local at = startOf(slot)
			expect(exec(s, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot }, at).ok).toBe(true)
			-- 同じパーティは同じ時間帯に2回目は出られない（探索中より先に判定する）
			expect(exec(s, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot }, at + 1).error).toBe(
				"EVENT_ALREADY_JOINED"
			)
			expect(exec(s, { type = "DispatchEvent", partyIndex = p2, eventSlot = slot }, at + 1).ok).toBe(true)
			expect(s.rareDungeonSlots["1"]).toBe(slot)
			-- 次のレアダンジョンの時間帯では、古い分は捨てられてまた出られる
			local slot2 = slot + 1
			while MapEvent.eventAt(slot2, master).kind ~= "rareDungeon" do
				slot2 += 1
			end
			local s2 = newState()
			s2.rareDungeonSlots = { ["1"] = slot }
			expect(exec(s2, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot2 }, startOf(slot2)).ok).toBe(
				true
			)
			expect(s2.rareDungeonSlots).toEqual({ ["1"] = slot2 })
		end)
		it("D-152 同じ時間帯に2回目は EVENT_ALREADY_JOINED", function()
			local slot = findSlot("rareDungeon")
			local s = newState()
			s.rareDungeonSlots = { ["1"] = slot }
			expect(exec(s, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot }, startOf(slot)).error).toBe(
				"EVENT_ALREADY_JOINED"
			)
		end)
		it("D-152 出発したパーティはイベントが消えても最後まで探索する", function()
			local slot = findSlot("rareDungeon")
			local s = newState()
			local at = startOf(slot) + K.mapEventWindowSeconds - 1
			expect(exec(s, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot }, at).ok).toBe(true)
			local e = expeditionOf(s, 1)
			expect(e.returnAt > MapEvent.closeOf(slot, K)).toBe(true)
			Game.advance(s, ctx(MapEvent.closeOf(slot, K) + 1))
			expect(expeditionOf(s, 1) ~= nil).toBe(true)
			local ev = eventsOf(Game.advance(s, ctx(e.returnAt)), "ExpeditionReturned")[1]
			expect(ev.eventSlot).toBe(slot)
			expect(ev.pileKey).toBe("special:rare:dng_graveyard")
		end)
		it("D-179 DispatchEvent もクエストの探索の回数に数える", function()
			local slot = findSlot("rareDungeon")
			local s = newState()
			Game.advance(s, ctx(startOf(slot)))
			local before = {}
			for i, q in s.quests.daily.entries do
				before[i] = q.progress
			end
			expect(exec(s, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot }, startOf(slot)).ok).toBe(true)
			for i, q in s.quests.daily.entries do
				local row = master.quests[q.questId]
				if row.kind == "expeditions" then
					expect(q.progress).toBe(before[i] + 1)
				else
					expect(q.progress).toBe(before[i])
				end
			end
		end)
		it(
			"D-171 rareChestEffectMinRarity のないダンジョンのレアダンジョンの山は開けられない（今の作り）",
			function()
				local s = newState()
				Chest.add(s, "special:rare:dng_ruins", 1, 3)
				expect(exec(s, { type = "OpenChests", pileKey = "special:rare:dng_ruins" }, T0).error).toBe(
					"PILE_NOT_FOUND"
				)
			end
		)
	end)

	describe("レイドボス（D-152, D-179, D-164）", function()
		-- HP を決めやすくしたマスターデータ
		local function raidMaster(hpMult: number): any
			return Fixtures.master(function(d)
				d.Constants.raidHpMult = hpMult
				d.Constants.raidHpSpread = { min = 1, max = 1 }
			end)
		end
		it(
			"D-152 HP はプレイヤーごと（seed と時間帯）。式は仮：一番深い踏破ダンジョンの base.hp × 倍率 × ばらつき",
			function()
				local slot = findSlot("raid")
				local a, b = newState(1), newState(2)
				local hpA = Raid.hp(a, slot, master)
				expect(Raid.hp(a, slot, master)).toBe(hpA)
				local d = master.dungeonList[1]
				expect(hpA >= math.floor(d.base.hp * K.raidHpMult * K.raidHpSpread.min)).toBe(true)
				expect(hpA <= math.floor(d.base.hp * K.raidHpMult * K.raidHpSpread.max)).toBe(true)
				local differs = false
				for i = 0, 10 do
					differs = differs or Raid.hp(a, slot + i, master) ~= Raid.hp(b, slot + i, master)
				end
				expect(differs).toBe(true)
				local m = raidMaster(2)
				clearUpTo(a, 3)
				expect(Raid.hp(a, slot, m)).toBe(math.floor(master.dungeonList[3].base.hp * 2))
			end
		)
		it(
			"D-152 ダメージは出発時に計算し（全員の攻撃力の合計 × raidDamagePerAtk）、到着時刻に入れる",
			function()
				local m = raidMaster(100)
				local slot = findSlot("raid", m)
				local s = newState(1, m)
				local snaps = Party.snapshots(s, 1, m)
				local atk = 0
				for _, sn in snaps do
					atk += sn.atk
				end
				local at = startOf(slot) + 3
				local r = exec(s, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot }, at, m)
				expect(r.ok).toBe(true)
				local e = expeditionOf(s, 1)
				expect(e.raidDamage).toBe(math.floor(atk * m.K.raidDamagePerAtk))
				expect(e.arriveAt).toBe(at + m.K.raidTravelSeconds)
				expect(e.returnAt).toBe(at + m.K.raidTravelSeconds * 2)
				-- 出発後に装備を外しても、ダメージは変わらない（結果は出発時に決まる）
				local adv = s.adventurers[s.parties[1].slots[1]]
				adv.equipment.weapon = nil
				Game.advance(s, ctx(e.arriveAt - 1, true, m))
				expect(s.raid.damage).toBe(0)
				local evs = Game.advance(s, ctx(e.arriveAt, true, m))
				expect(s.raid.damage).toBe(e.raidDamage)
				expect(eventsOf(evs, "RaidHit")[1].damage).toBe(e.raidDamage)
				expect(s.raid.defeated).toBe(false)
				expect(#raidInbox(s)).toBe(0) -- 討伐できなければ宝箱はない
				Game.advance(s, ctx(e.returnAt, true, m))
				expect(expeditionOf(s, 1)).toBe(nil)
			end
		)
		it(
			"D-179 合計が HP を超えたら討伐。参加したパーティごとにレアな宝箱を1つ受け取り箱へ",
			function()
				local m0 = raidMaster(1)
				local slot = findSlot("raid", m0)
				local s0 = newState(1, m0)
				local p2 = addParty(s0, m0)
				local d1 = Raid.damage(Party.snapshots(s0, 1, m0), m0.K)
				local d2 = Raid.damage(Party.snapshots(s0, p2, m0), m0.K)
				-- 1パーティでは届かず、2パーティで超える HP にする
				local hp = math.max(d1, d2) + 1
				local m = Fixtures.master(function(d)
					d.Constants.raidHpMult = hp / d.Dungeons[1].base.hp
					d.Constants.raidHpSpread = { min = 1, max = 1 }
				end)
				local s = newState(1, m)
				addParty(s, m)
				expect(Raid.hp(s, slot, m) <= d1 + d2 - 1).toBe(true)
				local at = startOf(slot)
				expect(exec(s, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot }, at, m).ok).toBe(true)
				expect(exec(s, { type = "DispatchEvent", partyIndex = p2, eventSlot = slot }, at + 30, m).ok).toBe(true)
				-- 同じパーティは2回出られない
				expect(exec(s, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot }, at + 31, m).error).toBe(
					"EVENT_ALREADY_JOINED"
				)
				local evs = Game.advance(s, ctx(at + m.K.raidTravelSeconds, true, m))
				expect(s.raid.defeated).toBe(false)
				expect(#raidInbox(s)).toBe(0)
				evs = Game.advance(s, ctx(at + 30 + m.K.raidTravelSeconds, true, m))
				expect(s.raid.defeated).toBe(true)
				expect(#eventsOf(evs, "RaidDefeated")).toBe(1)
				expect(#eventsOf(evs, "RaidReward")).toBe(2)
				expect(#raidInbox(s)).toBe(2)
				for _, entry in raidInbox(s) do
					expect(entry.rewards.chests[1].pileKey).toBe("special:raid")
					expect(entry.rewards.chests[1].count).toBe(1)
				end
				local claimed = exec(s, { type = "ClaimInbox" }, at + 200, m)
				expect(claimed.ok).toBe(true)
				expect(Chest.pileTotal(s, "special:raid")).toBe(2)
			end
		)
		it("D-179 討伐の後に到着したパーティにも宝箱が1つ", function()
			local m = raidMaster(0.01)
			local slot = findSlot("raid", m)
			local s = newState(1, m)
			local p2 = addParty(s, m)
			local at = startOf(slot)
			exec(s, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot }, at, m)
			Game.advance(s, ctx(at + m.K.raidTravelSeconds, true, m))
			expect(s.raid.defeated).toBe(true)
			expect(#raidInbox(s)).toBe(1)
			expect(exec(s, { type = "DispatchEvent", partyIndex = p2, eventSlot = slot }, at + 100, m).ok).toBe(true)
			local evs = Game.advance(s, ctx(at + 100 + m.K.raidTravelSeconds, true, m))
			expect(#eventsOf(evs, "RaidDefeated")).toBe(0)
			expect(#raidInbox(s)).toBe(2)
		end)
		it(
			"D-152 レイドの状態は今の時間帯の分だけ。query は今の時間帯の HP の見込みを返す",
			function()
				local slot = findSlot("raid")
				local s = newState()
				s.raid = { eventSlot = slot - 1, hp = 1, damage = 5, defeated = true, parties = { 1 }, arrived = 1 }
				local q = Game.query.raid(s, slot, master)
				expect(q.damage).toBe(0)
				expect(q.defeated).toBe(false)
				expect(q.hp).toBe(Raid.hp(s, slot, master))
				expect(exec(s, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot }, startOf(slot)).ok).toBe(
					true
				)
				expect(s.raid.eventSlot).toBe(slot)
				expect(s.raid.parties).toEqual({ 1 })
				expect(Game.query.raid(s, findSlot("merchant"), master)).toBe(nil)
			end
		)
		it("D-152 レイドの帰還は踏破に数えず、宝箱の山にも入れない", function()
			local slot = findSlot("raid")
			local s = newState()
			local at = startOf(slot)
			exec(s, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot }, at)
			local e = expeditionOf(s, 1)
			local evs = Game.advance(s, ctx(e.returnAt))
			expect(#eventsOf(evs, "RaidReturned")).toBe(1)
			expect(#eventsOf(evs, "ExpeditionReturned")).toBe(0)
			expect(next(s.clearedDungeons)).toBe(nil)
			expect(Chest.total(s)).toBe(0)
		end)
	end)

	describe("旅の商人（D-152, D-167, D-175, D-179）", function()
		it(
			"D-152 品はプレイヤーごとに3〜5点。同じ seed・時間帯なら同じ（rngCounter を進めない）",
			function()
				local slot = findSlot("merchant")
				local s = newState(1)
				local counter = s.rngCounter
				local g = Merchant.goods(s, slot, master)
				expect(#g >= K.merchantItemCount.min and #g <= K.merchantItemCount.max).toBe(true)
				expect(Merchant.goods(s, slot, master)).toEqual(g)
				expect(s.rngCounter).toBe(counter)
				local differs = false
				for seed = 2, 6 do
					differs = differs or not Protocol.deepEqual(Merchant.goods(newState(seed), slot, master), g)
				end
				expect(differs).toBe(true)
			end
		)
		it(
			"D-152 アイテムレベル・レアリティは踏破済みの範囲まで。量を管理している品は売らない",
			function()
				local s = newState(7)
				clearUpTo(s, 3)
				local maxTier = master.dungeonList[3].tier
				local maxRarity = #master.dungeonList[3].chestRarityWeights
				local slot = MapEvent.slotOf(T0, K)
				for i = 0, 60 do
					for _, g in Merchant.goods(s, slot + i, master) do
						expect(g.item.itemLevel <= maxTier).toBe(true)
						expect(g.item.rarity <= maxRarity).toBe(true)
						expect(master.equipmentBases[g.item.baseId] ~= nil).toBe(true) -- 装備だけ
						expect(s.clearedDungeons[g.dungeonId]).toBe(true)
					end
				end
			end
		)
		it("D-152 価格は売却額 × merchantPriceMult、グレード・修飾語で上がる", function()
			local item = { baseId = "eq_wpn_sword", rarity = 2, grade = 2, itemLevel = 3 }
			local sell = Inventory.equipmentSellPrice(item, master)
			expect(Merchant.price(item, master)).toBe(
				math.floor(sell * K.merchantPriceMult * (1 + K.merchantGradeCoef * 2))
			)
			local modded = table.clone(item)
			modded.modifierId = "mod_exorcism"
			expect(Merchant.price(modded, master)).toBe(
				math.floor(sell * K.merchantPriceMult * (1 + K.merchantGradeCoef * 2) * (1 + K.merchantModifierCoef))
			)
			expect(Merchant.price(modded, master) > Merchant.price(item, master)).toBe(true)
		end)
		it(
			"D-152 D-175 買った装備は fromMerchant で倉庫へ。購入済みは状態に持ち、2回は買えない",
			function()
				local slot = findSlot("merchant")
				local s = newState()
				s.gold = 10 ^ 9
				local g = Merchant.goods(s, slot, master)
				local r = exec(s, { type = "BuyFromMerchant", eventSlot = slot, itemIndex = 1 }, startOf(slot) + 1)
				expect(r.ok).toBe(true)
				local ev = eventsOf(r.events, "MerchantBought")[1]
				local eq = s.equipment[ev.equipmentUid]
				expect(eq.fromMerchant).toBe(true)
				expect(eq.baseId).toBe(g[1].item.baseId)
				expect(eq.rarity).toBe(g[1].item.rarity)
				expect(s.gold).toBe(10 ^ 9 - g[1].price)
				expect(s.merchant.eventSlot).toBe(slot)
				expect(s.merchant.bought[1]).toBe(true)
				expect(#s.merchant.bought).toBe(#g)
				expect(exec(s, { type = "BuyFromMerchant", eventSlot = slot, itemIndex = 1 }, startOf(slot) + 2).error).toBe(
					"ALREADY_BOUGHT"
				)
				local q = Game.query.merchant(s, slot, startOf(slot) + 2, master)
				expect(q.items[1].bought).toBe(true)
				expect(q.items[2].bought).toBe(false)
				expect(q.open).toBe(true)
				-- 一括売却で売らない（D-175）
				expect(Inventory.isWeakForBulkSell(s, eq, master)).toBe(false)
			end
		)
		it(
			"D-179 買えるのは3分間。締め切り後は EVENT_WINDOW_CLOSED、商人でない時間帯は EVENT_NOT_ACTIVE",
			function()
				local slot = findSlot("merchant")
				local s = newState()
				s.gold = 10 ^ 9
				expect(
					exec(
						s,
						{ type = "BuyFromMerchant", eventSlot = slot, itemIndex = 1 },
						startOf(slot) + K.mapEventWindowSeconds
					).error
				).toBe("EVENT_WINDOW_CLOSED")
				local raid = findSlot("raid")
				expect(exec(s, { type = "BuyFromMerchant", eventSlot = raid, itemIndex = 1 }, startOf(raid)).error).toBe(
					"EVENT_NOT_ACTIVE"
				)
				expect(exec(s, { type = "BuyFromMerchant", eventSlot = slot, itemIndex = 99 }, startOf(slot)).error).toBe(
					"ITEM_NOT_FOUND"
				)
			end
		)
		it("D-152 お金が足りない・倉庫がいっぱいなら買えない", function()
			local slot = findSlot("merchant")
			local s = newState()
			s.gold = 0
			expect(exec(s, { type = "BuyFromMerchant", eventSlot = slot, itemIndex = 1 }, startOf(slot)).error).toBe(
				"NOT_ENOUGH_GOLD"
			)
			s.gold = 10 ^ 9
			s.expansions.warehouseSize = Inventory.warehouseUsage(s)
			expect(exec(s, { type = "BuyFromMerchant", eventSlot = slot, itemIndex = 1 }, startOf(slot)).error).toBe(
				"WAREHOUSE_FULL"
			)
		end)
		it(
			"D-152 3分間のうちに新しく踏破しても、最初に買った後の品ぞろえは変わらない",
			function()
				local slot = findSlot("merchant")
				local s = newState()
				s.gold = 10 ^ 9
				local before = Merchant.goods(s, slot, master)
				exec(s, { type = "BuyFromMerchant", eventSlot = slot, itemIndex = 1 }, startOf(slot))
				clearUpTo(s, 5)
				expect(Merchant.goods(s, slot, master)).toEqual(before)
			end
		)
	end)

	describe("留守中（D-161）", function()
		it(
			"D-161 留守番の自動再派遣はマップイベントに出ない。出発済みのレイドのダメージは入る",
			function()
				local slot = findSlot("raid")
				local s = newState()
				local at = startOf(slot)
				exec(s, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot }, at)
				s.parties[1].autoRepeat = { dungeonId = "dng_graveyard" }
				s.lastSavedAt = at + 1
				Game.advance(s, ctx(at + 3 * 3600, false))
				expect(s.raid.arrived).toBe(1)
				for _, e in s.expeditions do
					expect(e.eventSlot).toBe(nil)
					expect(e.offline).toBe(true)
				end
				expect(s.merchant).toBe(nil)
			end
		)
	end)

	describe("通信・テキスト（D-152）", function()
		it("D-152 Protocol は DispatchEvent・BuyFromMerchant の形を検証する", function()
			expect((Protocol.validateCommand({ type = "DispatchEvent", partyIndex = 1, eventSlot = 5900000 }))).toBe(
				true
			)
			expect((Protocol.validateCommand({ type = "BuyFromMerchant", eventSlot = 5900000, itemIndex = 2 }))).toBe(
				true
			)
			expect((Protocol.validateCommand({ type = "DispatchEvent", partyIndex = 1 }))).toBe(false)
			expect((Protocol.validateCommand({ type = "BuyFromMerchant", eventSlot = 1.5, itemIndex = 1 }))).toBe(false)
		end)
		it("D-152 CommandText：eventgo <n> [時間帯]・buy <番号> [時間帯]", function()
			expect(CommandText.parse("eventgo 2 100")).toEqual({
				type = "DispatchEvent",
				partyIndex = 2,
				eventSlot = 100,
			})
			expect(CommandText.parse("eventgo 1")).toEqual({ type = "DispatchEvent", partyIndex = 1 })
			expect(CommandText.parse("buy 3")).toEqual({ type = "BuyFromMerchant", itemIndex = 3 })
		end)
		it("D-152 Protocol.view は商人・レイドの状態を JSON にして送れる", function()
			local slot = findSlot("raid")
			local s = newState()
			exec(s, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot }, startOf(slot))
			local v = Protocol.view(s, master)
			expect(v.raid.eventSlot).toBe(slot)
			local decoded = serde.decode("json", serde.encode("json", s))
			Game.advance(decoded, ctx(startOf(slot) + 1000))
			expect(decoded.raid.arrived).toBe(1)
		end)
	end)

	describe("セーブの移行（M7b-4 後半・担当B）", function()
		it(
			"D-152 D-175 旧版のセーブはイベントの状態なし・商人の印なしのまま今の版になる",
			function()
				local s = newState()
				s.version = Migration.CURRENT - 1
				Migration.migrate(s, master)
				expect(s.version).toBe(Migration.CURRENT)
				expect(s.merchant).toBe(nil)
				expect(s.raid).toBe(nil)
				expect(s.rareDungeonSlots).toBe(nil)
				for _, e in s.equipment do
					expect(e.fromMerchant).toBe(nil)
				end
				-- 移行後もイベントに出られる
				local slot = findSlot("rareDungeon")
				expect(exec(s, { type = "DispatchEvent", partyIndex = 1, eventSlot = slot }, startOf(slot)).ok).toBe(
					true
				)
			end
		)
	end)

	describe("マスターデータの検証（D-152）", function()
		it("D-152 種類の割合は MapEvents の種類を指す", function()
			expect(string.find(
				errorsOf(function(d)
					d.Constants.mapEventKindWeights[1].id = "mev_nope"
				end),
				"mapEventKindWeights",
				1,
				true
			) ~= nil).toBe(true)
		end)
		it("D-152 レイドの到着が次の時間帯に重なる設定は止める", function()
			expect(string.find(
				errorsOf(function(d)
					d.Constants.raidTravelSeconds = 200
				end),
				"raidTravelSeconds",
				1,
				true
			) ~= nil).toBe(true)
		end)
		it("D-152 場所の一覧は1行以上", function()
			expect(string.find(
				errorsOf(function(d)
					d.MapEvents.places = {}
				end),
				"MapEvents.places",
				1,
				true
			) ~= nil).toBe(true)
		end)
	end)
end
