--!strict
-- ゲームの窓口（docs/system/01_architecture.md §3、05_commands.md）
--   Game.newState(master, seed, now)
--   Game.advance(state, ctx) -> events        すべてのコマンドの前に呼ぶ（入口側の責任）
--   Game.execute(state, command, ctx) -> { ok, events } | { ok = false, error }
--   Game.query.*                              表示用の読み取り（状態を変えない）
-- ctx = { now: number, master: any, online: boolean, friendCount: number? }
--   friendCount：同じサーバーにいる友達の数（サーバーが数える：M7b-5。ClaimFriendReward だけが使う：D-157）

local Calendar = require("./Calendar")
local Chest = require("./Chest")
local DailyTrait = require("./DailyTrait")
local Expedition = require("./Expedition")
local Formulas = require("./Formulas")
local Friend = require("./Friend")
local Growth = require("./Growth")
local Guild = require("./Guild")
local Appearance = require("./Appearance")
local Hiring = require("./Hiring")
local Inbox = require("./Inbox")
local JobChange = require("./JobChange")
local Inventory = require("./Inventory")
local Login = require("./Login")
local MapEvent = require("./MapEvent")
local Merchant = require("./Merchant")
local Migration = require("./Migration")
local Party = require("./Party")
local Playtime = require("./Playtime")
local Quest = require("./Quest")
local Raid = require("./Raid")
local Rebirth = require("./Rebirth")
local Rng = require("./Rng")
local Training = require("./Training")
local Visitor = require("./Visitor")

local Game = {}

export type Ctx = { now: number, master: any, online: boolean, friendCount: number? }
export type Result = { ok: boolean, events: { any }?, error: string? }

-- 補助 -------------------------------------------------------------------

