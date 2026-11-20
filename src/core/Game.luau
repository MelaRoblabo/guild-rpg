--!strict
-- ゲームの窓口（docs/system/01_architecture.md §3、05_commands.md）
--   Game.newState(master, seed, now)
--   Game.advance(state, ctx) -> events        すべてのコマンドの前に呼ぶ（入口側の責任）
--   Game.execute(state, command, ctx) -> { ok, events } | { ok = false, error }
--   Game.query.*                              表示用の読み取り（状態を変えない）
-- ctx = { now: number, master: any, online: boolean }

local Chest = require("./Chest")
local Expedition = require("./Expedition")
local Formulas = require("./Formulas")
local Growth = require("./Growth")
local Guild = require("./Guild")
local Appearance = require("./Appearance")
local Hiring = require("./Hiring")
local JobChange = require("./JobChange")
local Inventory = require("./Inventory")
local Migration = require("./Migration")
local Party = require("./Party")
local Rebirth = require("./Rebirth")
local Rng = require("./Rng")
local Training = require("./Training")

local Game = {}

export type Ctx = { now: number, master: any, online: boolean }
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
		settings = { autoSell = { enabled = false, maxRarity = 1, keepModified = true } },
		stats = {},
		createdAt = now,
		lastAdvancedAt = now,
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

-- 派遣（D-026）。departAt を指定できる（自動再派遣は帰還時刻から出発する）
-- 派遣費（D-079）は呼び出し側で払えることを確かめてから呼ぶ
local function dispatch(state: any, partyIndex: number, dungeonId: string, departAt: number, master: any): any
	local fee = master.dungeons[dungeonId].dispatchFee or 0
	state.gold -= fee
	bump(state, "goldSpentOnFees", fee)
	local _, seed = takeRng(state)
	local snaps = Party.snapshots(state, partyIndex, master)
	local log =
		Expedition.simulate({ seed = seed, departAt = departAt, dungeonId = dungeonId, members = snaps }, master)
	local uid = newUid(state, "ex")
	local memberUids = {}
	for _, s in snaps do
		table.insert(memberUids, s.uid)
	end
	local e = {
		uid = uid,
		partyIndex = partyIndex,
		dungeonId = dungeonId,
		seed = seed,
		departAt = departAt,
		returnAt = departAt + log.totalSeconds,
		memberUids = memberUids,
		log = log,
	}
	state.expeditions[uid] = e
	bump(state, "expeditions")
	return e
end

-- 自動再派遣できない理由（できるなら nil）
local function autoRepeatBlocker(state: any, master: any, dungeonId: string): string?
	if state.gold < (master.dungeons[dungeonId].dispatchFee or 0) then
		return "NOT_ENOUGH_GOLD" -- D-079
	end
	if Inventory.warehouseFree(state) <= 0 then
		return "WAREHOUSE_FULL"
	end
	if #state.chests >= master.K.chestStorageMax then
		return "CHEST_STORAGE_FULL"
	end
	return nil
end

-- 帰還処理：報酬を状態に反映する
local function collect(state: any, e: any, master: any, events: { any })
	local K = master.K
	local log = e.log
	local r = log.rewards
	local rng = takeRng(state)

	state.gold += r.gold
	for itemId, c in r.items do
		Inventory.addItem(state, itemId, c)
	end
	-- 保管が上限なら、入りきらない宝箱は持ち帰れない（D-083：出発を止めると詰むため）
	local leftBehind = 0
	for _, c in r.chests do
		if #state.chests >= K.chestStorageMax then
			leftBehind += 1
		else
			table.insert(
				state.chests,
				{ uid = newUid(state, "ch"), rank = c.rank, dungeonId = e.dungeonId, obtainedAt = e.returnAt }
			)
		end
	end
	bump(state, "chestsLeftBehind", leftBehind)

	-- 経験値（D-041：生存者で等分済み。個人倍率はここで掛ける）。順序を固定するため隊列順に処理
	local levelUps = {}
	for _, uid in e.memberUids do
		local amount = r.exp[uid]
		local adv = state.adventurers[uid]
		if amount and amount > 0 and adv then
			local levels = Growth.addExp(adv, amount, rng, master, state.equipment)
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
		chests = #r.chests - leftBehind,
		chestsLeftBehind = leftBehind,
		gold = r.gold,
		items = r.items,
		guildExp = guildExp,
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

