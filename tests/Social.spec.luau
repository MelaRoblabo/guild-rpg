--!strict
-- M7b-4 後半（担当A）：今週の訪問者（D-158, D-170）、専用ギフト（D-165, D-174, D-177, D-185）、
-- フレンドボタンと紹介（D-157, D-180）、セーブの移行 v8 → 9
local serde = require("@lune/serde")

local Calendar = require("../src/core/Calendar")
local CommandText = require("../src/core/CommandText")
local ExclusiveGift = require("../src/core/ExclusiveGift")
local Expedition = require("../src/core/Expedition")
local Friend = require("../src/core/Friend")
local Game = require("../src/core/Game")
local Hiring = require("../src/core/Hiring")
local MasterData = require("../src/core/MasterData")
local Migration = require("../src/core/Migration")
local Party = require("../src/core/Party")
local Protocol = require("../src/core/Protocol")
local Rebirth = require("../src/core/Rebirth")
local Rng = require("../src/core/Rng")
local Visitor = require("../src/core/Visitor")
local Data = require("../src/data")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1767225600 -- 2026-01-01 00:00 UTC（木曜）
local DAY = 86400
local WEEK = 7 * DAY

-- テスト用の専用ギフト（本番の src/data には中身が決まるまで置かない：D-165）
local function withExclusive(d: any, opts: any?)
	local o = opts or {}
	table.insert(d.Gifts, {
		id = "gift_test_ex_chest",
		name = "テスト専用・宝箱",
		exclusive = true,
		partyEffect = { kind = "chestMult", value = o.chest or 2 },
	})
	table.insert(d.Gifts, {
		id = "gift_test_ex_travel",
		name = "テスト専用・移動",
		exclusive = true,
		effect = { kind = "statPct", stat = "agi", value = 0.1 },
		partyEffect = { kind = "travelMult", value = o.travel or 0.8 },
	})
	for _, u in d.Uniques do
		if u.id == "uni_garrett" then
			u.exclusiveGiftId = "gift_test_ex_chest"
		elseif u.id == "uni_lyra" then
			u.exclusiveGiftId = "gift_test_ex_travel"
		end
	end
