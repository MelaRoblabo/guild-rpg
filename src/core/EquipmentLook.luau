--!strict
-- 装備の見た目（名前と絵。D-254、06章 §4.1）。強さには関わらない。
-- 入手したダンジョンの段（itemLevel）をまとめた素材の段と、レアリティ（エピック以上は銘入り）で見た目を選ぶ。

local EquipmentLook = {}

-- 段（1 から）。指輪・護符は段を大きくまとめる
function EquipmentLook.band(baseId: string, itemLevel: number, master: any): number
	local base = master.equipmentBases[baseId]
	local K = master.K
	local per = if base and base.kind == "accessory" then K.equipLookAccessoryTiersPerBand else K.equipLookTiersPerBand
	return math.max(1, math.ceil(itemLevel / per))
end

-- 品の見た目（EquipmentLooks の行）。表にない段は一番近い下の段を使う。見つからなければ nil
function EquipmentLook.of(item: any, master: any): any?
	local bands = master.equipmentLooks[item.baseId]
	if bands == nil then
		return nil
	end
	local band = EquipmentLook.band(item.baseId, item.itemLevel or 1, master)
	local named = (item.rarity or 1) >= master.K.equipLookNamedMinRarity
	for b = band, 1, -1 do
		local slot = bands[b]
		if slot then
			local look = if named and slot.named then slot.named else slot.normal
			if look then
				return look
			end
		end
	end
	return nil
end

-- 品の英語名（見た目がなければ基本アイテムの名前）
function EquipmentLook.nameEn(item: any, master: any): string
	local look = EquipmentLook.of(item, master)
	if look then
		return look.nameEn
	end
	local base = master.equipmentBases[item.baseId]
	return if base then base.nameEn else item.baseId
end

-- 品の画像（なければ nil）
function EquipmentLook.image(item: any, master: any): string?
	local look = EquipmentLook.of(item, master)
	local images = master.images
	if look == nil or images == nil or images.equipment == nil then
		return nil
	end
	return images.equipment[look.id]
end

return EquipmentLook
