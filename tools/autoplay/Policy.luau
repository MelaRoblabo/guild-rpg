--!strict
-- 自動プレイヤーの方針（docs/system/09_cli_sim_autoplay.md §3）
-- greedy：行ける中で1秒あたりの経験値が最も多いダンジョンへ。良い装備は即装備、不要品は売却、
--         買える拡張はすぐ買う、パーティは雇用で埋める、上限レベルに達したら転生する（費用が払えれば）。
--         遅れている冒険者には修練の護符を持たせ（D-082）、余ったゴールドでトレーニングする（D-076）。
-- M7b-6：受け取り箱を受け取る（D-164）、開封のあとに一括売却（D-167）、フレンドボタン（D-157。友達の数は ctx.friendCount）、
--         マップイベント（D-152）は出ている時間帯に空いているパーティをレアダンジョン・レイドへ、商人は余裕があれば買う。
--         クエスト・ログインボーナス・プレイ時間・今週の訪問者は、ふだんの行動と advance で自然に進む。

local Expedition = require("../../src/core/Expedition")
local Formulas = require("../../src/core/Formulas")
local Game = require("../../src/core/Game")
local Inventory = require("../../src/core/Inventory")
local Party = require("../../src/core/Party")
local Rebirth = require("../../src/core/Rebirth")
local Rng = require("../../src/core/Rng")
local Training = require("../../src/core/Training")

local Policy = {}

-- 方針ごとの設定（docs/system/09_cli_sim_autoplay.md §3）
--   greedy    行ける中で1秒あたりの経験値が最も多い所（踏破率50%以上）。雇用は無料の引き直しのみ
--   cautious  踏破率80%以上の所だけ。未踏破への挑戦も70%以上から
--   collector 雇用でもチケットを使って粘る（合計130以上が出るまで、1人あたり最大30枚）。転生の目標も高め
local PRESETS = {
	greedy = { clearMin = 0.5, pushMin = 0.4, hireGood = 110, hireTickets = 0, rebirthGood = 0.7 },
	cautious = { clearMin = 0.8, pushMin = 0.7, hireGood = 110, hireTickets = 0, rebirthGood = 0.7 },
	collector = { clearMin = 0.5, pushMin = 0.4, hireGood = 130, hireTickets = 30, rebirthGood = 0.75 },
}
local params = PRESETS.greedy

function Policy.use(name: string)
	assert(PRESETS[name], `未知の方針: {name}`)
	params = PRESETS[name]
end

local LINE_ORDER = { warrior = 1, scout = 2, mage = 3, support = 4 }
local WANT_LINES = { "warrior", "scout", "mage", "support" }
local EXPANSION_PRIORITY = { "exp_party", "exp_warehouse", "exp_roster", "exp_training", "exp_candidate" }
-- トレーニングに使うのは「転生の備え」を除いた所持金のこの割合まで
local TRAIN_BUDGET_SHARE = 0.5

export type Ctx = { now: number, master: any, online: boolean, friendCount: number? }

-- 行動の設定（試し方の設定で、ゲームの数値ではない。tools/autoplay/Schedule.luau の behavior を Policy.configure で入れる）
local behavior: { [string]: any } = {
	mapEvents = true,
	merchant = true,
	merchantBudgetShare = 0.3,
	bulkSell = true,
}

function Policy.configure(b: { [string]: any })
	for k, v in b do
		behavior[k] = v
	end
end

-- 報酬の入手先を数えるための聞き手（tools/autoplay/Ledger.luau）。listener(state, cmd, result, extra)
--   extra：ClaimInbox は受け取る前の受け取り箱、Sell / BulkSell は売る前の売却額（uid → ゴールド）
local listener: ((any, any, any, any, number?) -> ())? = nil
function Policy.setListener(fn: ((any, any, any, any, number?) -> ())?)
	listener = fn
end

