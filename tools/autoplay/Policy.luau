--!strict
-- 自動プレイヤーの方針（docs/system/09_cli_sim_autoplay.md §3）
-- greedy：行ける中で1秒あたりの経験値が最も多いダンジョンへ。良い装備は即装備、不要品は売却、
--         買える拡張はすぐ買う、パーティは雇用で埋める、上限レベルに達したら転生する（費用が払えれば）。
--         遅れている冒険者には修練の護符を持たせ（D-082）、余ったゴールドでトレーニングする（D-076）。

local Expedition = require("../../src/core/Expedition")
local Formulas = require("../../src/core/Formulas")
local Game = require("../../src/core/Game")
local Inventory = require("../../src/core/Inventory")
local Party = require("../../src/core/Party")
local Rebirth = require("../../src/core/Rebirth")
local Rng = require("../../src/core/Rng")
local Training = require("../../src/core/Training")

local Policy = {}

local LINE_ORDER = { warrior = 1, scout = 2, mage = 3, support = 4 }
local WANT_LINES = { "warrior", "scout", "mage", "support" }
local EXPANSION_PRIORITY = { "exp_party", "exp_unlock", "exp_warehouse", "exp_roster", "exp_training", "exp_candidate" }
-- トレーニングに使うのは「転生の備え」を除いた所持金のこの割合まで
local TRAIN_BUDGET_SHARE = 0.5

export type Ctx = { now: number, master: any, online: boolean }

local function exec(state: any, cmd: any, ctx: Ctx): any
	return Game.execute(state, cmd, ctx)
end

-- 装備の評価（性能値の合計 × 倍率）
local function itemScore(item: any, master: any): number
	local base = master.equipmentBases[item.baseId]
	local raw = (base.atk or 0) + (base.pdef or 0) + (base.mdef or 0)
	for _, v in base.stats or {} do
		raw += v
	end
	local s = raw * Formulas.equipMult(item.rarity, item.grade, item.itemLevel or 1, master.K)
	if item.modifierId then
		s *= 1.05
	end
	return s
end
Policy.itemScore = itemScore

local function openAll(state: any, ctx: Ctx)
	exec(state, { type = "OpenChests" }, ctx)
end

-- 遅れている冒険者（最も進んだ人より転生回数が2以上少ない）
local function isCatchingUp(state: any, adv: any): boolean
	local maxReb = 0
	for _, a in state.adventurers do
		maxReb = math.max(maxReb, a.rebirthCount)
	end
	return adv.rebirthCount <= maxReb - 2
end

local function equipBest(state: any, ctx: Ctx)
	local master = ctx.master
	for uid in table.clone(state.adventurers) do
		local adv = state.adventurers[uid]
		if adv and not Party.isAdventurerBusy(state, uid) then
			local catching = isCatchingUp(state, adv)
			for _, slot in Inventory.SLOTS do
				adv = state.adventurers[uid]
				local cur = adv.equipment[slot]
				local function score(e: any): number
					if catching and slot == "sub" then
						-- 遅れている人は補助枠に経験値補正を優先（D-082）
						return Formulas.equipExpPct(e, master) * 10000 + itemScore(e, master)
					end
					return itemScore(e, master)
				end
				local curScore = if cur then score(state.equipment[cur]) else -1
				local best, bestScore = nil, curScore
				for euid, e in state.equipment do
					if e.equippedBy == nil and master.equipmentBases[e.baseId].slot == slot then
						if Inventory.canEquip(adv.jobId, e.baseId, master) then
							local sc = score(e)
							if sc > bestScore then
								best, bestScore = euid, sc
							end
						end
					end
				end
				if best then
					exec(state, { type = "Equip", adventurerUid = uid, equipmentUid = best }, ctx)
				end
			end
		end
	end
end

-- 倉庫の装備は「枠×種類ごとに上位2個」だけ残して売る
local function sellJunk(state: any, ctx: Ctx)
	local master = ctx.master
	local groups = {}
	for uid, e in state.equipment do
		if e.equippedBy == nil and not e.locked then
			local b = master.equipmentBases[e.baseId]
			local key = b.slot .. ":" .. b.kind .. (if b.expPct then ":exp" else "")
			groups[key] = groups[key] or {}
			table.insert(groups[key], { uid = uid, score = itemScore(e, master) })
		end
	end
	local toSell = {}
	for _, list in groups do
		table.sort(list, function(a, b)
			return a.score > b.score
		end)
		for i = 3, #list do
			table.insert(toSell, list[i].uid)
		end
	end
	if #toSell > 0 then
		exec(state, { type = "Sell", equipmentUids = toSell }, ctx)
	end
	for id, n in state.items do
		local it = master.items[id]
		if it and it.kind == "sellable" and n > 0 then
			exec(state, { type = "Sell", itemId = id, count = n }, ctx)
		end
	end
end

local function buyExpansions(state: any, ctx: Ctx)
	local bought = true
	while bought do
		bought = false
		for _, id in EXPANSION_PRIORITY do
			local r = exec(state, { type = "BuyExpansion", expansionId = id }, ctx)
			if r.ok then
				bought = true
			end
		end
	end
