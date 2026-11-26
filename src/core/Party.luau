--!strict
-- パーティ編成（ゲーム仕様書04章 §1、D-035）

local Formulas = require("./Formulas")

local Party = {}

Party.SIZE = 4
Party.EMPTY = "" -- 空き枠。セーブデータ（JSON/DataStore）で穴あき配列にしないため（03章）

function Party.newSlots(): { string }
	return { Party.EMPTY, Party.EMPTY, Party.EMPTY, Party.EMPTY }
end

function Party.isEmpty(p: any): boolean
	for slot = 1, Party.SIZE do
		if p.slots[slot] ~= Party.EMPTY then
			return false
		end
	end
	return true
end

-- 探索中か
-- パーティのリーダー（D-271）。leaderUid がパーティにいればその人、いなければいちばん前にいる人。誰もいなければ nil
function Party.leader(state: any, partyIndex: number): string?
	local p = state.parties[partyIndex]
	if p == nil then
		return nil
	end
	if p.leaderUid and table.find(p.slots, p.leaderUid) and state.adventurers[p.leaderUid] then
		return p.leaderUid
	end
	for _, uid in p.slots do
		if uid ~= Party.EMPTY and state.adventurers[uid] then
			return uid
		end
	end
	return nil
end

-- リーダーがパーティから外れていたら、記録を消す（次はいちばん前の人。外れた人が戻っても勝手にリーダーに戻らない：D-271 ①）
function Party.fixLeader(state: any, partyIndex: number)
	local p = state.parties[partyIndex]
	if p and p.leaderUid and table.find(p.slots, p.leaderUid) == nil then
		p.leaderUid = nil
	end
end

function Party.isBusy(state: any, partyIndex: number): boolean
	for _, e in state.expeditions do
		if e.partyIndex == partyIndex then
			return true
		end
	end
	return false
end

-- 冒険者が所属しているパーティ番号と隊列（なければ nil）
function Party.find(state: any, uid: string): (number?, number?)
	for i, p in state.parties do
		for slot = 1, Party.SIZE do
			if p.slots[slot] == uid then
				return i, slot
			end
		end
	end
	return nil, nil
end

-- 冒険者が探索中か（所属パーティが探索中）
function Party.isAdventurerBusy(state: any, uid: string): boolean
	local idx = Party.find(state, uid)
	return idx ~= nil and Party.isBusy(state, idx)
end

-- 冒険者 → 計算式に渡すメンバー定義
function Party.memberDef(state: any, adv: any, slot: number): Formulas.MemberDef
	local equipment = {}
	for slotName, uid in adv.equipment do
		local e = state.equipment[uid]
		if e then
			equipment[slotName] = {
				baseId = e.baseId,
				rarity = e.rarity,
				grade = e.grade,
				itemLevel = e.itemLevel,
				modifierId = e.modifierId,
				modifierValue = e.modifierValue,
			}
		end
	end
	return {
		uid = adv.uid,
		slot = slot,
		jobId = adv.jobId,
		baseStats = adv.baseStats,
		giftIds = adv.giftIds,
		equipment = equipment :: any,
	}
end

-- パーティの実効値（隊列順。空き枠は飛ばす）
function Party.snapshots(state: any, partyIndex: number, master: any): { Formulas.MemberSnapshot }
	local p = state.parties[partyIndex]
	local out = {}
	for slot = 1, Party.SIZE do
		local uid = p.slots[slot]
		if uid ~= Party.EMPTY then
			table.insert(out, Formulas.memberSnapshot(Party.memberDef(state, state.adventurers[uid], slot), master))
		end
	end
	return out
end

return Party