local function exec(state: any, cmd: any, ctx: Ctx): any
	local extra = nil
	if listener then
		if cmd.type == "ClaimInbox" then
			extra = table.clone(state.inbox)
		elseif cmd.type == "Sell" or cmd.type == "BulkSell" then
			extra = {}
			for _, uid in cmd.equipmentUids or {} do
				local e = state.equipment[uid]
				if e then
					extra[uid] = Game.query.sellPrice(e, ctx.master)
				end
			end
		end
	end
	local r = Game.execute(state, cmd, ctx)
	if listener and r.ok then
		(listener :: any)(state, cmd, r, extra, ctx.now) -- 5つ目は時刻（MX の出来事の記録用）
	end
	return r
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

-- 開けられる宝箱の山を、まとめ開き（D-089）で開けられるだけ開ける
-- 1回のまとめ開きのあとに、出た装備のうち「今の装備より弱い」ものを一括売却する（D-167, D-175。修飾語つきも：D-207）
local function openAll(state: any, ctx: Ctx)
	for _, c in Game.query.chestsByPile(state, ctx.master) do
		for _ = 1, 1000 do
			local r = exec(state, { type = "OpenChests", pileKey = c.pileKey }, ctx)
			if not r.ok then
				break
			end
			if behavior.bulkSell then
				local uids = {}
				for _, ev in r.events do
					if ev.type == "ChestsOpened" then
						for _, list in { ev.normal, ev.special } do
							for _, res in list do
								for _, uid in res.equipmentUids do
									table.insert(uids, uid)
								end
							end
						end
					end
				end
				if #uids > 0 then
					exec(state, { type = "BulkSell", equipmentUids = uids }, ctx) -- 弱い品がなければ失敗するだけ
				end
			end
		end
	end
end

-- 受け取り箱をまとめて受け取る（D-164）。達成したクエストとボーナスもここで受け取る（D-286：受け取り箱を通らない）
local function claimInbox(state: any, ctx: Ctx)
	if #state.inbox > 0 then
		exec(state, { type = "ClaimInbox" }, ctx)
	end
	for _, period in { "daily", "weekly" } do
		local book = state.quests and state.quests[period]
		if book then
			for _, entry in book.entries do
				if entry.done and not entry.claimed then
					exec(state, { type = "ClaimQuest", period = period, questId = entry.questId }, ctx)
				end
			end
			if book.bonusDone and not book.bonusClaimed then
				exec(state, { type = "ClaimQuestBonus", period = period }, ctx)
			end
		end
	end
end

-- フレンドボタン（D-157）：友達がいる想定（ctx.friendCount > 0）のときだけ、押せるなら押す
local function pressFriend(state: any, ctx: Ctx)
	local n = ctx.friendCount or 0
	if n > 0 and Game.query.friend(state, ctx.now, n, ctx.master).blocker == nil then
		exec(state, { type = "ClaimFriendReward" }, ctx)
	end
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
	-- 売却用アイテム（素材）は手に入れたときに自動で売られる（D-167）
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

