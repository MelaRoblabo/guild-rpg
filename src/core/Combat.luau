--!strict
-- 戦闘1回分（docs/system/07_expedition_engine.md §2「戦闘1回」）
-- 乱数の消費順（07章 §3）：各行動のクリティカル判定 → モンスターの被弾対象抽選

local Formulas = require("./Formulas")
local Rng = require("./Rng")

local Combat = {}

export type MemberState = { slot: number, snap: Formulas.MemberSnapshot, hp: number }

export type MonsterState = {
	id: string,
	raceTag: string,
	attackType: string,
	hp: number,
	atk: number,
	pdef: number,
	mdef: number,
}

export type Action = {
	kind: "attack" | "heal",
	slot: number,
	amount: number,
	crit: boolean?,
	target: number?, -- heal の対象の隊列番号
}

export type TurnLog = {
	actions: { Action },
	monster: { target: number, amount: number }?,
	monsterHp: number,
}

export type CombatResult = {
	outcome: "win" | "wipe" | "timeout",
	turns: { TurnLog },
	giftTriggers: { { uid: string, giftId: string } },
}

local function alive(members: { MemberState }): { MemberState }
	local out = {}
	for _, m in members do
		if m.hp > 0 then
			table.insert(out, m)
		end
	end
	return out
end

-- D-004：俊敏の降順、同値は隊列番号の小さい順
function Combat.actionOrder(members: { MemberState }): { MemberState }
	local list = alive(members)
	table.sort(list, function(a, b)
		if a.snap.agi ~= b.snap.agi then
			return a.snap.agi > b.snap.agi
		end
		return a.slot < b.slot
	end)
	return list
end

-- D-034：回復が必要な味方（HP割合が最小、同値は隊列順）。不要なら nil
function Combat.healTarget(members: { MemberState }, K: any): MemberState?
	local target: MemberState? = nil
	local best = math.huge
	for _, m in members do
		if m.hp > 0 then
			local ratio = m.hp / m.snap.maxHp
			if ratio < K.healThreshold and (ratio < best or (ratio == best and target and m.slot < target.slot)) then
				best, target = ratio, m
			end
		end
	end
	return target
end

-- D-005：生存者の被弾率を按分して抽選
function Combat.pickTarget(members: { MemberState }, rng: Rng.Rng, K: any): MemberState
	local list = alive(members)
	table.sort(list, function(a, b)
		return a.slot < b.slot
	end)
	return rng:pickWeighted(list, function(m)
		return K.hitWeights[m.slot]
	end)
end

function Combat.run(members: { MemberState }, monster: MonsterState, rng: Rng.Rng, K: any): CombatResult
	local turns: { TurnLog } = {}
	local triggers = {}

	-- 種族タグに効くギフト（退魔の才など）の発動記録
	for _, m in members do
		if m.hp > 0 then
			for _, g in m.snap.tagGiftIds[monster.raceTag] or {} do
				table.insert(triggers, { uid = m.snap.uid, giftId = g })
			end
		end
	end

	for _ = 1, K.maxTurns do
		local turn: TurnLog = { actions = {}, monsterHp = monster.hp }
		table.insert(turns, turn)

		for _, m in Combat.actionOrder(members) do
			local healTarget = if m.snap.heals then Combat.healTarget(members, K) else nil
			if healTarget then
				local amount = math.min(Formulas.healAmount(m.snap, K), healTarget.snap.maxHp - healTarget.hp)
				healTarget.hp += amount
				table.insert(turn.actions, { kind = "heal", slot = m.slot, amount = amount, target = healTarget.slot })
			else
				local atk = Formulas.attackAgainst(m.snap, monster.raceTag)
				local def = if m.snap.attackType == "physical" then monster.pdef else monster.mdef
				local dmg = Formulas.damage(atk, def, K)
				local crit = rng:chance(Formulas.critRate(m.snap.dex, K))
				if crit then
					dmg = Formulas.critDamage(dmg, K)
				end
				monster.hp = math.max(0, monster.hp - dmg)
				table.insert(turn.actions, { kind = "attack", slot = m.slot, amount = dmg, crit = crit })
				if monster.hp <= 0 then
					turn.monsterHp = 0
					return { outcome = "win", turns = turns, giftTriggers = triggers }
				end
			end
		end
		turn.monsterHp = monster.hp

		-- モンスターの攻撃（D-005, D-008）
		local target = Combat.pickTarget(members, rng, K)
		local def = if monster.attackType == "physical" then target.snap.pdef else target.snap.mdef
		local dmg = Formulas.damage(monster.atk, def, K)
		target.hp = math.max(0, target.hp - dmg)
		turn.monster = { target = target.slot, amount = dmg }

		if #alive(members) == 0 then
			return { outcome = "wipe", turns = turns, giftTriggers = triggers }
		end
	end

	return { outcome = "timeout", turns = turns, giftTriggers = triggers } -- D-009
end

Combat._alive = alive

return Combat
