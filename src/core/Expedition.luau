--!strict
-- 探索全体の計算・ログ生成・再生位置の計算（docs/system/07_expedition_engine.md）
-- 乱数の消費順（07章 §3）を変えたら ENGINE_VERSION を上げること。

local Combat = require("./Combat")
local Events = require("./Events")
local Formulas = require("./Formulas")
local Rng = require("./Rng")

local Expedition = {}

Expedition.ENGINE_VERSION = 1

export type Input = {
	seed: number,
	departAt: number,
	dungeonId: string,
	members: { Formulas.MemberSnapshot }, -- 隊列順。出発時点の実効値（07章 §1）
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
	hpAfter: { [number]: number }, -- 隊列番号 → フロア終了時のHP
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
	rewards: Events.Rewards,
}

local function weightOf(e: any): number
	return e.weight
end

local function hpSnapshot(members: { Combat.MemberState }): { [number]: number }
	local out = {}
	for _, m in members do
		out[m.slot] = m.hp
	end
	return out
end

function Expedition.simulate(input: Input, master: any): Log
	local K = master.K
	local dungeon = master.dungeons[input.dungeonId]
	assert(dungeon, `未知のダンジョン: {input.dungeonId}`)
	assert(#input.members > 0, "メンバーがいない")

	local rng = Rng.new(input.seed)
	local members: { Combat.MemberState } = {}
	for _, snap in input.members do
		table.insert(members, { slot = snap.slot, snap = snap, hp = snap.maxHp }) -- 満タンで出発（D-011）
	end

	local travel, travelGiftId = Formulas.travelSeconds(input.members, dungeon, K)
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
	-- ギルド経験値（Q-017）。初回踏破のボーナスは状態に依存するため M2 で加算する
	rewards.guildExp = rewards.floorsCleared * K.guildExpPerFloor
		+ (if result == "clear" then K.guildExpClearBonus else 0)

	local replay = offset - travel
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