-- 加算分の上限比（4項目の平均。D-074 の「良い結果」の定義）
local function bonusRatio(bonus: any, maxs: any): number
	local sum, n = 0, 0
	for _, k in { "str", "mag", "agi", "dex" } do
		if maxs[k] > 0 then
			sum += bonus[k] / maxs[k]
			n += 1
		end
	end
	return if n > 0 then sum / n else 1
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
		-- D-086：上限比の平均が rebirthGood 以上の結果が出たらその場で採用。予算を使い切ったら前回・今回の良い方
		local budget = ctx.master.K.rebirthFreeRerolls
			+ math.floor((state.items.itm_slot_ticket or 0) / (#capped - i + 1))
		local which = nil
		for _ = 0, budget do
			local r = state.rebirthSession
			if bonusRatio(r.currentBonus, r.bonusMax) >= params.rebirthGood then
				which = "current"
				break
			end
			if not exec(state, { type = "RebirthReroll" }, ctx).ok then
				break
			end
			stats.rebirthRerolls += 1
		end
		local r = state.rebirthSession
		if which == nil then
			which = "current"
			if r.previousBonus and Rebirth.total(r.previousBonus) > Rebirth.total(r.currentBonus) then
				which = "previous"
			end
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

-- 転生の備え：上限まで残り10レベル以内の人の転生費用の合計＋条件を満たしたパーティ枠の費用
local function rebirthReserve(state: any, master: any): number
	local sum = 0
	for _, id in { "exp_party" } do
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

-- 商人の計測（D-198 の価格倍率の見直し用。行動には使わない）
local merchantSeen: { [number]: boolean } = {}
local shopAt: (state: any, ctx: Ctx, eventSlot: number) -> ()
local merchantStats = { offers = 0, priceSum = 0, upgrades = 0, affordable = 0, bought = 0, spent = 0 }
Policy.merchantStats = merchantStats

-- 旅の商人（D-152, D-274）：今の時間帯が商人で、まだ送っていなければ、空いているパーティ（番号の大きい方）を送る。
-- 着いたら、誰かの今の装備より良い品を、予算（転生の備えを除いた所持金 × merchantBudgetShare）内で買い、すぐ帰る（Leave）
local function buyFromMerchant(state: any, ctx: Ctx)
	if not behavior.merchant then
		return
	end
	local master = ctx.master
	local cur = Game.query.mapEvent(ctx.now, master).current
	if cur.kind == "merchant" and cur.open then
		for i = #state.parties, 1, -1 do
			if not Party.isBusy(state, i) and not Party.isEmpty(state.parties[i]) then
				if exec(state, { type = "DispatchEvent", partyIndex = i, eventSlot = cur.eventSlot }, ctx).ok then
					break
				end
			end
		end
	end
	for _, p in Game.query.merchantPresence(state, ctx.now, master) do
		if p.phase == "here" then
			shopAt(state, ctx, p.eventSlot)
			exec(state, { type = "LeaveMerchant", partyIndex = p.partyIndex }, ctx)
		end
	end
end

-- 商人のところで買う（パーティが着いている時間帯）
shopAt = function(state: any, ctx: Ctx, eventSlot: number)
	local master = ctx.master
	local cur = { eventSlot = eventSlot }
	local m = Game.query.merchant(state, eventSlot, ctx.now, master)
	if not m or not m.open then
		return
	end
	-- 測るだけ（行動は変えない）：品を見た回数・そのうち誰かの装備より良い品・予算内だった品・買った品と額
	local seen = merchantSeen[cur.eventSlot] == nil
	merchantSeen[cur.eventSlot] = true
	for i, item in m.items do
		if not item.bought then
			local budget = (state.gold - rebirthReserve(state, master)) * behavior.merchantBudgetShare
			local slot = master.equipmentBases[item.baseId].slot
			local sc = itemScore(item, master)
			local upgrade = false
			for _, a in state.adventurers do
				if Inventory.canEquip(a.jobId, item.baseId, master) then
					local eq = a.equipment[slot]
					if eq == nil or itemScore(state.equipment[eq], master) < sc then
						upgrade = true
						break
					end
				end
			end
			if seen then
				merchantStats.offers += 1
				merchantStats.priceSum += item.price
				if upgrade then
					merchantStats.upgrades += 1
					if item.price <= budget then
						merchantStats.affordable += 1
					end
				end
			end
			if item.price <= budget and upgrade then
				local r = exec(state, { type = "BuyFromMerchant", eventSlot = cur.eventSlot, itemIndex = i }, ctx)
				if r.ok then
					merchantStats.bought += 1
					merchantStats.spent += item.price
				end
			end
		end
	end
end

-- 今の時間帯のマップイベントがレアダンジョン・レイドで出発できるなら、その時間帯（nil なら出ていない）
local function openEventSlot(ctx: Ctx): number?
	if not behavior.mapEvents then
		return nil
	end
	local cur = Game.query.mapEvent(ctx.now, ctx.master).current
	if cur.open and (cur.kind == "rareDungeon" or cur.kind == "raid") then
		return cur.eventSlot
	end
	return nil
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
		-- D-086：合計が hireGood 以上ならその場で採用。無料の引き直しを使い切ったら前回・今回の良い方
		local which = nil
		for _ = 0, master.K.hireFreeRerolls + params.hireTickets do
			local h = state.hireSession
			if h.currentRoll and Rebirth.total(h.currentRoll) >= params.hireGood then
				which = "current"
				break
			end
			if not exec(state, { type = "HireReroll" }, ctx).ok then
				break
			end
			stats.hireRerolls = (stats.hireRerolls or 0) + 1
		end
		local h = state.hireSession
		if which == nil then
			which = "current"
			if h.previousRoll and Rebirth.total(h.previousRoll) > Rebirth.total(h.currentRoll) then
				which = "previous"
			end
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
		if state.unlockedDungeons[d.id] then
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
		if not state.clearedDungeons[d.id] and rate >= params.pushMin then
			push = d.id
		end
		if rate >= params.clearMin then
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

-- パーティごとに最後に選んだ普通のダンジョン（ログアウトのときの自動再派遣の行き先）
local lastDungeon: { [number]: string } = {}

-- 空いているパーティを出す。マップイベント（レアダンジョン・レイド）が出ていて、まだ参加していなければそちらへ（D-152）
local function dispatchIdle(state: any, ctx: Ctx, rng: Rng.Rng, stats: any)
	local slot = openEventSlot(ctx)
	for i = 1, #state.parties do
		if not Party.isBusy(state, i) and not Party.isEmpty(state.parties[i]) then
			local sent = false
			if slot then
				local r = exec(state, { type = "DispatchEvent", partyIndex = i, eventSlot = slot }, ctx)
				if r.ok then
					sent = true
					local kind = r.events[1].kind
					stats.eventDispatches = stats.eventDispatches or {}
					stats.eventDispatches[kind] = (stats.eventDispatches[kind] or 0) + 1
				end
			end
			if not sent then
				local d = chooseDungeon(state, i, ctx, rng)
				if d and exec(state, { type = "Dispatch", partyIndex = i, dungeonId = d }, ctx).ok then
					lastDungeon[i] = d
				end
			end
		end
	end
end

function Policy.manage(state: any, ctx: Ctx, rng: Rng.Rng, stats: any)
	claimInbox(state, ctx)
	pressFriend(state, ctx)
	openAll(state, ctx)
	equipBest(state, ctx)
	sellJunk(state, ctx)
	buyExpansions(state, ctx)
	rebirthCapped(state, ctx, stats)
	hireIfNeeded(state, ctx, stats)
	buyFromMerchant(state, ctx)
	trainBehind(state, ctx, stats)
	arrangeParties(state, ctx)
	equipBest(state, ctx)
	dispatchIdle(state, ctx, rng, stats)
end

-- 帰還がないときの軽い見回り（マップイベントの始まり・フレンドボタンの時刻に呼ぶ）
function Policy.glance(state: any, ctx: Ctx, rng: Rng.Rng, stats: any)
	pressFriend(state, ctx)
	buyFromMerchant(state, ctx)
	dispatchIdle(state, ctx, rng, stats)
end

-- 空いているパーティがあるか（マップイベントの始まりに起きるかの判断）
function Policy.hasIdleParty(state: any): boolean
	for i = 1, #state.parties do
		if not Party.isBusy(state, i) and not Party.isEmpty(state.parties[i]) then
			return true
		end
	end
	return false
end

-- ログイン：留守番の自動再派遣を外し、オンラインでは帰還のたびに方針で出し直す
function Policy.onLogin(state: any, ctx: Ctx)
	for i, p in state.parties do
		if p.autoRepeat then
			exec(state, { type = "SetAutoRepeat", partyIndex = i }, ctx)
		end
	end
end

-- ログアウト：各パーティに自動再派遣を付ける（留守番：D-161）。行き先は最後に選んだ普通のダンジョン
function Policy.onLogout(state: any, ctx: Ctx)
	for i = 1, #state.parties do
		local d = lastDungeon[i]
		if d and not Party.isEmpty(state.parties[i]) then
			exec(state, { type = "SetAutoRepeat", partyIndex = i, dungeonId = d }, ctx)
		end
	end
end

return Policy
