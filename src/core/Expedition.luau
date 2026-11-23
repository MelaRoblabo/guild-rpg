--!strict
-- 探索全体の計算・ログ生成・再生位置の計算（docs/system/07_expedition_engine.md）
-- 乱数の消費順（07章 §3）を変えたら ENGINE_VERSION を上げること。

local Combat = require("./Combat")
local Events = require("./Events")
local Formulas = require("./Formulas")
local Rng = require("./Rng")

local Expedition = {}

-- v2：日替わりの特性 chestMult の端数の判定を最後に足した（07章 §3 の 4、D-173）
Expedition.ENGINE_VERSION = 2

export type Input = {
	seed: number,
	departAt: number,
	dungeonId: string,
	members: { Formulas.MemberSnapshot }, -- 隊列順。出発時点の実効値（07章 §1）
	dailyTraitId: string?, -- 出発時刻の日に当たっている日替わりの特性（D-156、06章 §16）
	timeMult: number?, -- 所要秒の倍率。留守番は offlineTimeMult、それ以外は 1（D-161）
}

export type FloorLog = {
	floor: number,
	kind: "battle" | "event",
	startOffset: number, -- 出発からの経過秒（行きの移動を含む）
	duration: number,
	monsterId: string?,
	monsterStats: any?,
	turns: { Combat.TurnLog }?,
	outcome: string?, -- battle: win / wipe / timeout
	event: string?, -- event: chest / item / trap / fountain / none
	detail: any?,
	hpAfter: { number }, -- メンバー順（input.members の順）のフロア終了時のHP
	giftTriggers: { { uid: string, giftId: string } },
}

export type Log = {
	engineVersion: number,
	seed: number,
	dungeonId: string,
	departAt: number,
	result: "clear" | "retreat",
	retreatReason: string?, -- wipe / timeout / trap
	reachedFloor: number,
	travelSeconds: number,
	replaySeconds: number,
	totalSeconds: number,
	floors: { FloorLog },
	clearChestRanks: { number }?,
	travelGiftId: string?,
	dailyTraitId: string?,
	traitChests: number?, -- 日替わりの特性 chestMult で増えた宝箱の数（rewards.chests に含む）
	timeMult: number?,
	rewards: Events.Rewards,
}

local function weightOf(e: any): number
	return e.weight
end

-- メンバーの並び（input.members の順）で HP を返す。JSON にできるよう穴のない配列にする
local function hpSnapshot(members: { Combat.MemberState }): { number }
	local out = {}
	for i, m in members do
		out[i] = m.hp
	end
	return out
end