end

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local K = master.K
	local exMaster = Fixtures.master(withExclusive)

	local function ctx(now: number, m: any?, friendCount: number?)
		return { now = now, master = m or master, online = true, friendCount = friendCount }
	end
	local function exec(s: any, cmd: any, now: number?, m: any?, friendCount: number?): any
		return Game.execute(s, cmd, ctx(now or T0, m, friendCount))
	end
	local function newState(seed: number?, m: any?)
		return Game.newState(m or master, seed or 1, T0)
	end
	local function errorsOf(mutate: (any) -> ()): string
		local d = Fixtures.clone(Data)
		mutate(d)
		local lines = {}
		for _, i in MasterData.validate(d) do
			if i.level == "error" then
				table.insert(lines, i.path .. " " .. i.message)
			end
		end
		return table.concat(lines, "\n")
	end
	local function has(s: string, part: string): boolean
		return string.find(s, part, 1, true) ~= nil
	end
	local function addUnique(s: any, uniqueId: string, m: any): any
		local u = m.uniques[uniqueId]
		local uid = `adv_{s.nextUid}`
		s.nextUid += 1
		local adv = Hiring.newAdventurer(uid, {
			uniqueId = u.id,
			name = u.name,
			gender = u.gender,
			appearanceId = u.appearanceId,
			jobId = u.jobId,
			giftIds = u.giftIds,
		}, u.baseStats, T0, m)
		s.adventurers[uid] = adv
		return adv
	end
	local function uniquesIn(cands: { any }): { string }
		local out = {}
		for _, c in cands do
			if c.kind == "unique" then
				table.insert(out, c.uniqueId)
			end
		end
		return out
	end

	describe("今週の訪問者（D-158, D-170、06章 §18）", function()
		it("D-158 D-170 週の番号と calendarSeed だけで決まる（全員共通）", function()
			local week = Calendar.weekIndex(T0)
			local a = Visitor.forWeek(week, master)
			local b = Visitor.forWeek(week, Fixtures.master())
			expect(a ~= nil).toBeTruthy()
			expect(a.id).toBe(b.id)
			-- プレイヤーの seed には関係しない
			expect(Game.query.weeklyVisitor(newState(1), T0, master).uniqueId).toBe(
				Game.query.weeklyVisitor(newState(99), T0, master).uniqueId
			)
		end)
		it("D-158 D-168 週の中では替わらず、月曜の区切りで替わる", function()
			local week = Calendar.weekIndex(T0)
			local monday = Calendar.nextWeekStart(T0) - WEEK
			local id = Visitor.forWeek(week, master).id
			for i = 0, 6 do
				expect(Visitor.forTime(monday + i * DAY + 3600, master).id).toBe(id)
			end
			expect(Calendar.weekIndex(Calendar.nextWeekStart(T0))).toBe(week + 1)
			expect(Calendar.weekIndex(Calendar.nextWeekStart(T0) - 1)).toBe(week)
			-- 何週も見れば別の人になる週がある
			local seen = {}
			local n = 0
			for w = week, week + 30 do
				local u = Visitor.forWeek(w, master).id
				if not seen[u] then
					seen[u] = true
					n += 1
				end
			end
			expect(n >= 2).toBeTruthy()
		end)
		it(
			"D-155 D-158 候補は visitor のユニークだけ（ログイン用・初回踏破は出ない）",
			function()
				local m = Fixtures.master(function(d)
					table.insert(d.Uniques, {
						id = "uni_test_login",
						name = "テストのログイン",
						gender = "f",
						appearanceId = "uni_lyra",
						jobId = "job_mage",
						baseStats = { str = 1, mag = 1, agi = 1, dex = 1, hp = 1 },
						giftIds = {},
						acquire = "login",
						loginOrder = 99,
						jobChange = "line",
					})
				end)
				local week = Calendar.weekIndex(T0)
				for w = week, week + 100 do
					expect(m.uniques[Visitor.forWeek(w, m).id].acquire).toBe("visitor")
				end
			end
		)
		it(
			"D-170 ① 今週の訪問者を別枠の確率で判定する（同じ雇用の2枠目には出ない）",
			function()
				local m = Fixtures.master(function(d)
					d.Constants.weeklyVisitorChance = 1
					d.Constants.specialVisitorChance = 0
				end)
				local weekly = Visitor.forTime(T0, m).id
				for seed = 1, 10 do
					local list = uniquesIn(Hiring.rollCandidates(newState(1, m), Rng.new(seed), m, T0))
					expect(list).toEqual({ weekly })
				end
			end
		)
		it("D-170 今週の訪問者を持っていれば①を飛ばす（乱数も引かない）", function()
			local function cands(weeklyChance: number): { any }
				local m = Fixtures.master(function(d)
					d.Constants.weeklyVisitorChance = weeklyChance
					d.Constants.specialVisitorChance = 0
				end)
				local s = newState(1, m)
				addUnique(s, Visitor.forTime(T0, m).id, m)
				return Hiring.rollCandidates(s, Rng.new(7), m, T0)
			end
			local a = cands(1)
			expect(#uniquesIn(a)).toBe(0)
			expect(a).toEqual(cands(0))
		end)
		it(
			"D-170 ② 特別な訪問者は、今週の人以外の持っていない visitor のユニークから選ぶ",
			function()
				local m = Fixtures.master(function(d)
					d.Constants.weeklyVisitorChance = 0
					d.Constants.specialVisitorChance = 1
				end)
				local weekly = Visitor.forTime(T0, m).id
				local seen = {}
				for seed = 1, 20 do
					for _, id in uniquesIn(Hiring.rollCandidates(newState(1, m), Rng.new(seed), m, T0)) do
						expect(id ~= weekly).toBeTruthy()
						expect(m.uniques[id].acquire).toBe("visitor")
						seen[id] = true
					end
				end
				expect(next(seen) ~= nil).toBeTruthy()
			end
		)
		it("D-170 雇用の開始（HireStart）は ctx.now の週の訪問者で判定する", function()
			local m = Fixtures.master(function(d)
				d.Constants.weeklyVisitorChance = 1
				d.Constants.specialVisitorChance = 0
			end)
			local s = newState(1, m)
			s.gold = 100000
			expect(exec(s, { type = "HireStart" }, T0, m).ok).toBeTruthy()
			expect(uniquesIn(s.hireSession.candidates)).toEqual({ Visitor.forTime(T0, m).id })
		end)
		it(
			"D-158 雇用画面のバナー用に、今週の訪問者・出現率・仲間済み・次の区切りを返す",
			function()
				local s = newState()
				local q = Game.query.weeklyVisitor(s, T0, master)
				expect(q.uniqueId).toBe(Visitor.forTime(T0, master).id)
				expect(q.chance).toBe(K.weeklyVisitorChance)
				expect(q.candidateSlots).toBe(s.expansions.candidateSlots)
				expect(q.owned).toBe(false)
				expect(q.nextWeekAt > T0 and q.nextWeekAt - T0 <= WEEK).toBeTruthy()
				addUnique(s, q.uniqueId, master)
				expect(Game.query.weeklyVisitor(s, T0, master).owned).toBe(true)
			end
		)
		it("D-158 weeklyVisitorChance は確率（0〜1）として検証する", function()
			expect(has(
				errorsOf(function(d)
					d.Constants.weeklyVisitorChance = 1.5
				end),
				"Constants.weeklyVisitorChance"
			)).toBeTruthy()
		end)
	end)

	describe("専用ギフト（D-165, D-174）", function()
		it("D-165 本番データには専用ギフトの行をまだ置かない（中身は未決）", function()
			for _, g in Data.Gifts do
				expect(g.exclusive).toBe(nil)
			end
			for _, u in Data.Uniques do
				expect(u.exclusiveGiftId).toBe(nil)
			end
		end)
		it("D-165 一般の抽選（雇用の初期ギフト）に出ない", function()
			for _, g in exMaster.giftList do
				expect(g.exclusive).toBe(nil)
			end
			local m = Fixtures.master(function(d)
				withExclusive(d)
				d.Constants.specialVisitorChance = 0
				d.Constants.weeklyVisitorChance = 0
			end)
			for seed = 1, 50 do
				for _, c in Hiring.rollCandidates(newState(1, m), Rng.new(seed), m, T0) do
					for _, g in c.giftIds do
						expect(m.gifts[g].exclusive).toBe(nil)
					end
				end
			end
		end)
		it("D-165 転生で増えるギフトの抽選にも出ない", function()
			local s = newState(1, exMaster)
			for seed = 1, 50 do
				local adv = Game._deepClone(s.adventurers.adv_1)
				adv.rebirthCount = K.rebirthGiftAddAt[1] - 1
				adv.giftIds = {}
				local added = Rebirth.apply(
					adv,
					{ inherited = adv.baseStats, newAppearanceId = adv.appearanceId },
					{ str = 0, mag = 0, agi = 0, dex = 0, hp = 0 },
					Rng.new(seed),
					exMaster
				)
				expect(added ~= nil).toBeTruthy()
				expect(exMaster.gifts[added :: string].exclusive).toBe(nil)
			end
		end)
		it("D-165 ユニークは加入すると専用ギフトを持つ（候補の表示にも出る）", function()
			local m = Fixtures.master(function(d)
				withExclusive(d)
				d.Constants.weeklyVisitorChance = 0
				d.Constants.specialVisitorChance = 1
			end)
			local s = newState(1, m)
			s.gold = 100000
			exec(s, { type = "HireStart" }, T0, m)
			local idx, cand = nil, nil
			for i, c in s.hireSession.candidates do
				if c.kind == "unique" then
					idx, cand = i, c
					break
				end
			end
			expect(cand ~= nil).toBeTruthy()
			local u = m.uniques[cand.uniqueId]
			expect(table.find(cand.giftIds, u.exclusiveGiftId) ~= nil).toBeTruthy()
			exec(s, { type = "HirePick", candidateIndex = idx }, T0, m)
			local r = exec(s, { type = "HireChoose", which = "current" }, T0, m)
			expect(r.ok).toBeTruthy()
			local adv = s.adventurers[r.events[1].uid]
			expect(adv.giftIds).toEqual(ExclusiveGift.uniqueGiftIds(u))
			expect(adv.giftIds[#adv.giftIds]).toBe(u.exclusiveGiftId)
		end)
		it(
			"D-165 D-174 マスターデータの検証（専用の印・持ち主は1人・枠・パーティ効果）",
			function()
				-- partyEffect は専用ギフトだけ
				expect(has(
					errorsOf(function(d)
						d.Gifts[1].partyEffect = { kind = "chestMult", value = 1.2 }
					end),
					"Gifts[1].partyEffect"
				)).toBeTruthy()
				-- 効果の種類は移動・宝箱だけ
				expect(has(
					errorsOf(function(d)
						withExclusive(d)
						d.Gifts[#d.Gifts].partyEffect = { kind = "expMult", value = 2 }
					end),
					"partyEffect.kind"
				)).toBeTruthy()
				-- 移動は 0〜1、宝箱は 1 以上
				expect(has(
					errorsOf(function(d)
						withExclusive(d, { travel = 1.5, chest = 0.5 })
					end),
					"partyEffect.value"
				)).toBeTruthy()
				-- exclusiveGiftId は専用ギフトを指す
				expect(has(
					errorsOf(function(d)
						d.Uniques[1].exclusiveGiftId = d.Gifts[1].id
					end),
					"Uniques[1].exclusiveGiftId"
				)).toBeTruthy()
				-- 持ち主は1人だけ
				expect(has(
					errorsOf(function(d)
						withExclusive(d)
						d.Uniques[3].exclusiveGiftId = "gift_test_ex_chest"
					end),
					"Uniques[3].exclusiveGiftId"
				)).toBeTruthy()
				-- giftIds と合わせて giftMax まで
				expect(has(
					errorsOf(function(d)
						withExclusive(d)
						d.Uniques[1].giftIds = { "gift_swift", "gift_lucky", "gift_sturdy", "gift_guide" }
					end),
					"giftMax"
				)).toBeTruthy()
				-- 専用ギフトは giftIds（一般の冒険者・ユニークの固定ギフト）に書かない
				expect(has(
					errorsOf(function(d)
						withExclusive(d)
						d.StarterSet.adventurers[1].giftIds = { "gift_test_ex_chest" }
					end),
					"StarterSet.adventurers[1].giftIds"
				)).toBeTruthy()
				-- テスト用の専用ギフトの形は通る（専用ギフトは weight・effect を省ける）
				expect(errorsOf(function(d)
					withExclusive(d)
				end)).toBe("")
			end
		)
		it("D-174 同じ効果はパーティ内で重ねない（一番大きい1つだけ）", function()
			local m = Fixtures.master(function(d)
				withExclusive(d, { chest = 1.5, travel = 0.8 })
				table.insert(d.Gifts, {
					id = "gift_test_ex_chest2",
					name = "テスト専用・宝箱2",
					exclusive = true,
					partyEffect = { kind = "chestMult", value = 1.2 },
				})
				table.insert(d.Gifts, {
					id = "gift_test_ex_travel2",
					name = "テスト専用・移動2",
					exclusive = true,
					partyEffect = { kind = "travelMult", value = 0.9 },
				})
				d.Uniques[3].exclusiveGiftId = "gift_test_ex_chest2"
			end)
			local pe = ExclusiveGift.partyEffects({
				{ giftIds = { "gift_test_ex_chest2", "gift_test_ex_travel2" } },
				{ giftIds = { "gift_test_ex_chest", "gift_test_ex_travel" } },
				{ giftIds = { "gift_test_ex_chest" } },
			}, m)
			expect(pe.chestMult).toBe(1.5)
			expect(pe.chestGiftId).toBe("gift_test_ex_chest")
			expect(pe.travelMult).toBe(0.8)
			expect(pe.travelGiftId).toBe("gift_test_ex_travel")
			expect(ExclusiveGift.partyEffects({ { giftIds = { "gift_lucky" } } }, m)).toEqual({
				travelMult = 1,
				chestMult = 1,
			})
		end)
		it(
			"D-174 D-173 移動は片道秒に掛け、宝箱は数に掛ける（途中ログインでも元の宝箱と一緒に持ち帰る）",
			function()
				local s = newState(1, exMaster)
				local base = Party.snapshots(s, 1, exMaster)
				local function simulate(seed: number, gifts: { string }?): any
					local members = base
					if gifts then
						members = Game._deepClone(base)
						for _, g in gifts do
							table.insert(members[1].giftIds, g)
						end
					end
					return Expedition.simulate(
						{ seed = seed, departAt = T0, dungeonId = "dng_graveyard", members = members },
						exMaster
					)
				end
				local seed = 1
				while #simulate(seed).rewards.chests == 0 do
					seed += 1
				end
				local a = simulate(seed)
				local b = simulate(seed, { "gift_test_ex_chest" }) -- ×2（整数なので乱数を引かない）
				expect(#b.rewards.chests).toBe(2 * #a.rewards.chests)
				expect(b.partyChests).toBe(#a.rewards.chests)
				expect(b.partyEffectGiftIds).toEqual({ "gift_test_ex_chest" })
				expect(a.partyChests).toBe(nil)
				expect(b.engineVersion).toBe(Expedition.ENGINE_VERSION)
				-- 途中ログイン（D-186）：持ち帰る元の宝箱の分だけ、増えた宝箱も持ち帰る
				for k = 1, #a.floors - 1 do
					local f = a.floors[k]
					local at = f.startOffset + f.duration
					expect(#Expedition.rewardsAt(b, at, K).rewards.chests).toBe(
						2 * #Expedition.rewardsAt(a, at, K).rewards.chests
					)
				end
				-- 移動
				local c = simulate(seed, { "gift_test_ex_travel" })
				expect(c.travelSeconds < a.travelSeconds).toBeTruthy()
				local d = simulate(seed, { "gift_test_ex_travel", "gift_test_ex_travel" })
				expect(d.travelSeconds).toBe(c.travelSeconds) -- 重ねない
			end
		)
	end)

	describe("フレンドボタン（D-157、06章 §20）", function()
		it(
			"D-157 押すとゴールドがその場で入り、人数で少し増える（上限 friendRewardMaxFriends 人分）",
			function()
				local function expected(n: number): number
					local c = math.min(n, K.friendRewardMaxFriends)
					return math.floor(K.friendRewardGold * (1 + K.friendRewardBonusPerFriend * (c - 1)))
				end
				for n = 1, 5 do
					expect(Friend.gold(n, master)).toBe(expected(n))
				end
				expect(Friend.gold(2, master) > Friend.gold(1, master)).toBeTruthy()
				expect(Friend.gold(5, master)).toBe(Friend.gold(K.friendRewardMaxFriends, master))
				local s = newState()
				local gold = s.gold
				local r = exec(s, { type = "ClaimFriendReward" }, T0, nil, 2)
				expect(r.ok).toBeTruthy()
				expect(s.gold).toBe(gold + expected(2))
				expect(r.events[1].type).toBe("FriendReward")
				expect(#s.inbox).toBe(0) -- 受け取り箱には入れない
			end
		)
		it("D-157 同じサーバーに友達がいなければ押せない", function()
			local s = newState()
			expect(exec(s, { type = "ClaimFriendReward" }, T0, nil, 0).error).toBe("NO_FRIEND")
			expect(exec(s, { type = "ClaimFriendReward" }, T0).error).toBe("NO_FRIEND")
		end)
		it("D-157 一定時間ごとに押せる。押さないとたまらない", function()
			local s = newState()
			local iv = K.friendRewardIntervalSeconds
			expect(exec(s, { type = "ClaimFriendReward" }, T0, nil, 1).ok).toBeTruthy()
			expect(exec(s, { type = "ClaimFriendReward" }, T0 + iv - 1, nil, 1).error).toBe("FRIEND_NOT_READY")
			expect(exec(s, { type = "ClaimFriendReward" }, T0 + iv, nil, 1).ok).toBeTruthy()
			-- 長く空けても1回分だけ
			local later = T0 + iv + 10 * iv
			expect(exec(s, { type = "ClaimFriendReward" }, later, nil, 1).ok).toBeTruthy()
			expect(exec(s, { type = "ClaimFriendReward" }, later + 1, nil, 1).error).toBe("FRIEND_NOT_READY")
			expect(s.friend.nextAt).toBe(later + iv)
		end)
		it("D-157 D-168 1日の上限まで。日の区切りで戻る", function()
			local s = newState()
			local iv = K.friendRewardIntervalSeconds
			local now = T0
			for _ = 1, K.friendRewardDailyCap do
				expect(exec(s, { type = "ClaimFriendReward" }, now, nil, 1).ok).toBeTruthy()
				now += iv
			end
			expect(Calendar.dayIndex(now)).toBe(Calendar.dayIndex(T0)) -- 同じ日のうちに上限まで押せる値
			expect(exec(s, { type = "ClaimFriendReward" }, now, nil, 1).error).toBe("DAILY_LIMIT")
			expect(Game.query.friend(s, now, 1, master).blocker).toBe("DAILY_LIMIT")
			local tomorrow = Calendar.nextDayStart(now)
			expect(exec(s, { type = "ClaimFriendReward" }, tomorrow, nil, 1).ok).toBeTruthy()
			expect(s.friend.todayCount).toBe(1)
		end)
		it(
			"D-157 友達の数はクライアントから受け取らない（サーバーが ctx で渡す）",
			function()
				expect({ Protocol.validateCommand({ type = "ClaimFriendReward" }) }).toEqual({ true, nil })
				expect((Protocol.validateCommand({ type = "ClaimFriendReward", friendCount = 3 }))).toBe(false)
				expect(CommandText.parse("friend 2")).toEqual({ type = "ClaimFriendReward" })
				expect({ Protocol.validateCommand(CommandText.parse("friend") :: any) }).toEqual({ true, nil })
			end
		)
	end)

	describe("紹介（D-157, D-180）", function()
		it("D-157 紹介の報酬はサーバー専用（クライアントからは受け付けない）", function()
			expect(Protocol.SERVER_ONLY.GrantReferral).toBe(true)
			expect((Protocol.validateCommand({ type = "GrantReferral", role = "invitee", userId = 1 }))).toBe(false)
		end)
		it("D-157 招待された側は1回だけ、受け取り箱へ", function()
			local s = newState()
			local r = exec(s, { type = "GrantReferral", role = "invitee", userId = 10 })
			expect(r.ok).toBeTruthy()
			expect(#s.inbox).toBe(1)
			expect(s.inbox[1].source).toBe("referral")
			expect(exec(s, { type = "GrantReferral", role = "invitee", userId = 10 }).error).toBe("ALREADY_REWARDED")
			local tickets = s.items.itm_slot_ticket or 0
			expect(exec(s, { type = "ClaimInbox" }).ok).toBeTruthy()
			expect(s.items.itm_slot_ticket).toBe(tickets + K.referralRewards.invitee.items.itm_slot_ticket)
		end)
		it("D-157 D-168 招待した側は相手1人ごと・週の上限まで。週の区切りで戻る", function()
			local s = newState()
			for i = 1, K.referralWeeklyCap do
				expect(exec(s, { type = "GrantReferral", role = "inviter", userId = i }).ok).toBeTruthy()
			end
			expect(exec(s, { type = "GrantReferral", role = "inviter", userId = 1 }).error).toBe("ALREADY_REWARDED")
			expect(exec(s, { type = "GrantReferral", role = "inviter", userId = 100 }).error).toBe("WEEKLY_LIMIT")
			expect(#s.inbox).toBe(K.referralWeeklyCap)
			local nextWeek = Calendar.nextWeekStart(T0)
			expect(exec(s, { type = "GrantReferral", role = "inviter", userId = 100 }, nextWeek).ok).toBeTruthy()
		end)
		it(
			"D-180 届け物を受け取り箱へ入れる。同じ id の届け物は二度受け取らない",
			function()
				local s = newState()
				local d = { id = "referral:42", kind = "referral", fromUserId = 42, at = T0 }
				local changed, events = Game.grantDelivery(s, d, ctx(T0))
				expect(changed).toBe(true)
				expect(events[1].type).toBe("ReferralGranted")
				expect(#s.inbox).toBe(1)
				expect(s.referral.claimedDeliveries["referral:42"]).toBe(true)
				-- サーバーが届け物を消す前に落ちて、同じ届け物がもう一度来た
				local before = Game._deepClone(s)
				local again, events2 = Game.grantDelivery(s, d, ctx(T0 + 60))
				expect(again).toBe(false)
				expect(events2).toEqual({})
				expect(s).toEqual(before)
				-- 知らない種類・形の違うものは何もしない
				expect((Game.grantDelivery(s, { id = "x:1", kind = "nope", fromUserId = 1, at = T0 }, ctx(T0)))).toBe(
					false
				)
				expect((Game.grantDelivery(s, {} :: any, ctx(T0)))).toBe(false)
				expect(s).toEqual(before)
			end
		)
		it(
			"D-180 招待された側に「招待した人へ届けた」の印を持てる（同じ招待で2回届けない）",
			function()
				local s = newState()
				expect(Friend.inviterDelivered(s)).toBe(false)
				expect(Friend.markInviterDelivered(s)).toBe(true)
				expect(Friend.inviterDelivered(s)).toBe(true)
				expect(Friend.markInviterDelivered(s)).toBe(false)
			end
		)
	end)

	describe("セーブの移行 version 8 → 9（M7b-4 後半）", function()
		local function v8State(m: any): any
			local s = newState(1, m)
			s.version = 8
			s.friend, s.referral = nil, nil
			return s
		end
		it("D-157 D-180 フレンドボタン・紹介の状態を初期値で足す", function()
			local s = Migration.migrate(v8State(master), master)
			expect(s.version).toBe(Migration.CURRENT)
			expect(s.friend).toEqual(Friend.newState())
			expect(s.referral).toEqual(Friend.newReferralState())
			-- 新規のセーブも同じ初期値
			local n = newState()
			expect(n.version).toBe(Migration.CURRENT)
			expect(n.friend).toEqual(Friend.newState())
			expect(n.referral).toEqual(Friend.newReferralState())
			-- JSON にして戻しても動く
			local decoded = serde.decode("json", serde.encode("json", s))
			expect(exec(decoded, { type = "ClaimFriendReward" }, T0, nil, 1).ok).toBeTruthy()
		end)
		it(
			"D-177 D-185 既存のユニークに専用ギフトを足す。枠がいっぱいなら giftIds の先頭と入れ替える",
			function()
				local s = v8State(exMaster)
				local garrett = addUnique(s, "uni_garrett", exMaster)
				local lyra = addUnique(s, "uni_lyra", exMaster)
				-- 専用ギフトを持つ前の旧版の形にする
				garrett.giftIds = { "gift_sturdy", "gift_swift", "gift_lucky", "gift_guide" }
				lyra.giftIds = { "gift_lucky" }
				local general = s.adventurers.adv_1
				local generalGifts = table.clone(general.giftIds)
				Migration.migrate(s, exMaster)
				expect(s.adventurers[garrett.uid].giftIds).toEqual({
					"gift_test_ex_chest",
					"gift_swift",
					"gift_lucky",
					"gift_guide",
				})
				expect(s.adventurers[lyra.uid].giftIds).toEqual({ "gift_lucky", "gift_test_ex_travel" })
				expect(s.adventurers.adv_1.giftIds).toEqual(generalGifts)
			end
		)
		it("D-177 専用ギフトを持つユニークがいなければ何も変えない", function()
			local s = v8State(master)
			local adv = addUnique(s, "uni_garrett", master)
			local gifts = table.clone(adv.giftIds)
			Migration.migrate(s, master)
			expect(s.adventurers[adv.uid].giftIds).toEqual(gifts)
		end)
		it("D-177 移行には master が要る（無ければ何も変えずに失敗する）", function()
			local s = v8State(master)
			local before = Game._deepClone(s)
			expect(function()
				Migration.migrate(s)
			end).toThrow("master")
			expect(s).toEqual(before)
		end)
	end)
end
