--!strict
-- 倉庫・装備の付け外し・売却・保護（ゲーム仕様書06章 §4・§6、Q-020）

local Inventory = {}

local SLOTS = { "weapon", "armor", "sub" }
Inventory.SLOTS = SLOTS

-- 倉庫の使用量＝誰も装備していない装備の数（Q-020）
function Inventory.warehouseUsage(state: any): number
	local n = 0
	for _, e in state.equipment do
		if e.equippedBy == nil then
			n += 1
		end
	end
	return n
end

function Inventory.warehouseFree(state: any): number
	return state.expansions.warehouseSize - Inventory.warehouseUsage(state)
end

function Inventory.addItem(state: any, itemId: string, count: number)
	state.items[itemId] = (state.items[itemId] or 0) + count
end

-- 装備を新しく作って倉庫に入れる
function Inventory.newEquipment(state: any, fields: any): any
	local uid = `eq_{state.nextUid}`
	state.nextUid += 1
	local e = {
		uid = uid,
		baseId = fields.baseId,
		rarity = fields.rarity,
		grade = fields.grade,
		itemLevel = fields.itemLevel,
		modifierId = fields.modifierId,
		modifierValue = fields.modifierValue,
		equippedBy = nil,
		locked = false,
	}
	state.equipment[uid] = e
	return e
end

-- 職業が装備できるか
function Inventory.canEquip(jobId: string, baseId: string, master: any): boolean
	local job = master.jobs[jobId]
	local base = master.equipmentBases[baseId]
	if not job or not base then
		return false
	end
	return table.find(job.equipKinds, base.kind) ~= nil
end

-- 冒険者に装備させる（前の装備は倉庫へ）。エラーコードを返す（成功時 nil）
function Inventory.equip(state: any, adv: any, item: any, master: any): string?
	if item.equippedBy ~= nil and item.equippedBy ~= adv.uid then
		return "ITEM_EQUIPPED"
	end
	if not Inventory.canEquip(adv.jobId, item.baseId, master) then
		return "JOB_CANNOT_EQUIP"
	end
	local slot = master.equipmentBases[item.baseId].slot
	local prev = adv.equipment[slot]
	if prev and state.equipment[prev] then
		state.equipment[prev].equippedBy = nil
	end
	adv.equipment[slot] = item.uid
	item.equippedBy = adv.uid
	return nil
end

function Inventory.unequip(state: any, adv: any, slot: string): string?
	local uid = adv.equipment[slot]
	if uid == nil then
		return "SLOT_EMPTY"
	end
	if Inventory.warehouseFree(state) < 1 then
		return "WAREHOUSE_FULL"
	end
	state.equipment[uid].equippedBy = nil
	adv.equipment[slot] = nil
	return nil
end

-- 06章 §6：売却価格
function Inventory.equipmentSellPrice(item: any, master: any): number
	local K = master.K
	local base = master.equipmentBases[item.baseId]
	return math.floor(
		base.sellPrice
			* K.sellRarityMult[item.rarity]
			* (1 + K.sellGradeCoef * item.grade)
			* K.equipTierMult ^ ((item.itemLevel or 1) - 1)
	)
end

return Inventory