local function deepClone(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepClone(x)
	end
	return out
end
Game._deepClone = deepClone

local function newUid(state: any, prefix: string): string
	local uid = `{prefix}_{state.nextUid}`
	state.nextUid += 1
	return uid
end

-- 乱数を1本払い出す（08章 §2）
local function takeRng(state: any): (Rng.Rng, number)
	local seed = Rng.derive(state.seed, state.rngCounter)
	state.rngCounter += 1
	return Rng.new(seed), seed
end

-- 乱数が要るときだけ1本払い出す関数（受け取り箱の宝箱のランク：D-166）
local function rngTaker(state: any): () -> Rng.Rng
	return function()
		return (takeRng(state))
	end
end

local function bump(state: any, key: string, n: number?)
	state.stats[key] = (state.stats[key] or 0) + (n or 1)
end

local function fail(code: string): Result
	return { ok = false, error = code }
end

-- 状態の作成 -------------------------------------------------------------

function Game.newState(master: any, seed: number, now: number): any
	local S = master.raw.StarterSet
	local state = {
		version = Migration.CURRENT,
		seed = seed,
		rngCounter = 0,
		nextUid = 1,
		gold = S.gold,
		guild = { level = 1, exp = 0 },
		expansions = table.clone(S.expansions),
		adventurers = {},
		parties = {},
		equipment = {},
		chests = {},
		items = {},
		expeditions = {},
		unlockedDungeons = {},
		clearedDungeons = {},
		hireSession = nil,
		rebirthSession = nil,
		settings = { autoSell = table.clone(S.autoSell) }, -- D-167：最初からオン
		stats = {},
		createdAt = now,
		lastAdvancedAt = now,
		lastSavedAt = now, -- 最後に保存した時刻（留守の始まり：D-161）。サーバーが保存のときに書く（M7b-5）
		restBonusSeconds = 0, -- 休息ボーナスの残り秒（D-161）
		quests = Quest.newState(), -- D-153。次のオンラインの advance で今日・今週の分を作る
		login = Login.newState(), -- D-155。次のオンラインの advance で1日目
		playtime = Playtime.newState(), -- D-154
		inbox = {}, -- 受け取り箱（D-164）
		friend = Friend.newState(), -- フレンドボタン（D-157）。version 9
		referral = Friend.newReferralState(), -- 紹介（D-157, D-180）。version 9
	}
	for i = 1, state.expansions.partySlots do
		state.parties[i] = { index = i, slots = Party.newSlots(), autoRepeat = nil }
	end
	for _, d in master.dungeonList do
		if d.unlockAfterClear == nil then
			state.unlockedDungeons[d.id] = true
		end
	end
	for i, a in S.adventurers do
		local uid = newUid(state, "adv")
		local adv = {
			uid = uid,
			uniqueId = nil,
			name = a.name,
			appearanceId = a.appearanceId,
			gender = a.gender,
			jobId = a.jobId,
			level = 1,
			levelCap = master.K.levelCapInitial,
			exp = 0,
			rebirthCount = 0,
			baseStats = table.clone(a.baseStats),
			giftIds = table.clone(a.giftIds),
			equipment = {},
			locked = false,
			hiredAt = now,
		}
		state.adventurers[uid] = adv
		for _, baseId in a.equipment do
			local e = Inventory.newEquipment(state, { baseId = baseId, rarity = 1, grade = 0, itemLevel = 1 })
			Inventory.equip(state, adv, e, master)
		end
		if i <= 4 then
			state.parties[1].slots[i] = uid
		end
	end
	return state
end

-- 探索を1回計算する（状態には入れない。乱数は1本使う）
-- 日替わりの特性は出発時刻の日のものを固定する（D-156）。留守番は所要秒を offlineTimeMult 倍にする（D-161）
local function planExpedition(
	state: any,
	partyIndex: number,
	dungeonId: string,
	departAt: number,
	master: any,
	offline: boolean,
	rare: any?
): any
	local _, seed = takeRng(state)
	local snaps = Party.snapshots(state, partyIndex, master)
	-- レアダンジョン（rare = { eventSlot, pileKey }）は日替わりの特性を当てない（D-187）
	local traitId = if rare then nil else DailyTrait.traitIdFor(dungeonId, departAt, master)
	local log = Expedition.simulate({
		seed = seed,
		departAt = departAt,
		dungeonId = dungeonId,
		members = snaps,
		dailyTraitId = traitId,
		timeMult = if offline then master.K.offlineTimeMult else nil,
		chestMult = if rare then master.K.rareDungeonChestMult else nil, -- D-152
	}, master)
	local memberUids = {}
	for _, s in snaps do
		table.insert(memberUids, s.uid)
	end
	return {
		uid = "",
		partyIndex = partyIndex,
		dungeonId = dungeonId,
		seed = seed,
		departAt = departAt,
		returnAt = departAt + log.totalSeconds,
		memberUids = memberUids,
		log = log,
		offline = if offline then true else nil, -- 留守番の探索（D-161）。クエストに数えない・休息ボーナスを使わない
		dailyTraitId = traitId,
		eventSlot = if rare then rare.eventSlot else nil, -- マップイベントへの派遣（D-152）
		chestPile = if rare then rare.pileKey else nil, -- 宝箱の山（レアダンジョンは special:rare:<相当>：D-171）
	}
end

local function commitExpedition(state: any, e: any): any
	e.uid = newUid(state, "ex")
	state.expeditions[e.uid] = e
	bump(state, "expeditions")
	if e.offline then
		bump(state, "offlineExpeditions")
	end
	return e
end

-- 派遣（D-026）。departAt を指定できる（自動再派遣は帰還時刻から出発する）。派遣費は廃止（D-163）
local function dispatch(state: any, partyIndex: number, dungeonId: string, departAt: number, master: any): any
	return commitExpedition(state, planExpedition(state, partyIndex, dungeonId, departAt, master, false))
end

-- 自動再派遣できない理由（できるなら nil）。派遣費の不足による停止は D-163 で削除
local function autoRepeatBlocker(state: any): string?
	if Inventory.warehouseFree(state) <= 0 then
		return "WAREHOUSE_FULL"
	end
	return nil
end

-- 帰還処理：報酬を状態に反映する
-- restActive：休息ボーナスが効くか（オンライン中の帰還で、帰還時に残りがある：06章 §14）
local function collect(state: any, e: any, master: any, events: { any }, restActive: boolean)
	if e.raidDamage then
		-- レイドからの帰還：報酬は到着時に入れた（受け取り箱：D-179）。ここでは帰るだけ
		state.expeditions[e.uid] = nil
		bump(state, "raidReturns")
		table.insert(events, {
			type = "RaidReturned",
			at = e.returnAt,
			partyIndex = e.partyIndex,
			eventSlot = e.eventSlot,
			damage = e.raidDamage,
		})
		return
	end
	local K = master.K
	local log = e.log
	local r = log.rewards
	local rng = takeRng(state)

	state.gold += r.gold
	-- 売却用アイテム（素材）は常にその場で売る（D-167）
	local itemsSoldGold = 0
	for itemId, c in r.items do
		itemsSoldGold += Inventory.gainItem(state, itemId, c, master)
	end
	-- 宝箱はギルドの宝箱置き場へ（倉庫とは別、上限なし：D-084）。普通の探索の山の鍵は dungeonId（D-166）
	-- レアダンジョンは special:rare:<相当するダンジョン>（D-171, D-185）
	local pileKey = e.chestPile or e.dungeonId
	for _, c in r.chests do
		Chest.add(state, pileKey, c.rank, 1)
	end

	-- 経験値（D-041：生存者で等分済み。個人倍率はここで掛ける）。順序を固定するため隊列順に処理
	-- 休息ボーナス（留守番の探索には使わない）と日替わりの expMult は expBonusCap の外で掛け合わせる（D-161, D-173）
	local useRest = restActive and not e.offline
	local outerMult = (if useRest then K.restBonusExpMult else 1) * DailyTrait.expMult(e.dailyTraitId, master)
	local levelUps = {}
	for _, uid in e.memberUids do
		local amount = r.exp[uid]
		local adv = state.adventurers[uid]
		if amount and amount > 0 and adv then
			local levels = Growth.addExp(adv, amount, rng, master, state.equipment, outerMult)
			if #levels > 0 then
				table.insert(levelUps, { uid = uid, level = adv.level })
			end
		end
	end

	-- ギルド経験値と初回踏破（Q-017）
	local guildExp = r.guildExp
	local firstClear = false
	if log.result == "clear" and not state.clearedDungeons[e.dungeonId] then
		firstClear = true
		state.clearedDungeons[e.dungeonId] = true
		guildExp += K.guildExpFirstClear
	end
	Guild.addExp(state, guildExp, master, events, e.returnAt)

	state.expeditions[e.uid] = nil
	bump(state, if log.result == "clear" then "clears" else "retreats")
	bump(state, "chestsGained", #r.chests)
	if state.stats.firstReturnAt == nil then
		state.stats.firstReturnAt = e.returnAt
	end

	table.insert(events, {
		type = "ExpeditionReturned",
		at = e.returnAt,
		partyIndex = e.partyIndex,
		dungeonId = e.dungeonId,
		result = log.result,
		retreatReason = log.retreatReason,
		reachedFloor = log.reachedFloor,
		chests = #r.chests,
		gold = r.gold,
		items = r.items,
		itemsSoldGold = itemsSoldGold,
		guildExp = guildExp,
		offline = e.offline,
		interrupted = e.interrupted, -- 途中ログインで戻った（D-186）
		dailyTraitId = e.dailyTraitId,
		restBonus = if useRest then true else nil,
		eventSlot = e.eventSlot, -- レアダンジョンからの帰還（D-152）
		pileKey = if e.chestPile then e.chestPile else nil,
	})
	for _, lu in levelUps do
		table.insert(events, { type = "LevelUp", at = e.returnAt, uid = lu.uid, level = lu.level })
	end
	if firstClear then
		table.insert(events, { type = "FirstClear", at = e.returnAt, dungeonId = e.dungeonId })
		-- ユニークキャラの初回踏破報酬（02章 §2、企画書§16.7）。所属枠を超えても加入する
		for _, u in master.raw.Uniques do
			if u.acquire == "firstClear:" .. e.dungeonId then
				local owned = false
				for _, a in state.adventurers do
					owned = owned or a.uniqueId == u.id
				end
				if not owned then
					local uid = newUid(state, "adv")
					local cand = {
						uniqueId = u.id,
						name = u.name,
						gender = u.gender,
						appearanceId = u.appearanceId,
						jobId = u.jobId,
						giftIds = u.giftIds,
					}
					state.adventurers[uid] = Hiring.newAdventurer(uid, cand, u.baseStats, e.returnAt, master)
					table.insert(events, { type = "UniqueJoined", at = e.returnAt, uid = uid, uniqueId = u.id })
				end
			end
		end
		for _, d in master.dungeonList do
			if d.unlockAfterClear == e.dungeonId and not state.unlockedDungeons[d.id] then
				state.unlockedDungeons[d.id] = true
				table.insert(events, { type = "DungeonUnlocked", at = e.returnAt, dungeonId = d.id })
			end
		end
	end
end

-- 時間経過（05章 §3） ------------------------------------------------------

-- 帰還時刻が ctx.now 以前で最も早い探索（同時刻は uid の数値順）
local function nextReturn(state: any, now: number): any?
	local nextE = nil
	for _, e in state.expeditions do
		if e.returnAt <= now then
			if
				nextE == nil
				or e.returnAt < nextE.returnAt
				or (
					e.returnAt == nextE.returnAt
					and tonumber(string.sub(e.uid, 4)) < tonumber(string.sub(nextE.uid, 4))
				)
			then
				nextE = e
			end
		end
	end
	return nextE
end

-- レイドの到着（D-152, D-179）：到着時刻が ctx.now 以前でまだ入れていないダメージを、到着の早い順に入れる
-- 結果は出発時に決まっているので、オンラインでも留守の計算でも同じに入れる
local function raidArrivals(state: any, now: number, master: any, events: { any })
	local list = {}
	for _, e in state.expeditions do
		if e.raidDamage and not e.raidArrived and e.arriveAt <= now then
			table.insert(list, e)
		end
	end
	table.sort(list, function(x, y)
		if x.arriveAt ~= y.arriveAt then
			return x.arriveAt < y.arriveAt
		end
		return tonumber(string.sub(x.uid, 4)) < tonumber(string.sub(y.uid, 4))
	end)
	local take = rngTaker(state)
	for _, e in list do
		e.raidArrived = true
		Raid.arrive(state, e, take, master, events)
	end
end

-- 留守の始まり（06章 §13、D-193）＝ max(lastSavedAt, lastAdvancedAt)。lastSavedAt はサーバーが保存のときに書く（M7b-5）。
-- オンラインで進めた時間を留守として重ねて数えないよう、最後の advance の時刻より前にはしない。
-- サーバーが落ちて失われた進み具合（最後の定期保存から落ちるまで）は、次のログインで留守として計算される（D-193）
function Game.offlineStart(state: any): number
	return math.max(state.lastSavedAt or state.lastAdvancedAt, state.lastAdvancedAt)
end

-- オンライン（ctx.online == true）：帰還 → 自動再派遣を ctx.now に追いつくまで。休息ボーナスはオンラインの経過秒だけ減る
-- 帰還・自動再派遣のあとで、日・週の切り替え（クエストの入れ替え・ログインボーナスの前進）とプレイ時間（05章 §3-4）
local function advanceOnline(state: any, ctx: Ctx, events: { any })
	local master = ctx.master
	local t0 = state.lastAdvancedAt
	local rest = state.restBonusSeconds or 0
	local take = rngTaker(state)
	raidArrivals(state, ctx.now, master, events)
	while true do
		local nextE = nextReturn(state, ctx.now)
		if nextE == nil then
			break
		end
		-- 帰還時刻での休息ボーナスの残り（06章 §14、D-173）
		local restLeft = rest - math.max(0, nextE.returnAt - t0)
		collect(state, nextE, master, events, restLeft > 0)
		-- クエストの「踏破」はオンライン中の帰還で数える（留守番の探索は数えない：D-153, D-161）
		-- レアダンジョンの踏破は数え、レイドは数えない（D-191）
		if nextE.log.result == "clear" and not nextE.offline and not nextE.raidDamage then
			Quest.count(state, "clears", 1, nextE.returnAt, master, take, events)
		end

		local party = state.parties[nextE.partyIndex]
		if party and party.autoRepeat then
			local blocker = autoRepeatBlocker(state)
			if blocker then
				party.autoRepeat = nil
				table.insert(
					events,
					{ type = "AutoRepeatStopped", at = nextE.returnAt, partyIndex = nextE.partyIndex, reason = blocker }
				)
			elseif state.unlockedDungeons[party.autoRepeat.dungeonId] then
				local e2 = dispatch(state, nextE.partyIndex, party.autoRepeat.dungeonId, nextE.returnAt, master)
				table.insert(events, {
					type = "AutoDispatched",
					at = nextE.returnAt,
					partyIndex = nextE.partyIndex,
					dungeonId = e2.dungeonId,
					returnAt = e2.returnAt,
				})
				-- オンライン中の自動再派遣も「探索の回数」に数える（D-179）
				Quest.count(state, "expeditions", 1, nextE.returnAt, master, take, events)
			end
		end
	end
	state.restBonusSeconds = math.max(0, rest - math.max(0, ctx.now - t0))
	Quest.refresh(state, ctx.now, master) -- D-153：日・週が変わったら入れ替える（引き直しなし）
	Login.advance(state, ctx.now, master, take, events) -- D-155：その日の最初のオンラインの advance で1日分
	-- プレイ時間：前回の advance からのオンラインの経過秒を足す（D-154。留守番の時間は数えない）
	Playtime.advance(state, t0, ctx.now, master, take, events)
end

-- 留守番（ctx.online == false。ログイン時の留守の計算：05章 §3、06章 §13・§14、D-161, D-172）
local function advanceOffline(state: any, ctx: Ctx, events: { any })
	local master = ctx.master
	local K = master.K
	local start = Game.offlineStart(state)
	local finish = start + K.offlineMaxSeconds -- 6時間までに最後の探索を帰還させる
	-- 休息ボーナスを貯める：留守にした時間 × restBonusRate（上限 restBonusMaxSeconds）
	local away = math.max(0, ctx.now - start)
	local gained = math.floor(away * K.restBonusRate)
	state.restBonusSeconds = math.min((state.restBonusSeconds or 0) + gained, K.restBonusMaxSeconds)
	-- ログアウトの前に出発したレイドのダメージは入れる（結果は出発時に決まる：D-152）。留守中は新しく参加しない（D-161）
	raidArrivals(state, ctx.now, master, events)

	while true do
		local nextE = nextReturn(state, ctx.now)
		if nextE == nil then
			break
		end
		collect(state, nextE, master, events, false)
		-- 自動再派遣のパーティは留守番の探索を続ける。倉庫がいっぱいでも止めない（D-172）
		local party = state.parties[nextE.partyIndex]
		if party and party.autoRepeat and state.unlockedDungeons[party.autoRepeat.dungeonId] then
			local counter = state.rngCounter
			local plan =
				planExpedition(state, nextE.partyIndex, party.autoRepeat.dungeonId, nextE.returnAt, master, true)
			if plan.returnAt <= finish then
				local e2 = commitExpedition(state, plan)
				table.insert(events, {
					type = "AutoDispatched",
					at = nextE.returnAt,
					partyIndex = nextE.partyIndex,
					dungeonId = e2.dungeonId,
					returnAt = e2.returnAt,
					offline = true,
				})
			else
				state.rngCounter = counter -- 出さなかった探索の乱数は使わなかったことにする
			end
		end
	end

	-- 6時間より前にログインしたら、帰っていない留守番の探索はログインの時点で帰還させる（D-172）。全員ギルドで待機
	-- 持ち帰るのはその時点までに進んだフロアの分だけ（その時点で撤退したのと同じ：D-186）
	local pending = {}
	for _, e in state.expeditions do
		if e.offline then
			table.insert(pending, e)
		end
	end
	table.sort(pending, function(x, y)
		return tonumber(string.sub(x.uid, 4)) < tonumber(string.sub(y.uid, 4))
	end)
	for _, e in pending do
		local part = Expedition.rewardsAt(e.log, ctx.now - e.departAt, K)
		local log = table.clone(e.log)
		log.result = part.result
		log.retreatReason = part.retreatReason
		log.reachedFloor = part.reachedFloor
		log.rewards = part.rewards
		e.log = log
		e.returnAt = ctx.now
		e.interrupted = if part.interrupted then true else nil
		collect(state, e, master, events, false)
	end
	state.stats.offlineSecondsTotal = (state.stats.offlineSecondsTotal or 0) + away
end

function Game.advance(state: any, ctx: Ctx): { any }
	local events = {}
	if ctx.online then
		advanceOnline(state, ctx, events)
	else
		advanceOffline(state, ctx, events)
	end
	state.lastAdvancedAt = math.max(state.lastAdvancedAt, ctx.now)
	return events
end

-- コマンド ---------------------------------------------------------------

local handlers: { [string]: (any, any, Ctx) -> Result } = {}

handlers.SetPartySlot = function(state, cmd, ctx)
	local p = state.parties[cmd.partyIndex]
	if not p then
		return fail("PARTY_NOT_FOUND")
	end
	if cmd.slot < 1 or cmd.slot > Party.SIZE then
		return fail("INVALID_SLOT")
	end
	if Party.isBusy(state, cmd.partyIndex) then
		return fail("PARTY_BUSY")
	end
	local uid = cmd.adventurerUid
	if uid == nil or uid == Party.EMPTY then
		p.slots[cmd.slot] = Party.EMPTY
		return { ok = true, events = {} }
	end
	if not state.adventurers[uid] then
		return fail("ADVENTURER_NOT_FOUND")
	end
	local otherParty, otherSlot = Party.find(state, uid)
	if otherParty and otherParty ~= cmd.partyIndex then
		return fail("ADVENTURER_IN_OTHER_PARTY")
	end
	if otherParty == cmd.partyIndex and otherSlot then
		-- 同じパーティ内なら入れ替え
		p.slots[otherSlot] = p.slots[cmd.slot]
	end
	p.slots[cmd.slot] = uid
	local _ = ctx
	return { ok = true, events = {} }
end

handlers.Equip = function(state, cmd, ctx)
	local adv = state.adventurers[cmd.adventurerUid]
	local item = state.equipment[cmd.equipmentUid]
	if not adv then
		return fail("ADVENTURER_NOT_FOUND")
	end
	if not item then
		return fail("ITEM_NOT_FOUND")
	end
	if Party.isAdventurerBusy(state, adv.uid) then
		return fail("ADVENTURER_ON_EXPEDITION")
	end
	if item.equippedBy and Party.isAdventurerBusy(state, item.equippedBy) then
		return fail("ITEM_HOLDER_ON_EXPEDITION") -- 品を装備している別の冒険者が探索中
	end
	local err = Inventory.equip(state, adv, item, ctx.master)
	if err then
		return fail(err)
	end
	return { ok = true, events = {} }
end

handlers.Unequip = function(state, cmd, _ctx)
	local adv = state.adventurers[cmd.adventurerUid]
	if not adv then
		return fail("ADVENTURER_NOT_FOUND")
	end
	if Party.isAdventurerBusy(state, adv.uid) then
		return fail("ADVENTURER_ON_EXPEDITION")
	end
	local err = Inventory.unequip(state, adv, cmd.slot)
	if err then
		return fail(err)
	end
	return { ok = true, events = {} }
end

handlers.Dispatch = function(state, cmd, ctx)
	local p = state.parties[cmd.partyIndex]
	if not p then
		return fail("PARTY_NOT_FOUND")
	end
	if Party.isBusy(state, cmd.partyIndex) then
		return fail("PARTY_BUSY")
	end
	if state.rebirthSession and table.find(p.slots, state.rebirthSession.adventurerUid) then
		return fail("ADVENTURER_IN_REBIRTH")
	end
	if not ctx.master.dungeons[cmd.dungeonId] then
		return fail("DUNGEON_NOT_FOUND")
	end
	if not state.unlockedDungeons[cmd.dungeonId] then
		return fail("DUNGEON_LOCKED")
	end
	if Party.isEmpty(p) then
		return fail("PARTY_EMPTY")
	end
	local e = dispatch(state, cmd.partyIndex, cmd.dungeonId, ctx.now, ctx.master)
	local events: { any } = {
		{
			type = "Dispatched",
			at = ctx.now,
			partyIndex = cmd.partyIndex,
			dungeonId = cmd.dungeonId,
			returnAt = e.returnAt,
		},
	}
	Quest.count(state, "expeditions", 1, ctx.now, ctx.master, rngTaker(state), events) -- D-179：オンライン中の出発
	return { ok = true, events = events }
end

handlers.SetAutoRepeat = function(state, cmd, ctx)
	local p = state.parties[cmd.partyIndex]
	if not p then
		return fail("PARTY_NOT_FOUND")
	end
	if cmd.dungeonId == nil then
		p.autoRepeat = nil
	else
		if not ctx.master.dungeons[cmd.dungeonId] then
			return fail("DUNGEON_NOT_FOUND")
		end
		if not state.unlockedDungeons[cmd.dungeonId] then
			return fail("DUNGEON_LOCKED")
		end
		p.autoRepeat = { dungeonId = cmd.dungeonId }
	end
	return { ok = true, events = {} }
end

handlers.OpenChests = function(state, cmd, ctx)
	-- D-087：プレイヤーに見えるのは「どの宝箱の山が何個」だけ。レアリティは開けるまで分からない
	-- D-089, D-166：まとめ開き。指定した宝箱の山から最大 count 個（省略時 chestBatchOpen）を、残り数で重み付けして1つずつ引く
	local master = ctx.master
	local pileKey = cmd.pileKey
	-- 中身の表と演出ライン（普通の山・特別な宝箱・レアダンジョンの山：D-166, D-171）
	local source = if type(pileKey) == "string" then Chest.pileSource(pileKey, state, master) else nil
	if not source then
		return fail("PILE_NOT_FOUND")
	end
	if cmd.count ~= nil and (type(cmd.count) ~= "number" or cmd.count < 1 or cmd.count ~= math.floor(cmd.count)) then
		return fail("INVALID_COUNT")
	end
	local available = Chest.pileTotal(state, pileKey)
	if available == 0 then
		return fail("NO_CHEST")
	end
	local n = math.min(cmd.count or master.K.chestBatchOpen, available)
	local perChest = Chest.maxEquipmentPerChest(master)
	local pickRng = takeRng(state)
	local normal, special = {}, {}
	local opened = 0
	local stoppedBy = nil
	for _ = 1, n do
		if Inventory.warehouseFree(state) < perChest then
			stoppedBy = "WAREHOUSE_FULL" -- 途中で倉庫がいっぱいになった
			break
		end
		local rank = Chest.draw(state, pileKey, pickRng)
		Chest.add(state, pileKey, rank, -1)
		local res = Chest.open(state, { pileKey = pileKey, rank = rank }, takeRng(state), master)
		-- 自動売却（06章 §6、D-167）：保護中の品は対象外（開けたばかりの品は保護されていない）
		local auto = state.settings.autoSell
		if auto.enabled then
			local kept = {}
			res.autoSold = {}
			res.autoSoldGold = 0
			for _, uid in res.equipmentUids do
				local item = state.equipment[uid]
				if item.rarity <= auto.maxRarity and not (auto.keepModified and item.modifierId) then
					local price = Inventory.equipmentSellPrice(item, master)
					state.gold += price
					res.autoSoldGold += price
					table.insert(res.autoSold, { baseId = item.baseId, rarity = item.rarity, grade = item.grade })
					state.equipment[uid] = nil
					bump(state, "goldFromSales", price)
				else
					table.insert(kept, uid)
				end
			end
			res.equipmentUids = kept
		end
		-- D-089：宝箱の山ごとの発生ライン以上のレアリティなら演出あり（派手さはレアリティで決まる）
		res.effect = rank >= source.effectMinRarity
		opened += 1
		res.order = opened
		table.insert(if res.effect then special else normal, res)
		bump(state, "chestsOpened")
	end
	if opened == 0 then
		return fail("WAREHOUSE_FULL")
	end
	if state.stats.firstChestOpenedAt == nil then
		state.stats.firstChestOpenedAt = ctx.now
	end
	-- 表示の順（D-089）：演出なしをまとめて一覧 → 演出ありをレアリティの低い順に1つずつ（最後が一番派手）
	table.sort(special, function(x, y)
		if x.rank ~= y.rank then
			return x.rank < y.rank
		end
		return x.order < y.order
	end)
	local events: { any } = {
		{
			type = "ChestsOpened",
			at = ctx.now,
			pileKey = pileKey,
			opened = opened,
			normal = normal,
			special = special,
			remaining = Chest.pileTotal(state, pileKey),
			stoppedBy = stoppedBy,
		},
	}
	Quest.count(state, "chestsOpened", opened, ctx.now, master, rngTaker(state), events) -- D-153
	return { ok = true, events = events }
end

-- 一括売却（05章 BulkSell、06章 §17、D-167, D-175）：開封結果に出た装備のうち「今の装備より弱い」ものを全部売る
-- もう無い品（売った・自動売却された）は飛ばす
handlers.BulkSell = function(state, cmd, ctx)
	local master = ctx.master
	local targets = {}
	local seen = {}
	for _, uid in cmd.equipmentUids or {} do
		local e = state.equipment[uid]
		if e and not seen[uid] and Inventory.isWeakForBulkSell(state, e, master) then
			seen[uid] = true
			table.insert(targets, uid)
		end
	end
	if #targets == 0 then
		return fail("NOTHING_TO_SELL")
	end
	local total = 0
	for _, uid in targets do
		total += Inventory.equipmentSellPrice(state.equipment[uid], master)
		state.equipment[uid] = nil
	end
	state.gold += total
	bump(state, "goldFromSales", total)
	return { ok = true, events = { { type = "Sold", at = ctx.now, gold = total, equipmentUids = targets } } }
end

handlers.Sell = function(state, cmd, ctx)
	local master = ctx.master
	local total = 0
	local sold = {}
	for _, uid in cmd.equipmentUids or {} do
		local e = state.equipment[uid]
		if not e then
			return fail("ITEM_NOT_FOUND")
		end
		if e.locked then
			return fail("ITEM_LOCKED")
		end
		if e.equippedBy then
			return fail("ITEM_EQUIPPED")
		end
		total += Inventory.equipmentSellPrice(e, master)
		state.equipment[uid] = nil
		table.insert(sold, uid)
	end
	if cmd.itemId then
		local item = master.items[cmd.itemId]
		local count = cmd.count or 1
		if not item then
			return fail("ITEM_NOT_FOUND")
		end
		if item.kind ~= "sellable" then
			return fail("ITEM_NOT_SELLABLE")
		end
		if (state.items[cmd.itemId] or 0) < count then
			return fail("NOT_ENOUGH_ITEMS")
		end
		state.items[cmd.itemId] -= count
		total += item.sellPrice * count
	end
	state.gold += total
	bump(state, "goldFromSales", total)
	return { ok = true, events = { { type = "Sold", at = ctx.now, gold = total, equipmentUids = sold } } }
end

handlers.SetLock = function(state, cmd, _ctx)
	local target = state.adventurers[cmd.uid] or state.equipment[cmd.uid]
	if not target then
		return fail("NOT_FOUND")
	end
	target.locked = cmd.locked == true
	return { ok = true, events = {} }
end

-- 雇用・面接（02章 §3、Q-006） -------------------------------------------

local function rosterCount(state: any): number
	local n = 0
	for _ in state.adventurers do
		n += 1
	end
	return n
end

handlers.HireStart = function(state, _cmd, ctx)
	local K = ctx.master.K
	if state.hireSession then
		return fail("SESSION_EXISTS")
	end
	if rosterCount(state) >= state.expansions.rosterSize then
		return fail("ROSTER_FULL")
	end
	if state.gold < K.hireCost then
		return fail("NOT_ENOUGH_GOLD")
	end
	state.gold -= K.hireCost
	local rng = takeRng(state)
	state.hireSession = {
		candidates = Hiring.rollCandidates(state, rng, ctx.master, ctx.now), -- 今週の訪問者は ctx.now の週（D-158）
		pickedIndex = nil,
		previousRoll = nil,
		currentRoll = nil,
		freeRerollsLeft = K.hireFreeRerolls,
	}
	bump(state, "hireStarted")
	return { ok = true, events = { { type = "HireStarted", at = ctx.now, cost = K.hireCost } } }
end

handlers.HirePick = function(state, cmd, ctx)
	local h = state.hireSession
	if not h then
		return fail("NO_SESSION")
	end
	if h.pickedIndex then
		return fail("ALREADY_PICKED")
	end
	local c = h.candidates[cmd.candidateIndex]
	if not c then
		return fail("CANDIDATE_NOT_FOUND")
	end
	h.pickedIndex = cmd.candidateIndex
	if c.kind == "unique" then
		h.currentRoll = Hiring.uniqueStats(c.uniqueId, ctx.master)
	else
		h.currentRoll = Hiring.rollStats(takeRng(state), ctx.master)
	end
	return { ok = true, events = { { type = "StatsRolled", at = ctx.now, stats = h.currentRoll } } }
end

handlers.HireReroll = function(state, _cmd, ctx)
	local h = state.hireSession
	if not h then
		return fail("NO_SESSION")
	end
	if not h.pickedIndex then
		return fail("NOT_PICKED")
	end
	local c = h.candidates[h.pickedIndex]
	if c.kind == "unique" then
		return fail("UNIQUE_FIXED_STATS")
	end
	local usedTicket = false
	if h.freeRerollsLeft > 0 then
		h.freeRerollsLeft -= 1
	else
		if (state.items.itm_slot_ticket or 0) < 1 then
			return fail("NO_TICKET")
		end
		state.items.itm_slot_ticket -= 1
		usedTicket = true
	end
	-- D-086：直前の結果だけを比較用に残す（それより前の結果は消える。良い結果を残すには採用するしかない）
	h.previousRoll = h.currentRoll
	h.currentRoll = Hiring.rollStats(takeRng(state), ctx.master)
	bump(state, "hireRerolls")
	return {
		ok = true,
		events = { { type = "StatsRolled", at = ctx.now, stats = h.currentRoll, usedTicket = usedTicket } },
	}
end

handlers.HireChoose = function(state, cmd, ctx)
	local h = state.hireSession
	if not h then
		return fail("NO_SESSION")
	end
	if not h.pickedIndex then
		return fail("NOT_PICKED")
	end
	local stats = if cmd.which == "previous"
		then h.previousRoll
		elseif cmd.which == "current" then h.currentRoll
		else nil
	if not stats then
		return fail("INVALID_CHOICE")
	end
	if rosterCount(state) >= state.expansions.rosterSize then
		return fail("ROSTER_FULL")
	end
	local uid = newUid(state, "adv")
	local adv = Hiring.newAdventurer(uid, h.candidates[h.pickedIndex], stats, ctx.now, ctx.master)
	state.adventurers[uid] = adv
	state.hireSession = nil
	bump(state, "hired")
	local events: { any } = { { type = "Hired", at = ctx.now, uid = uid } }
	Quest.count(state, "hires", 1, ctx.now, ctx.master, rngTaker(state), events) -- D-153
	return { ok = true, events = events }
end

handlers.HireCancel = function(state, _cmd, ctx)
	if not state.hireSession then
		return fail("NO_SESSION")
	end
	state.hireSession = nil -- 雇用費は戻らない（05章）
	return { ok = true, events = { { type = "HireCanceled", at = ctx.now } } }
end

handlers.Rename = function(state, cmd, _ctx)
	local adv = state.adventurers[cmd.adventurerUid]
	if not adv then
		return fail("ADVENTURER_NOT_FOUND")
	end
	if adv.uniqueId then
		return fail("UNIQUE_CANNOT_RENAME")
	end
	local len = if type(cmd.name) == "string" then utf8.len(cmd.name) else nil
	if not len or len < 1 or len > 12 then
		return fail("INVALID_NAME")
	end
	adv.name = cmd.name
	return { ok = true, events = {} }
end

-- 解雇（Q-020）：保護中・探索中は不可。装備は倉庫へ戻す
handlers.Dismiss = function(state, cmd, ctx)
	local adv = state.adventurers[cmd.adventurerUid]
	if not adv then
		return fail("ADVENTURER_NOT_FOUND")
	end
	if adv.locked then
		return fail("ADVENTURER_LOCKED")
	end
	if Party.isAdventurerBusy(state, adv.uid) then
		return fail("ADVENTURER_ON_EXPEDITION")
	end
	if
		(state.rebirthSession and state.rebirthSession.adventurerUid == adv.uid)
		or (state.appearanceSession and state.appearanceSession.adventurerUid == adv.uid)
	then
		return fail("ADVENTURER_IN_SESSION")
	end
	local equipped = 0
	for _ in adv.equipment do
		equipped += 1
	end
	if Inventory.warehouseFree(state) < equipped then
		return fail("WAREHOUSE_FULL")
	end
	for slot, uid in adv.equipment do
		state.equipment[uid].equippedBy = nil
		adv.equipment[slot] = nil
	end
	local partyIndex, slot = Party.find(state, adv.uid)
	if partyIndex and slot then
		state.parties[partyIndex].slots[slot] = Party.EMPTY
	end
	state.adventurers[adv.uid] = nil
	return { ok = true, events = { { type = "Dismissed", at = ctx.now, uid = adv.uid, name = adv.name } } }
end

-- 転生（07章 §2、D-071, D-072, Q-021） ------------------------------------

handlers.RebirthStart = function(state, cmd, ctx)
	local master = ctx.master
	local adv = state.adventurers[cmd.adventurerUid]
	if not adv then
		return fail("ADVENTURER_NOT_FOUND")
	end
	if state.rebirthSession then
		return fail("SESSION_EXISTS")
	end
	if Party.isAdventurerBusy(state, adv.uid) then
		return fail("ADVENTURER_ON_EXPEDITION")
	end
	local err = Rebirth.canRebirth(adv, master)
	if err then
		return fail(err)
	end
	local cost = Rebirth.cost(adv, master) -- D-080
	if state.gold < cost then
		return fail("NOT_ENOUGH_GOLD")
	end
	local rng = takeRng(state)
	local newAppearanceId = adv.appearanceId
	if adv.uniqueId then
		if cmd.useKeepPotion then
			return fail("UNIQUE_APPEARANCE_FIXED") -- ユニークは見た目固定。ポーションを無駄にさせない
		end
	elseif cmd.useKeepPotion then
		if (state.items.itm_potion_appearance_keep or 0) < 1 then
			return fail("NO_POTION")
		end
		state.items.itm_potion_appearance_keep -= 1
	else
		-- 通常転生：性別固定で見た目を引き直す（D-051）
		local outfit = Appearance.outfitClassOf(adv.jobId, master)
		newAppearanceId = Appearance.roll(adv.gender, outfit, rng, master, adv.appearanceId).appearanceId
	end
	state.gold -= cost
	bump(state, "goldSpentOnRebirth", cost)
	state.rebirthSession = {
		adventurerUid = adv.uid,
		inherited = Rebirth.inherited(adv.baseStats),
		bonusMax = Rebirth.bonusMax(adv.baseStats, master),
		previousBonus = nil,
		currentBonus = Rebirth.rollBonus(adv.baseStats, adv.rebirthCount + 1, rng, master),
		freeRerollsLeft = master.K.rebirthFreeRerolls,
		newAppearanceId = newAppearanceId,
	}
	return { ok = true, events = { { type = "RebirthStarted", at = ctx.now, uid = adv.uid, cost = cost } } }
end

handlers.RebirthReroll = function(state, _cmd, ctx)
	local r = state.rebirthSession
	if not r then
		return fail("NO_SESSION")
	end
	local usedTicket = false
	if r.freeRerollsLeft > 0 then
		r.freeRerollsLeft -= 1
	else
		if (state.items.itm_slot_ticket or 0) < 1 then
			return fail("NO_TICKET")
		end
		state.items.itm_slot_ticket -= 1
		usedTicket = true
	end
	local adv = state.adventurers[r.adventurerUid]
	r.previousBonus = r.currentBonus -- D-086：直前の結果だけを残す
	r.currentBonus = Rebirth.rollBonus(adv.baseStats, adv.rebirthCount + 1, takeRng(state), ctx.master)
	bump(state, "rebirthRerolls")
	return { ok = true, events = { { type = "RebirthRerolled", at = ctx.now, usedTicket = usedTicket } } }
end

handlers.RebirthChoose = function(state, cmd, ctx)
	local r = state.rebirthSession
	if not r then
		return fail("NO_SESSION")
	end
	local bonus = if cmd.which == "previous"
		then r.previousBonus
		elseif cmd.which == "current" then r.currentBonus
		else nil
	if not bonus then
		return fail("INVALID_CHOICE")
	end
	local adv = state.adventurers[r.adventurerUid]
	local giftId = Rebirth.apply(adv, r, bonus, takeRng(state), ctx.master)
	state.rebirthSession = nil
	bump(state, "rebirths")
	local events: { any } = {
		{
			type = "Reborn",
			at = ctx.now,
			uid = adv.uid,
			rebirthCount = adv.rebirthCount,
			levelCap = adv.levelCap,
			giftAdded = giftId,
		},
	}
	Quest.count(state, "rebirths", 1, ctx.now, ctx.master, rngTaker(state), events) -- D-153（ウィークリーだけ）
	return { ok = true, events = events }
end

-- 転職（03章 §4） --------------------------------------------------------

handlers.ChangeJob = function(state, cmd, ctx)
	local master = ctx.master
	local adv = state.adventurers[cmd.adventurerUid]
	if not adv then
		return fail("ADVENTURER_NOT_FOUND")
	end
	if Party.isAdventurerBusy(state, adv.uid) then
		return fail("ADVENTURER_ON_EXPEDITION")
	end
	local err = JobChange.check(adv, cmd.jobId, master)
	if err then
		return fail(err)
	end
	local potion = JobChange.potionId(cmd.jobId)
	if (state.items[potion] or 0) < 1 then
		return fail("NO_POTION")
	end
	-- 装備できなくなる品は倉庫へ戻す
	local slots = JobChange.unequippableSlots(state, adv, cmd.jobId, master)
	if Inventory.warehouseFree(state) < #slots then
		return fail("WAREHOUSE_FULL")
	end
	for _, slot in slots do
		state.equipment[adv.equipment[slot]].equippedBy = nil
		adv.equipment[slot] = nil
	end
	state.items[potion] -= 1
	local from = adv.jobId
	adv.jobId = cmd.jobId -- 見た目は維持（D-052）。以降の成長は新しい職業（D-045）
	bump(state, "jobChanges")
	return {
		ok = true,
		events = {
			{ type = "JobChanged", at = ctx.now, uid = adv.uid, from = from, to = cmd.jobId, unequipped = slots },
		},
	}
end

-- 見た目変更ポーション（07章 §3、D-051） ------------------------------------

handlers.ChangeAppearance = function(state, cmd, ctx)
	local master = ctx.master
	local adv = state.adventurers[cmd.adventurerUid]
	if not adv then
		return fail("ADVENTURER_NOT_FOUND")
	end
	if adv.uniqueId then
		return fail("UNIQUE_CANNOT_CHANGE")
	end
	if state.appearanceSession then
		return fail("SESSION_EXISTS")
	end
	if (state.items.itm_potion_appearance_change or 0) < 1 then
		return fail("NO_POTION")
	end
	state.items.itm_potion_appearance_change -= 1 -- どちらを選んでも1個消費
	local outfit = Appearance.outfitClassOf(adv.jobId, master)
	local rolled = Appearance.roll(adv.gender, outfit, takeRng(state), master, adv.appearanceId)
	state.appearanceSession =
		{ adventurerUid = adv.uid, previousId = adv.appearanceId, currentId = rolled.appearanceId }
	return {
		ok = true,
		events = { { type = "AppearanceRolled", at = ctx.now, uid = adv.uid, appearanceId = rolled.appearanceId } },
	}
end

handlers.ChangeAppearanceChoose = function(state, cmd, ctx)
	local a = state.appearanceSession
	if not a then
		return fail("NO_SESSION")
	end
	local id = if cmd.which == "previous" then a.previousId elseif cmd.which == "current" then a.currentId else nil
	if not id then
		return fail("INVALID_CHOICE")
	end
	local adv = state.adventurers[a.adventurerUid]
	if adv then
		adv.appearanceId = id
	end
	state.appearanceSession = nil
	return {
		ok = true,
		events = { { type = "AppearanceChanged", at = ctx.now, uid = a.adventurerUid, appearanceId = id } },
	}
end

-- トレーニング（D-076, D-077） ----------------------------------------------

handlers.Train = function(state, cmd, ctx)
	local master = ctx.master
	local adv = state.adventurers[cmd.adventurerUid]
	if not adv then
		return fail("ADVENTURER_NOT_FOUND")
	end
	local n = cmd.sessions
	if type(n) ~= "number" or n < 1 or n ~= math.floor(n) then
		return fail("INVALID_COUNT")
	end
	if Party.isAdventurerBusy(state, adv.uid) then
		return fail("ADVENTURER_ON_EXPEDITION")
	end
	if state.rebirthSession and state.rebirthSession.adventurerUid == adv.uid then
		return fail("ADVENTURER_IN_REBIRTH")
	end
	if adv.level >= Training.levelCap(adv, state, master) then
		return fail("TRAINING_CAP")
	end
	if state.gold < Training.sessionCost(adv.level, master.K) then
		return fail("NOT_ENOUGH_GOLD")
	end
	local r = Training.run(state, adv, n, takeRng(state), master)
	bump(state, "goldSpentOnTraining", r.gold)
	bump(state, "trainingSessions", r.sessions)
	local events: { any } = {
		{
			type = "Trained",
			at = ctx.now,
			uid = adv.uid,
			sessions = r.sessions,
			gold = r.gold,
			level = adv.level,
			levelsGained = #r.levels,
		},
	}
	-- D-153, D-191：トレーニングは行った回数（sessions）で数える
	Quest.count(state, "trainings", r.sessions, ctx.now, master, rngTaker(state), events)
	return { ok = true, events = events }
end

-- 拡張・設定（08章 §4、06章 §6） --------------------------------------------

-- 次に買える段階（なければ nil）
function Game.nextExpansionStep(state: any, expansionId: string, master: any): any
	local e = master.expansions[expansionId]
	if not e then
		return nil
	end
	local current = state.expansions[e.kind]
	for _, s in e.steps do
		if s.value > current then
			return s
		end
	end
	return nil
end

handlers.BuyExpansion = function(state, cmd, ctx)
	local master = ctx.master
	local e = master.expansions[cmd.expansionId]
	if not e then
		return fail("EXPANSION_NOT_FOUND")
	end
	local step = Game.nextExpansionStep(state, cmd.expansionId, master)
	if not step then
		return fail("EXPANSION_MAXED")
	end
	if state.guild.level < step.guildLevel then
		return fail("GUILD_LEVEL_TOO_LOW")
	end
	if step.requiresClear and not state.clearedDungeons[step.requiresClear] then
		return fail("DUNGEON_NOT_CLEARED")
	end
	if state.gold < step.gold then
		return fail("NOT_ENOUGH_GOLD")
	end
	state.gold -= step.gold
	state.expansions[e.kind] = step.value
	if e.kind == "partySlots" then
		for i = #state.parties + 1, step.value do
			state.parties[i] = { index = i, slots = Party.newSlots(), autoRepeat = nil }
		end
	end
	bump(state, "goldSpentOnExpansions", step.gold)
	return {
		ok = true,
		events = { { type = "Expanded", at = ctx.now, expansionId = e.id, value = step.value, gold = step.gold } },
	}
end

handlers.SetAutoSell = function(state, cmd, ctx)
	local r = tonumber(cmd.maxRarity) or state.settings.autoSell.maxRarity
	if r < 1 or r > ctx.master.rarityCount then
		return fail("INVALID_RARITY")
	end
	state.settings.autoSell = {
		enabled = cmd.enabled == true,
		maxRarity = r,
		keepModified = if cmd.keepModified == nil then true else cmd.keepModified == true,
	}
	return { ok = true, events = {} }
end

-- マップイベント（05章 DispatchEvent・BuyFromMerchant、06章 §12、D-152, D-179） ---------------------
-- コマンドはオンラインでだけ届く。留守中（advance の ctx.online == false）はイベントに参加しない（D-161）

-- レアダンジョンに出発したパーティ（partyIndex → eventSlot）。今の時間帯の分だけ残す（03章）
local function rareJoined(state: any, slot: number, partyIndex: number): boolean
	local slots = state.rareDungeonSlots
	return slots ~= nil and slots[tostring(partyIndex)] == slot
end

local function markRareJoined(state: any, slot: number, partyIndex: number)
	local slots = {}
	for k, v in state.rareDungeonSlots or {} do
		if v == slot then
			slots[k] = v
		end
	end
	slots[tostring(partyIndex)] = slot
	state.rareDungeonSlots = slots
end

handlers.DispatchEvent = function(state, cmd, ctx)
	local master = ctx.master
	local p = state.parties[cmd.partyIndex]
	if not p then
		return fail("PARTY_NOT_FOUND")
	end
	local slot = cmd.eventSlot
	-- 種類はその時間帯のイベント（全員共通）で決まる。商人には派遣できない
	local kind = if type(slot) == "number" and slot == math.floor(slot)
		then MapEvent.eventAt(slot, master).kind
		else nil
	if kind ~= "rareDungeon" and kind ~= "raid" then
		return fail("EVENT_NOT_ACTIVE")
	end
	local err = MapEvent.check(slot, kind, ctx.now, master)
	if err then
		return fail(err)
	end
	if
		(kind == "rareDungeon" and rareJoined(state, slot, cmd.partyIndex))
		or (kind == "raid" and Raid.joined(state, slot, cmd.partyIndex))
	then
		return fail("EVENT_ALREADY_JOINED") -- 1パーティ1回まで（D-152）
	end
	if Party.isBusy(state, cmd.partyIndex) then
		return fail("PARTY_BUSY")
	end
	if state.rebirthSession and table.find(p.slots, state.rebirthSession.adventurerUid) then
		return fail("ADVENTURER_IN_REBIRTH")
	end
	if Party.isEmpty(p) then
		return fail("PARTY_EMPTY")
	end
	local events: { any } = {}
	if kind == "rareDungeon" then
		-- 強さは踏破済みの一番深いダンジョン、宝箱 × rareDungeonChestMult、山は special:rare:<1段上>（D-152, D-171, D-185）
		local target = MapEvent.rareDungeonTarget(state, master)
		local e = commitExpedition(
			state,
			planExpedition(
				state,
				cmd.partyIndex,
				target.dungeonId,
				ctx.now,
				master,
				false,
				{ eventSlot = slot, pileKey = target.pileKey }
			)
		)
		markRareJoined(state, slot, cmd.partyIndex)
		bump(state, "rareDungeonDispatches")
		table.insert(events, {
			type = "EventDispatched",
			at = ctx.now,
			kind = kind,
			eventSlot = slot,
			partyIndex = cmd.partyIndex,
			dungeonId = target.dungeonId,
			pileKey = target.pileKey,
			returnAt = e.returnAt,
		})
	else
		-- レイド：ダメージは出発時に計算し、到着時刻にボスへ入れる（D-152, D-179、07章 §4b）
		local K = master.K
		local snaps = Party.snapshots(state, cmd.partyIndex, master)
		local damage = Raid.damage(snaps, K)
		local memberUids = {}
		for _, sn in snaps do
			table.insert(memberUids, sn.uid)
		end
		-- 表示用にダンジョンを持たせる（強さの基準と同じ、踏破済みの一番深いダンジョン）
		local dungeonId = MapEvent.rareDungeonTarget(state, master).dungeonId
		local travel = K.raidTravelSeconds
		Raid.join(state, slot, cmd.partyIndex, master)
		local e = commitExpedition(state, {
			uid = "",
			partyIndex = cmd.partyIndex,
			dungeonId = dungeonId,
			seed = 0,
			departAt = ctx.now,
			arriveAt = ctx.now + travel,
			returnAt = ctx.now + travel * 2,
			memberUids = memberUids,
			log = {
				engineVersion = Expedition.ENGINE_VERSION,
				seed = 0,
				dungeonId = dungeonId,
				departAt = ctx.now,
				result = "raid",
				reachedFloor = 0,
				travelSeconds = travel,
				replaySeconds = 0,
				totalSeconds = travel * 2,
				floors = {},
				rewards = { exp = {}, gold = 0, chests = {}, items = {}, floorsCleared = 0, guildExp = 0 },
			},
			eventSlot = slot,
			raidDamage = damage,
		})
		bump(state, "raidDispatches")
		table.insert(events, {
			type = "EventDispatched",
			at = ctx.now,
			kind = kind,
			eventSlot = slot,
			partyIndex = cmd.partyIndex,
			damage = damage,
			hp = state.raid.hp,
			arriveAt = e.arriveAt,
			returnAt = e.returnAt,
		})
	end
	-- D-179：オンライン中の出発（DispatchEvent）も「探索の回数」に数える
	Quest.count(state, "expeditions", 1, ctx.now, master, rngTaker(state), events)
	return { ok = true, events = events }
end

handlers.BuyFromMerchant = function(state, cmd, ctx)
	local master = ctx.master
	local err = MapEvent.check(cmd.eventSlot, "merchant", ctx.now, master)
	if err then
		return fail(err)
	end
	local buyErr, r = Merchant.buy(state, cmd.eventSlot, cmd.itemIndex, master)
	if buyErr then
		return fail(buyErr)
	end
	bump(state, "goldSpentOnMerchant", r.price)
	bump(state, "merchantBought")
	return {
		ok = true,
		events = {
			{
				type = "MerchantBought",
				at = ctx.now,
				eventSlot = cmd.eventSlot,
				itemIndex = cmd.itemIndex,
				equipmentUid = r.equipment.uid,
				price = r.price,
			},
		},
	}
end

-- 受け取り箱（05章 ClaimInbox、D-164, D-176）：受け取れるものだけ受け取り、残りは受け取り箱に残す（期限なし）
handlers.ClaimInbox = function(state, _cmd, ctx)
	if #state.inbox == 0 then
		return fail("INBOX_EMPTY")
	end
	local r = Inbox.claim(state, ctx.now, ctx.master)
	local events: { any } = {
		{
			type = "InboxClaimed",
			at = ctx.now,
			gold = r.gold,
			items = r.items,
			chests = r.chests, -- 宝箱の山ごとの数（ランクは出さない：D-087）
			remaining = r.remaining,
			blocked = r.blocked,
		},
	}
	for _, j in r.joined do
		table.insert(events, { type = "UniqueJoined", at = ctx.now, uid = j.uid, uniqueId = j.uniqueId })
	end
	return { ok = true, events = events }
end

-- フレンドボタン（05章 ClaimFriendReward、D-157）：友達の数はサーバーが数えて ctx.friendCount で渡す（M7b-5）
-- 受け取り箱には入れず、その場でゴールドを渡す
handlers.ClaimFriendReward = function(state, _cmd, ctx)
	local ev, err = Friend.claim(state, ctx.now, ctx.friendCount or 0, ctx.master)
	if err then
		return fail(err)
	end
	return { ok = true, events = { ev } }
end

-- 紹介の報酬（05章 GrantReferral、D-157, D-180, D-192。サーバー専用）：受け取り箱へ入れる
--   role = "invitee"：招待された側（1回だけ。Friend.referralProgressReached に届いてから：D-192）
--   role = "inviter"：招待した側。userId は招待された人、deliveryId は届け物の id（同じ id は二度受け取らない）
handlers.GrantReferral = function(state, cmd, ctx)
	if type(cmd.userId) ~= "number" then
		return fail("INVALID_USER")
	end
	local ev, err =
		Friend.grantReferral(state, cmd.role, cmd.userId, cmd.deliveryId, ctx.now, rngTaker(state), ctx.master)
	if err then
		return fail(err)
	end
	return { ok = true, events = { ev } }
end

Game.COMMANDS = {}
for name in handlers do
	table.insert(Game.COMMANDS, name)
end
table.sort(Game.COMMANDS)

-- 検証 → 変更。失敗したら state は一切変わらない（01章 §3）
function Game.execute(state: any, command: any, ctx: Ctx): Result
	local handler = handlers[command.type]
	if not handler then
		return fail("UNKNOWN_COMMAND")
	end
	local work = deepClone(state)
	local result = handler(work, command, ctx)
	if result.ok then
		for k in state do
			state[k] = nil
		end
		for k, v in work do
			state[k] = v
		end
	end
	return result
end

-- 届け物（D-180）：別の保存場所（サーバーが M7b-5 で持つ）から届いた物を受け取り箱へ入れる
-- delivery = { id, kind, fromUserId, at, data? }。kind = "referral" は紹介で招待した側への報酬
-- 戻り値：(状態を変えたか, events)。同じ id の届け物は二度受け取らない（変えずに false）。
-- false のとき（受け取り済み・週の上限・知らない種類）も、サーバーは届け物を消してよい
function Game.grantDelivery(state: any, delivery: any, ctx: Ctx): (boolean, { any })
	if type(delivery) ~= "table" or type(delivery.id) ~= "string" then
		return false, {}
	end
	if delivery.kind == "referral" then
		local r = Game.execute(
			state,
			{ type = "GrantReferral", role = "inviter", userId = delivery.fromUserId, deliveryId = delivery.id },
			ctx
		)
		return r.ok, r.events or {}
	end
	return false, {}
end

-- 読み取り ---------------------------------------------------------------

Game.query = {}

function Game.query.snapshot(state: any, uid: string, master: any)
	local adv = state.adventurers[uid]
	if not adv then
		return nil
	end
	local _, slot = Party.find(state, uid)
	return Formulas.memberSnapshot(Party.memberDef(state, adv, slot or 1), master)
end

function Game.query.partySnapshots(state: any, partyIndex: number, master: any)
	return Party.snapshots(state, partyIndex, master)
end

function Game.query.expeditionOf(state: any, partyIndex: number)
	for _, e in state.expeditions do
		if e.partyIndex == partyIndex then
			return e
		end
	end
	return nil
end

function Game.query.progress(e: any, now: number)
	return Expedition.progressAt(e.log, now)
end

function Game.query.warehouse(state: any)
	return { used = Inventory.warehouseUsage(state), size = state.expansions.warehouseSize }
end

function Game.query.sellPrice(item: any, master: any): number
	return Inventory.equipmentSellPrice(item, master)
end

-- 未開封の宝箱：普通のダンジョンの山ごとの数（プレイヤーに見せてよいのはこれだけ：D-087）
function Game.query.chestsByDungeon(state: any, master: any): { any }
	local out = {}
	for _, d in master.dungeonList do
		local n = Chest.pileTotal(state, d.id)
		if n > 0 then
			table.insert(out, { dungeonId = d.id, count = n })
		end
	end
	return out
end

-- 未開封の宝箱：宝箱の山ごとの数（D-087, D-166。レアリティは返さない）
-- 普通の山はダンジョンの順、続けて特別な宝箱の山を鍵の順に並べる
function Game.query.chestsByPile(state: any, master: any): { any }
	local out = {}
	for _, d in master.dungeonList do
		local n = Chest.pileTotal(state, d.id)
		if n > 0 then
			table.insert(out, { pileKey = d.id, count = n })
		end
	end
	local others = {}
	for key in state.chests do
		if not master.dungeons[key] then
			table.insert(others, key)
		end
	end
	table.sort(others)
	for _, key in others do
		local n = Chest.pileTotal(state, key)
		if n > 0 then
			table.insert(out, { pileKey = key, count = n })
		end
	end
	return out
end

-- 未開封の宝箱のランクごとの数。開発・自動プレイ用（プレイヤーに見せない：D-087）
function Game.query.chestsByRank(state: any, master: any): { number }
	return Chest.countByRank(state, master)
end

-- 今日・明日の日替わりの特性（D-156、06章 §16）。帯の順に { band, dungeonId, traitId }
function Game.query.dailyTraits(now: number, master: any): any
	local day = Calendar.dayIndex(now)
	return {
		today = DailyTrait.forDay(day, master),
		tomorrow = DailyTrait.forDay(day + 1, master),
		nextDayAt = Calendar.nextDayStart(now),
	}
end

-- 今週の訪問者（D-158, D-170）：雇用画面のバナー用
-- { uniqueId, chance（候補1人ごと）, candidateSlots, owned, weekIndex, nextWeekAt }
function Game.query.weeklyVisitor(state: any, now: number, master: any): any
	return Visitor.summary(state, now, master)
end

-- フレンドボタン（D-157）：次に押せる時刻・今日押した回数・1日の上限・今押したときのゴールド
function Game.query.friend(state: any, now: number, friendCount: number, master: any): any
	local F = state.friend
	return {
		nextAt = F.nextAt,
		todayCount = if F.dayIndex == Calendar.dayIndex(now) then F.todayCount else 0,
		dailyCap = master.K.friendRewardDailyCap,
		gold = Friend.gold(state, friendCount, master),
		blocker = Friend.blocker(state, now, friendCount, master),
	}
end

-- 受け取り箱の中身（D-164）。宝箱は山ごとの数だけ（ランクは返さない：D-087）
function Game.query.inbox(state: any): { any }
	return Inbox.summary(state)
end

-- 今日・今週のクエスト（D-153）。{ daily = { entries, bonusDone }, weekly = ... }。entries の行に kind を添える
function Game.query.quests(state: any, master: any): any
	local out = {}
	for _, period in { "daily", "weekly" } do
		local book = state.quests[period]
		local entries = {}
		for _, e in book.entries do
			local row = master.quests[e.questId]
			table.insert(entries, {
				questId = e.questId,
				kind = if row then row.kind else nil,
				target = e.target,
				progress = e.progress,
				done = e.done,
			})
		end
		out[period] = { entries = entries, bonusDone = book.bonusDone }
	end
	return out
end

-- ログインボーナスのカレンダー（D-155）。day は次に受け取る位置、uniqueId はこの周の7日目のユニーク（いなければ nil）
function Game.query.loginCalendar(state: any, now: number, master: any): any
	local L = state.login
	local u = Login.uniqueFor(state, L.cycle, master)
	return {
		day = L.day,
		cycle = L.cycle,
		receivedToday = L.lastDayIndex >= Calendar.dayIndex(now),
		uniqueId = if u then u.id else nil,
	}
end

-- 今日のプレイ時間（D-154）
function Game.query.playtime(state: any, master: any): any
	local P = state.playtime
	local nextStep = Playtime.nextStep(state, master)
	return {
		seconds = P.seconds,
		capSeconds = master.K.playtimeDailyCapSeconds,
		claimedSteps = P.claimedSteps,
		nextMinutes = if nextStep then nextStep.minutes else nil,
	}
end

-- 休息ボーナスの残り秒（D-161）
function Game.query.restBonus(state: any): number
	return state.restBonusSeconds or 0
end

-- 今と次のマップイベント（D-152、06章 §12）。全員共通。next は予告の時間に入るまで nil
--   { current = { eventSlot, kindId, kind, placeId, startAt, closeAt, open, closesIn }, next = { ..., startsIn }?, nextAt }
function Game.query.mapEvent(now: number, master: any): any
	return MapEvent.status(now, master)
end

-- 旅の商人の品（D-152）。その時間帯のプレイヤーごとの品ぞろえと価格・買ったか
--   { eventSlot, open, items = { { baseId, rarity, grade, itemLevel, modifierId, modifierValue, price, bought } } }
--   その時間帯が商人でなければ nil
function Game.query.merchant(state: any, eventSlot: number, now: number, master: any): any
	local ev = MapEvent.eventAt(eventSlot, master)
	if ev.kind ~= "merchant" then
		return nil
	end
	local bought = Merchant.boughtFor(state, eventSlot)
	local items = {}
	for i, g in Merchant.goods(state, eventSlot, master) do
		local row = table.clone(g.item)
		row.price = g.price
		row.bought = bought[i] == true
		table.insert(items, row)
	end
	return {
		eventSlot = eventSlot,
		open = MapEvent.check(eventSlot, "merchant", now, master) == nil,
		items = items,
	}
end

-- レイドボスの進み具合（D-152。自分専用）。その時間帯がレイドでなければ nil
--   { eventSlot, hp, damage, defeated, parties（出発したパーティ）, arrived }。まだ誰も出発していなければ HP の見込みと damage = 0
function Game.query.raid(state: any, eventSlot: number, master: any): any
	if MapEvent.eventAt(eventSlot, master).kind ~= "raid" then
		return nil
	end
	local r = Raid.stateFor(state, eventSlot)
	if r then
		return table.clone(r)
	end
	return {
		eventSlot = eventSlot,
		hp = Raid.hp(state, eventSlot, master),
		damage = 0,
		defeated = false,
		parties = {},
		arrived = 0,
	}
end

-- レアダンジョンの行き先（D-152, D-171, D-185）：{ dungeonId（強さ）, pileKey（宝箱の山）, joined（出発済みのパーティ番号） }
function Game.query.rareDungeon(state: any, eventSlot: number, master: any): any
	local t = MapEvent.rareDungeonTarget(state, master)
	local joined = {}
	for k, v in state.rareDungeonSlots or {} do
		if v == eventSlot then
			table.insert(joined, tonumber(k))
		end
	end
	table.sort(joined)
	return { dungeonId = t.dungeonId, pileKey = t.pileKey, joined = joined }
end

-- レイドのパーティのダメージの見込み（出発したときに入るダメージ。D-152）
function Game.query.raidDamage(state: any, partyIndex: number, master: any): number
	return Raid.damage(Party.snapshots(state, partyIndex, master), master.K)
end

function Game.query.trainingQuote(state: any, uid: string, targetLevel: number, master: any)
	return Training.quote(state, state.adventurers[uid], targetLevel, master)
end

function Game.query.trainingSessionCost(level: number, master: any): number
	return Training.sessionCost(level, master.K)
end

function Game.query.rebirthCost(state: any, uid: string, master: any): number
	return Rebirth.cost(state.adventurers[uid], master)
end

function Game.query.expToNext(level: number, master: any, rebirthCount: number?): number
	return Formulas.expToNext(level, master.K, rebirthCount)
end

return Game
