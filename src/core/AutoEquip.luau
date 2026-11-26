--!strict
-- 自動装備（D-120・D-231 ⑨・D-235 ③、06章 §24）。状態を持たない関数の集合。
--   AutoEquip.weights  最後の行き先の攻撃の種類の割合（一度も出ていなければ物理と魔法を半々）
--   AutoEquip.plan     付け替えの提案（隊列1番から順に、倉庫の品と本人の今の装備から一番良いもの）
--   AutoEquip.apply    提案を適用する（呼び出し側で探索中でないことを確かめておく）

local Formulas = require("./Formulas")
local Inventory = require("./Inventory")

local AutoEquip = {}

export type Change = { advUid: string, slot: string, from: string?, to: string }

-- 物理と魔法の重み：ダンジョンの普通のモンスターの出現の重みを攻撃の種類で分ける（D-048 の攻略ヒントと同じ割合）
function AutoEquip.weights(dungeonId: string?, master: any): (number, number)
	local d = if dungeonId then master.dungeons[dungeonId] else nil
	if d == nil then
		return 0.5, 0.5
	end
	local phys, total = 0, 0
	for _, m in d.monsters do
		local mon = master.monsters[m.id]
		total += m.weight
		if mon and mon.attackType == "physical" then
			phys += m.weight
		end
	end
	if total <= 0 then
		return 0.5, 0.5
	end
	return phys / total, (total - phys) / total
end

-- 比べる値：武器＝攻撃力補正、防具＝物理防御×物理の重み＋魔法防御×魔法の重み
function AutoEquip.score(item: any, slot: string, wPhys: number, wMag: number, master: any): number
	local base = master.equipmentBases[item.baseId]
	local mult = Formulas.equipMult(item.rarity, item.grade, item.itemLevel or 1, master.K)
	if slot == "weapon" then
		return math.floor((base.atk or 0) * mult)
	end
	return math.floor((base.pdef or 0) * mult) * wPhys + math.floor((base.mdef or 0) * mult) * wMag
end

-- 付け替えの提案。補助と修飾語は見ない。他の冒険者が付けている品は使わない（倉庫の品と本人の今の装備だけ）
-- onlyUid を渡すと、その人の分だけ提案する（パーティに入れた瞬間の自動装備：D-266）
function AutoEquip.plan(state: any, partyIndex: number, master: any, onlyUid: string?): { Change }
	local party = state.parties[partyIndex]
	if party == nil then
		return {}
	end
	local wPhys, wMag = AutoEquip.weights(party.lastDungeonId, master)
	-- 倉庫の品（提案の中で取ったものは抜き、外したものは戻す）
	local pool: { [string]: boolean } = {}
	for uid, item in state.equipment do
		if item.equippedBy == nil then
			pool[uid] = true
		end
	end
	local changes: { Change } = {}
	for _, advUid in party.slots do
		local adv = state.adventurers[advUid] -- 空き枠（Party.EMPTY）は冒険者がいない
		if adv and (onlyUid == nil or advUid == onlyUid) then
			for _, slot in { "weapon", "armor" } do
				local cur = adv.equipment[slot]
				local best, bestScore =
					nil, if cur then AutoEquip.score(state.equipment[cur], slot, wPhys, wMag, master) else -1
				-- 同じ値なら新しい品より今の装備を残し、品どうしは uid の小さい方（決まった順）
				local keys = {}
				for uid in pool do
					table.insert(keys, uid)
				end
				table.sort(keys)
				for _, uid in keys do
					local item = state.equipment[uid]
					local base = master.equipmentBases[item.baseId]
					if base and base.slot == slot and Inventory.canEquip(adv.jobId, item.baseId, master) then
						local sc = AutoEquip.score(item, slot, wPhys, wMag, master)
						if sc > bestScore then
							best, bestScore = uid, sc
						end
					end
				end
				if best then
					pool[best] = nil
					if cur then
						pool[cur] = true
					end
					table.insert(changes, { advUid = adv.uid, slot = slot, from = cur, to = best })
				end
			end
		end
	end
	return changes
end

-- 提案を適用する（前の装備は倉庫へ。枠の数は変わらないので倉庫の空きは要らない）
function AutoEquip.apply(state: any, changes: { Change }, master: any): number
	local n = 0
	for _, c in changes do
		local adv = state.adventurers[c.advUid]
		local item = state.equipment[c.to]
		if adv and item and item.equippedBy == nil then
			if Inventory.equip(state, adv, item, master) == nil then
				n += 1
			end
		end
	end
	return n
end

return AutoEquip
