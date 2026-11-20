--!strict
-- イベントフロア1回分と宝箱の確保（docs/system/07_expedition_engine.md、D-014〜D-019）
-- 乱数の消費順（07章 §3）：イベント種別 → 種別ごとの抽選 → 幸運判定

local Combat = require("./Combat")
local Formulas = require("./Formulas")
local Rng = require("./Rng")

local Events = {}

export type Rewards = {
	exp: { [string]: number },
	gold: number,
	chests: { { rank: number } },
	items: { [string]: number },
	floorsCleared: number,
	guildExp: number,
}

export type EventContext = {
	members: { Combat.MemberState },
	dungeon: any,
	rng: Rng.Rng,
	K: any,
	rewards: Rewards,
	giftTriggers: { { uid: string, giftId: string } },
}

local function weightOf(e: any): number
	return e.weight
end

-- 宝箱ランクを抽選する（D-015）
function Events.rollChestRank(ctx: EventContext): number
	local e = ctx.rng:pickWeighted(ctx.K.chestRankOffsets, weightOf)
	return Formulas.chestRank(ctx.dungeon.minChestRank, e.offset)
end

-- 宝箱を1個確保し、幸運の判定を行う（D-019）。確保したランクの一覧を返す
function Events.secureChest(ctx: EventContext): { number }
	local ranks = { Events.rollChestRank(ctx) }
	local holders = {}
	for _, m in ctx.members do
		if m.hp > 0 and m.snap.lucky then
			table.insert(holders, m)
		end
	end
	if #holders > 0 and ctx.rng:chance(Formulas.luckyChance(#holders, ctx.K)) then
		table.insert(ranks, Events.rollChestRank(ctx))
		for _, m in holders do
			table.insert(ctx.giftTriggers, { uid = m.snap.uid, giftId = "gift_lucky" })
		end
	end
	for _, r in ranks do
		table.insert(ctx.rewards.chests, { rank = r })
	end
	return ranks
end

-- イベントを1回処理する。戻り値：イベント種別、詳細、全滅したか
function Events.run(ctx: EventContext): (string, any, boolean)
	local K = ctx.K
	local kind = ctx.rng:pickWeighted(K.eventWeights, weightOf).id -- D-014

	if kind == "chest" then
		return kind, { ranks = Events.secureChest(ctx) }, false
	elseif kind == "item" then
		-- D-016, D-058, Q-011
		local sub = ctx.rng:pickWeighted(K.itemEventWeights, weightOf).id
		local itemId
		if sub == "ticket" then
			itemId = "itm_slot_ticket"
		else
			itemId = ctx.rng:pickWeighted(ctx.dungeon.sellableItems, weightOf).id
		end
		ctx.rewards.items[itemId] = (ctx.rewards.items[itemId] or 0) + 1
		return kind, { itemId = itemId }, false
	elseif kind == "trap" then
		-- D-017：技巧合計（罠師の勘は本人分を倍で数える）
		local dexSum = 0
		for _, m in ctx.members do
			if m.hp > 0 then
				dexSum += m.snap.dex * m.snap.trapDexMult
				if m.snap.trapDexMult > 1 then
					table.insert(ctx.giftTriggers, { uid = m.snap.uid, giftId = "gift_trapsense" })
				end
			end
		end
		local evadeRate = Formulas.trapEvadeRate(dexSum, ctx.dungeon.trapLevel, K)
		local evaded = ctx.rng:chance(evadeRate)
		local damage = {}
		if not evaded then
			for _, m in ctx.members do
				if m.hp > 0 then
					local d = Formulas.trapDamage(m.snap.maxHp, ctx.dungeon, K)
					m.hp = math.max(0, m.hp - d)
					table.insert(damage, { slot = m.slot, amount = d })
				end
			end
		end
		local wiped = #Combat._alive(ctx.members) == 0
		return kind, { evaded = evaded, evadeRate = evadeRate, damage = damage }, wiped
	elseif kind == "fountain" then
		-- D-018：生存者のみ回復、復活なし
		local healed = {}
		for _, m in ctx.members do
			if m.hp > 0 then
				local h = math.min(Formulas.fountainHeal(m.snap.maxHp, K), m.snap.maxHp - m.hp)
				m.hp += h
				table.insert(healed, { slot = m.slot, amount = h })
			end
		end
		return kind, { healed = healed }, false
	end

	return "none", {}, false
end

return Events