function Game.advance(state: any, ctx: Ctx): { any }
	local master = ctx.master
	local events = {}
	while true do
		-- 帰還時刻が最も早い探索（同時刻は uid の数値順）
		local nextE = nil
		for _, e in state.expeditions do
			if e.returnAt <= ctx.now then
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
		if nextE == nil then
			break
		end
		collect(state, nextE, master, events)

		local party = state.parties[nextE.partyIndex]
		if party and party.autoRepeat then
			local blocker = autoRepeatBlocker(state, master, party.autoRepeat.dungeonId)
			if not ctx.online then
				-- オフライン中は再派遣しない（企画書§16.8 案A）。設定は残す
				continue
			elseif blocker then
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
			end
		end
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
	if
		Party.isAdventurerBusy(state, adv.uid) or (item.equippedBy and Party.isAdventurerBusy(state, item.equippedBy))
	then
		return fail("ADVENTURER_ON_EXPEDITION")
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
	local fee = ctx.master.dungeons[cmd.dungeonId].dispatchFee or 0
	if state.gold < fee then
		return fail("NOT_ENOUGH_GOLD") -- D-079
	end
	local e = dispatch(state, cmd.partyIndex, cmd.dungeonId, ctx.now, ctx.master)
	return {
		ok = true,
		events = {
			{
				type = "Dispatched",
				at = ctx.now,
				partyIndex = cmd.partyIndex,
				dungeonId = cmd.dungeonId,
				returnAt = e.returnAt,
				fee = fee,
			},
		},
	}
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
	-- 解錠技術（D-078）：開けられるのは unlockRank 以下の宝箱だけ。開けられない宝箱はギルドに残る
	local unlockRank = state.expansions.unlockRank
	local targets = {}
	if cmd.chestUids == "all" then
		for _, c in state.chests do
			if c.rank <= unlockRank then
				table.insert(targets, c)
			end
		end
		if #targets == 0 and #state.chests > 0 then
			return fail("CHEST_RANK_TOO_HIGH")
		end
	else
		for _, uid in cmd.chestUids do
			for _, c in state.chests do
				if c.uid == uid then
					if c.rank > unlockRank then
						return fail("CHEST_RANK_TOO_HIGH")
					end
					table.insert(targets, c)
				end
			end
		end
	end
	if #targets == 0 then
		return fail("NO_CHEST")
	end
	local perChest = Chest.maxEquipmentPerChest(ctx.master)
	local events = {}
	for _, c in targets do
		if Inventory.warehouseFree(state) < perChest then
			break
		end
		local rng = takeRng(state)
		local opened = Chest.open(state, c, rng, ctx.master)
		-- 自動売却（06章 §6）：保護中の品は対象外（開けたばかりの品は保護されていない）
		local auto = state.settings.autoSell
		if auto.enabled then
			local kept = {}
			opened.autoSold = {}
			opened.autoSoldGold = 0
			for _, uid in opened.equipmentUids do
				local item = state.equipment[uid]
				if item.rarity <= auto.maxRarity and not (auto.keepModified and item.modifierId) then
					local price = Inventory.equipmentSellPrice(item, ctx.master)
					state.gold += price
					opened.autoSoldGold += price
					table.insert(opened.autoSold, { baseId = item.baseId, rarity = item.rarity, grade = item.grade })
					state.equipment[uid] = nil
					bump(state, "goldFromSales", price)
				else
					table.insert(kept, uid)
				end
			end
			opened.equipmentUids = kept
		end
		local idx = table.find(state.chests, c)
		if idx then
			table.remove(state.chests, idx)
		end
		bump(state, "chestsOpened")
		if state.stats.firstChestOpenedAt == nil then
			state.stats.firstChestOpenedAt = ctx.now
		end
		table.insert(events, { type = "ChestOpened", at = ctx.now, result = opened })
	end
	if #events == 0 then
		return fail("WAREHOUSE_FULL")
	end
	return { ok = true, events = events }
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
		candidates = Hiring.rollCandidates(state, rng, ctx.master),
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

handlers.HireReroll = function(state, cmd, ctx)
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
	-- Q-021：残す方（keep）と新しい結果を並べる。指定がなければ合計値の高い方を残す
	h.previousRoll = Rebirth.pickKept(h.previousRoll, h.currentRoll, cmd.keep)
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
	return { ok = true, events = { { type = "Hired", at = ctx.now, uid = uid } } }
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

handlers.RebirthReroll = function(state, cmd, ctx)
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
	r.previousBonus = Rebirth.pickKept(r.previousBonus, r.currentBonus, cmd.keep) -- Q-021
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
	return {
		ok = true,
		events = {
			{
				type = "Reborn",
				at = ctx.now,
				uid = adv.uid,
				rebirthCount = adv.rebirthCount,
				levelCap = adv.levelCap,
				giftAdded = giftId,
			},
		},
	}
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
	return {
		ok = true,
		events = {
			{
				type = "Trained",
				at = ctx.now,
				uid = adv.uid,
				sessions = r.sessions,
				gold = r.gold,
				level = adv.level,
				levelsGained = #r.levels,
			},
		},
	}
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

handlers.SetAutoSell = function(state, cmd, _ctx)
	local r = tonumber(cmd.maxRarity) or state.settings.autoSell.maxRarity
	if r < 1 or r > 5 then
		return fail("INVALID_RARITY")
	end
	state.settings.autoSell = {
		enabled = cmd.enabled == true,
		maxRarity = r,
		keepModified = if cmd.keepModified == nil then true else cmd.keepModified == true,
	}
	return { ok = true, events = {} }
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