end

-- 転生：無料3回＋チケットを「残りの枚数 ÷ 上限に達した人数」まで使い、合計の高い方を採用
local function rebirthCapped(state: any, ctx: Ctx, stats: any)
	local capped = {}
	for uid, a in state.adventurers do
		if
			a.level >= a.levelCap
			and a.levelCap < ctx.master.K.levelCapMax
			and not Party.isAdventurerBusy(state, uid)
		then
			table.insert(capped, uid)
		end
	end
	table.sort(capped)
	for i, uid in capped do
		if not exec(state, { type = "RebirthStart", adventurerUid = uid }, ctx).ok then
			continue -- 転生費用が足りなければ待つ（D-080）
		end
		local budget = ctx.master.K.rebirthFreeRerolls
			+ math.floor((state.items.itm_slot_ticket or 0) / (#capped - i + 1))
		for _ = 1, budget do
			if not exec(state, { type = "RebirthReroll" }, ctx).ok then
				break
			end
			stats.rebirthRerolls += 1
		end
		local r = state.rebirthSession
		local which = "current"
		if r.previousBonus and Rebirth.total(r.previousBonus) > Rebirth.total(r.currentBonus) then
			which = "previous"
		end
		exec(state, { type = "RebirthChoose", which = which }, ctx)
		stats.rebirths += 1
		local adv = state.adventurers[uid]
		if adv.rebirthCount > stats.maxRebirth then
			stats.maxRebirth = adv.rebirthCount
			table.insert(stats.timeline, { at = ctx.now, what = `初めて転生{adv.rebirthCount}回目に到達` })
		end
	end
end

local function rosterCount(state: any): number
	local n = 0
	for _ in state.adventurers do
		n += 1
	end
	return n
end

-- 転生の備え：上限まで残り10レベル以内の人の転生費用の合計＋条件を満たした解錠技術・パーティ枠の費用
local function rebirthReserve(state: any, master: any): number
	local sum = 0
	for _, id in { "exp_unlock", "exp_party" } do
		local step = Game.nextExpansionStep(state, id, master)
		if
			step
			and state.guild.level >= step.guildLevel
			and (step.requiresClear == nil or state.clearedDungeons[step.requiresClear])
		then
			sum += step.gold
		end
	end
	for _, a in state.adventurers do
		if a.levelCap < master.K.levelCapMax and a.level >= a.levelCap - 10 then
			sum += Rebirth.cost(a, master)
		end
	end
	return sum
end

-- トレーニング（D-076）：レベルの低い人から、予算内で上げられるところまで
local function trainBehind(state: any, ctx: Ctx, stats: any)
	local master = ctx.master
	local list = {}
	for uid, a in state.adventurers do
		if
			not Party.isAdventurerBusy(state, uid)
			and not (state.rebirthSession and state.rebirthSession.adventurerUid == uid)
			and a.level < Training.levelCap(a, state, master)
		then
			table.insert(list, uid)
		end
	end
	table.sort(list, function(x, y)
		local a, b = state.adventurers[x], state.adventurers[y]
		if a.level ~= b.level then
			return a.level < b.level
		end
		return x < y
	end)
	for _, uid in list do
		local budget = math.floor((state.gold - rebirthReserve(state, master)) * TRAIN_BUDGET_SHARE)
		if budget <= 0 then
			return
		end
		local adv = state.adventurers[uid]
		local cap = Training.levelCap(adv, state, master)
		-- 予算で届く最も高いレベル（二分探索）
		local lo, hi, best = adv.level + 1, cap, nil
		while lo <= hi do
			local mid = (lo + hi) // 2
			local q = Training.quote(state, adv, mid, master)
			if q.gold <= budget then
				best, lo = q, mid + 1
			else
				hi = mid - 1
			end
		end
		if best and best.sessions > 0 then
			local r = exec(state, { type = "Train", adventurerUid = uid, sessions = best.sessions }, ctx)
			if r.ok then
				stats.trainedLevels += r.events[1].levelsGained
			end
		end
	end
end

-- パーティに入っていない冒険者の系統ごとの数と、空き枠が求める系統
local function hireIfNeeded(state: any, ctx: Ctx, stats: any)
	local master = ctx.master
	local need = state.expansions.partySlots * Party.SIZE
	while rosterCount(state) < math.min(need, state.expansions.rosterSize) and state.gold >= master.K.hireCost do
		-- 足りない系統を数える
		local have = { warrior = 0, scout = 0, mage = 0, support = 0 }
		for _, a in state.adventurers do
			local line = master.jobs[a.jobId].line
			have[line] += 1
		end
		local wantLine = "warrior"
		local fewest = math.huge
		for _, l in WANT_LINES do
			if have[l] < fewest then
				fewest, wantLine = have[l], l
			end
		end
		if not exec(state, { type = "HireStart" }, ctx).ok then
			break
		end
		local pick = 1
		for i, c in state.hireSession.candidates do
			if c.kind == "unique" or master.jobs[c.jobId].line == wantLine then
				pick = i
				if c.kind == "unique" then
					break
				end
			end
		end
		exec(state, { type = "HirePick", candidateIndex = pick }, ctx)
		for _ = 1, master.K.hireFreeRerolls do
			exec(state, { type = "HireReroll" }, ctx)
		end
		local h = state.hireSession
		local which = "current"
		if h.previousRoll and Rebirth.total(h.previousRoll) > Rebirth.total(h.currentRoll) then
			which = "previous"
		end
		exec(state, { type = "HireChoose", which = which }, ctx)
		stats.hired += 1
	end
end

-- 空いている冒険者をパーティに入れ、系統の順（戦士系→探索系→魔法系→支援系）に並べる
local function arrangeParties(state: any, ctx: Ctx)
	local master = ctx.master
	local free = {}
	for uid in state.adventurers do
		if Party.find(state, uid) == nil then
			table.insert(free, uid)
		end
	end
	table.sort(free)
	for i = 1, #state.parties do
		if not Party.isBusy(state, i) and not state.rebirthSession then
			local members = {}
			for slot = 1, Party.SIZE do
				local uid = state.parties[i].slots[slot]
				if uid ~= Party.EMPTY then
					table.insert(members, uid)
				end
			end
			while #members < Party.SIZE and #free > 0 do
				table.insert(members, table.remove(free, 1))
			end
			table.sort(members, function(a, b)
				local la = LINE_ORDER[master.jobs[state.adventurers[a].jobId].line]
				local lb = LINE_ORDER[master.jobs[state.adventurers[b].jobId].line]
				if la ~= lb then
					return la < lb
				end
				return a < b
			end)
			for slot = 1, Party.SIZE do
				exec(state, { type = "SetPartySlot", partyIndex = i, slot = slot }, ctx)
			end
			for slot, uid in members do
				exec(state, { type = "SetPartySlot", partyIndex = i, slot = slot, adventurerUid = uid }, ctx)
			end
		end
	end
end

-- 行き先：踏破率50%以上で1秒あたりの経験値が最大の所。未踏破で40%以上なら挑戦
local function chooseDungeon(state: any, partyIndex: number, ctx: Ctx, rng: Rng.Rng): string?
	local master = ctx.master
	local snaps = Party.snapshots(state, partyIndex, master)
	if #snaps == 0 then
		return nil
	end
	local unlocked = {}
	for _, d in master.dungeonList do
		if state.unlockedDungeons[d.id] and (d.dispatchFee or 0) <= state.gold then -- 派遣費（D-079）
			table.insert(unlocked, d)
		end
	end
	if #unlocked == 0 then
		return nil
	end
	-- 深い方から試算し、踏破率50%以上のダンジョンが2つ見つかったら打ち切る
	local best, bestScore, push = unlocked[1].id, -1, nil
	local qualified = 0
	for i = #unlocked, 1, -1 do
		local d = unlocked[i]
		local clears, exp, secs = 0, 0, 0
		for _ = 1, 12 do
			local log =
				Expedition.simulate({ seed = rng:nextU32(), departAt = 0, dungeonId = d.id, members = snaps }, master)
			if log.result == "clear" then
				clears += 1
			end
			for _, v in log.rewards.exp do
				exp += v
			end
			secs += log.totalSeconds
		end
		local rate = clears / 12
		if not state.clearedDungeons[d.id] and rate >= 0.4 then
			push = d.id
		end
		if rate >= 0.5 then
			qualified += 1
			if exp / secs > bestScore then
				best, bestScore = d.id, exp / secs
			end
			if qualified >= 2 then
				break
			end
		end
	end
	return push or best
end

-- 開けられない宝箱が溜まっていて、解錠技術の次の段階の条件を満たしているなら、そのための貯金を優先する
local function savingForUnlock(state: any, master: any): boolean
	local step = Game.nextExpansionStep(state, "exp_unlock", master)
	if not step or state.guild.level < step.guildLevel then
		return false
	end
	local locked = 0
	for r, n in Game.query.chestsByRank(state, master) do
		if r > state.expansions.unlockRank then
			locked += n
		end
	end
	return locked >= 300 -- 開けられない宝箱がかなり溜まったときだけ
end

function Policy.manage(state: any, ctx: Ctx, rng: Rng.Rng, stats: any)
	openAll(state, ctx)
	equipBest(state, ctx)
	sellJunk(state, ctx)
	buyExpansions(state, ctx)
	local saving = savingForUnlock(state, ctx.master)
	if saving then
		stats.savingTicks = (stats.savingTicks or 0) + 1
	else
		rebirthCapped(state, ctx, stats)
	end
	hireIfNeeded(state, ctx, stats)
	if not saving then
		trainBehind(state, ctx, stats)
	end
	arrangeParties(state, ctx)
	equipBest(state, ctx)
	for i = 1, #state.parties do
		if not Party.isBusy(state, i) then
			local d = chooseDungeon(state, i, ctx, rng)
			if d then
				exec(state, { type = "Dispatch", partyIndex = i, dungeonId = d }, ctx)
			end
		end
	end
end

return Policy
