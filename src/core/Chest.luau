--!strict
-- 宝箱の中身の抽選と開封（ゲーム仕様書06章 §3、D-015、D-058、Q-011、Q-020）
-- 中身は開封時に抽選する（D-015）。乱数の消費順：装備の数 → 各装備（基本・グレード・修飾語の有無・種類・値）
--   → 追加（売却用/ゴールド）→ 売却用の種類 → ポーション判定 → ポーションの種類 → 転職ポーションの職業

local Inventory = require("./Inventory")
local Rng = require("./Rng")

local Chest = {}

local function weightOf(e: any): number
	return e.weight
end

local function uniform(e: any): number
	local _ = e
	return 1
end

-- 1個の装備を抽選する（倉庫には入れない）
function Chest.rollEquipment(rank: number, dungeon: any, rng: Rng.Rng, master: any): any
	local K = master.K
	local candidates = {}
	for _, b in master.raw.EquipmentBases do
		if b.minRarity <= rank then
			table.insert(candidates, b)
		end
	end
	local base = rng:pickWeighted(candidates, uniform)
	local grade = rng:pickWeighted(K.gradeWeights, weightOf).grade
	local modifierId, modifierValue = nil, nil
	if rng:chance(K.modifierChance) and #dungeon.modifierPool > 0 then
		modifierId = rng:pickWeighted(dungeon.modifierPool, uniform)
		local mod = master.modifiers[modifierId]
		if mod.effect.kind == "flatStat" then
			-- 固定値の修飾語はアイテムレベルに応じて大きくする（D-069）
			modifierValue = math.floor(rng:int(mod.range.min, mod.range.max) * K.equipTierMult ^ (dungeon.tier - 1))
		else
			modifierValue = math.floor((mod.range.min + rng:float() * (mod.range.max - mod.range.min)) * 100 + 0.5)
				/ 100
		end
	end
	return {
		baseId = base.id,
		rarity = rank,
		grade = grade,
		itemLevel = dungeon.tier,
		modifierId = modifierId,
		modifierValue = modifierValue,
	}
end

-- 1箱の中身を抽選する
function Chest.rollContents(rank: number, dungeon: any, rng: Rng.Rng, master: any): any
	local K = master.K
	local L = master.raw.LootTables.chest
	local contents = { equipment = {}, items = {}, gold = 0 }
	local count = rng:pickWeighted(L.equipmentCountWeights, weightOf).count
	for _ = 1, count do
		table.insert(contents.equipment, Chest.rollEquipment(rank, dungeon, rng, master))
	end
	local extra = rng:pickWeighted(L.extraWeights, weightOf).id
	if extra == "sellable" then
		local itemId = rng:pickWeighted(dungeon.sellableItems, weightOf).id
		contents.items[itemId] = (contents.items[itemId] or 0) + 1
	else
		contents.gold = math.floor(dungeon.battleReward.gold * L.goldMult * K.sellRarityMult[rank])
	end
	if rank >= L.potionMinRank and rng:chance(K.potionChanceRarePlus) then
		local kind = rng:pickWeighted(K.potionKindWeights, weightOf).id
		local itemId
		if kind == "job_change" then
			local jobId = rng:pickWeighted(dungeon.jobPotionTargets, uniform)
			itemId = "itm_potion_job_" .. string.gsub(jobId, "^job_", "")
		elseif kind == "appearance_change" then
			itemId = "itm_potion_appearance_change"
		else
			itemId = "itm_potion_appearance_keep"
		end
		contents.items[itemId] = (contents.items[itemId] or 0) + 1
	end
	return contents
end

-- 宝箱を開封して状態に反映する（倉庫の空きは呼び出し側で確認する）
function Chest.open(state: any, chest: any, rng: Rng.Rng, master: any): any
	local dungeon = master.dungeons[chest.dungeonId]
	local contents = Chest.rollContents(chest.rank, dungeon, rng, master)
	local created = {}
	for _, e in contents.equipment do
		table.insert(created, Inventory.newEquipment(state, e).uid)
	end
	for itemId, c in contents.items do
		Inventory.addItem(state, itemId, c)
	end
	state.gold += contents.gold
	return {
		chestUid = chest.uid,
		rank = chest.rank,
		equipmentUids = created,
		items = contents.items,
		gold = contents.gold,
	}
end

-- 1箱で増えうる装備の最大数（倉庫の空き確認用）
function Chest.maxEquipmentPerChest(master: any): number
	local m = 0
	for _, e in master.raw.LootTables.chest.equipmentCountWeights do
		m = math.max(m, e.count)
	end
	return m
end

return Chest