function Expedition.simulate(input: Input, master: any): Log
	local K = master.K
	local dungeon = master.dungeons[input.dungeonId]
	assert(dungeon, `未知のダンジョン: {input.dungeonId}`)
	assert(#input.members > 0, "メンバーがいない")

	local rng = Rng.new(input.seed)
	-- 日替わりの特性（D-156, D-173）：攻撃力は出発時の実効値に掛けて固定する（個体補正の上限の外）
	local trait = if input.dailyTraitId then master.dailyTraits[input.dailyTraitId] else nil
	local members: { Combat.MemberState } = {}
	for _, snap in input.members do
		local s = snap
		local atk = Formulas.traitAttack(snap, trait)
		if atk ~= snap.atk then
			s = table.clone(snap)
			s.atk = atk
		end
		table.insert(members, { slot = s.slot, snap = s, hp = s.maxHp }) -- 満タンで出発（D-011）
	end

	local travelMult = if trait and trait.effect == "travelMult" then trait.value else 1
	local travel, travelGiftId = Formulas.travelSeconds(input.members, dungeon, K, travelMult)
	local rewards: Events.Rewards = { exp = {}, gold = 0, chests = {}, items = {}, floorsCleared = 0, guildExp = 0 }
	local floors: { FloorLog } = {}
	local offset = travel
	local battleIndex = 0
	local result: "clear" | "retreat" = "clear"
	local retreatReason: string? = nil
	local reached = 0

	for floor = 1, dungeon.floors do
		reached = floor
		local triggers = {}
		local entry: FloorLog

		if floor % 2 == 1 then
			-- 戦闘フロア（D-001）
			battleIndex += 1
			local list = if floor == dungeon.floors then dungeon.bosses else dungeon.monsters
			local monsterId = rng:pickWeighted(list, weightOf).id
			local def = master.monsters[monsterId]
			local stats = Formulas.monsterStats(dungeon, battleIndex, K)
			local monster: Combat.MonsterState = {
				id = monsterId,
				raceTag = def.raceTag,
				attackType = def.attackType,
				hp = stats.hp,
				atk = stats.atk,
				pdef = stats.pdef,
				mdef = stats.mdef,
			}
			local combat = Combat.run(members, monster, rng, K)
			for _, t in combat.giftTriggers do
				table.insert(triggers, t)
			end
			entry = {
				floor = floor,
				kind = "battle",
				startOffset = offset,
				duration = #combat.turns * K.replaySecondsPerTurn,
				monsterId = monsterId,
				monsterStats = stats,
				turns = combat.turns,
				outcome = combat.outcome,
				hpAfter = hpSnapshot(members),
				giftTriggers = triggers,
			}
			if combat.outcome == "win" then
				-- D-012, D-041：経験値は勝利時点の生存者で等分
				rewards.gold += stats.gold
				local survivors = Combat._alive(members)
				local share = math.floor(stats.exp / #survivors)
				for _, m in survivors do
					rewards.exp[m.snap.uid] = (rewards.exp[m.snap.uid] or 0) + share
				end
			else
				result, retreatReason = "retreat", combat.outcome
			end
		else
			-- イベントフロア（D-001, D-014）
			local ctx: Events.EventContext = {
				members = members,
				dungeon = dungeon,
				rng = rng,
				K = K,
				rewards = rewards,
				giftTriggers = triggers,
			}
			local kind, detail, wiped = Events.run(ctx)
			entry = {
				floor = floor,
				kind = "event",
				startOffset = offset,
				duration = K.replaySecondsPerEvent,
				event = kind,
				detail = detail,
				hpAfter = hpSnapshot(members),
				giftTriggers = triggers,
			}
			if wiped then
				result, retreatReason = "retreat", "trap"
			end
		end

		table.insert(floors, entry)
		offset += entry.duration
		if result == "retreat" then
			break
		end
	end

	local clearChestRanks = nil
	if result == "clear" then
		rewards.floorsCleared = dungeon.floors
		-- 踏破報酬の確定宝箱（D-019）
		clearChestRanks = Events.secureChest({
			members = members,
			dungeon = dungeon,
			rng = rng,
			K = K,
			rewards = rewards,
			giftTriggers = floors[#floors].giftTriggers,
		})
	else
		rewards.floorsCleared = reached - 1
	end
	-- 日替わりの特性 chestMult（D-173、07章 §3 の 4）：宝箱1個ごとに、整数部ぶん増やし、端数は確率で +1
	local traitChests = nil
	if trait and trait.effect == "chestMult" then
		traitChests = 0
		local whole = math.floor(trait.value - 1)
		local frac = (trait.value - 1) - whole
		local base = table.clone(rewards.chests)
		for _, c in base do
			local extra = whole
			if frac > 0 and rng:chance(frac) then
				extra += 1
			end
			for _ = 1, extra do
				table.insert(rewards.chests, { rank = c.rank })
			end
			traitChests += extra
		end
	end
	-- ギルド経験値（Q-017）。初回踏破のボーナスは状態に依存するため M2 で加算する
	rewards.guildExp = rewards.floorsCleared * K.guildExpPerFloor
		+ (if result == "clear" then K.guildExpClearBonus else 0)

	local replay = offset - travel
	-- 留守番（D-161、07章 §4b）：時間だけを倍率で伸ばす（戦闘・イベント・報酬は同じ）
	local timeMult = input.timeMult or 1
	if timeMult ~= 1 then
		travel *= timeMult
		replay *= timeMult
		for _, f in floors do
			f.startOffset *= timeMult
			f.duration *= timeMult
		end
	end
	return {
		engineVersion = Expedition.ENGINE_VERSION,
		seed = input.seed,
		dungeonId = input.dungeonId,
		departAt = input.departAt,
		result = result,
		retreatReason = retreatReason,
		reachedFloor = reached,
		travelSeconds = travel,
		replaySeconds = replay,
		totalSeconds = travel * 2 + replay, -- D-026
		floors = floors,
		clearChestRanks = clearChestRanks,
		travelGiftId = travelGiftId,
		dailyTraitId = input.dailyTraitId,
		traitChests = traitChests,
		timeMult = if timeMult ~= 1 then timeMult else nil,
		rewards = rewards,
	}
end

-- 07章 §5：再生位置
export type Progress = {
	phase: "outbound" | "floor" | "inbound" | "returned",
	floorIndex: number?, -- floors の何番目か
	ratio: number, -- その区間の進捗 0〜1
}

function Expedition.progressAt(log: Log, now: number): Progress
	local t = now - log.departAt
	if t < 0 then
		return { phase = "outbound", ratio = 0 }
	end
	if t < log.travelSeconds then
		return { phase = "outbound", ratio = t / log.travelSeconds }
	end
	local replayEnd = log.travelSeconds + log.replaySeconds
	if t < replayEnd then
		for i, f in log.floors do
			if t < f.startOffset + f.duration then
				return { phase = "floor", floorIndex = i, ratio = (t - f.startOffset) / math.max(f.duration, 1) }
			end
		end
	end
	if t < log.totalSeconds then
		return { phase = "inbound", ratio = (t - replayEnd) / log.travelSeconds }
	end
	return { phase = "returned", ratio = 1 }
end

return Expedition
