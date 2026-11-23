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

-- 宝箱の保管（D-084, D-166）：倉庫とは別に「宝箱の山×ランクごとの数」だけを持つ。上限なし
-- state.chests[pileKey] = { ランク1の数, …, 最上位ランクの数 }（長さは出た最上位ランクまで。D-085）
-- 宝箱の山の鍵（pileKey）：普通のダンジョンの宝箱は dungeonId、特別な宝箱は "special:<種類>"（D-166, D-171）
-- レアリティが増えたら、足りない分を0で伸ばす
Chest.SPECIAL_PREFIX = "special:"

function Chest.isSpecialPile(pileKey: string): boolean
	return string.sub(pileKey, 1, #Chest.SPECIAL_PREFIX) == Chest.SPECIAL_PREFIX
end

Chest.RARE_PREFIX = "special:rare:"

-- 踏破している一番深いダンジョン（tier が最大。同じ tier はダンジョンの並び順で先のもの）。なければ nil
function Chest.deepestCleared(state: any, master: any): any?
	local best = nil
	for _, d in master.dungeonList do
		if state.clearedDungeons[d.id] and (best == nil or d.tier > best.tier) then
			best = d
		end
	end
	return best
end

-- 基準のダンジョン：踏破している一番深いダンジョン。まだどこも踏破していなければ一番浅いダンジョン（並びの先頭＝古い墓地：D-187）
-- 特別な宝箱・レアダンジョン・レイド・旅の商人・報酬のゴールド（D-190）で使う
function Chest.baseDungeon(state: any, master: any): any
	return Chest.deepestCleared(state, master) or master.dungeonList[1]
end

-- 宝箱の山を開けるときの中身の表と演出ライン（D-089, D-166, D-171, D-185。06章 §19）。開けられない山なら nil
--   普通の山（dungeonId）           → そのダンジョン、演出ラインは chestEffectMinRarity
--   special:rare:<相当するダンジョン> → そのダンジョンの表、演出ラインは rareChestEffectMinRarity（無いダンジョンは開けられない）
--                                      アイテムレベルも相当するダンジョンのもの（D-187）
--   special:<種類>（SpecialChests）  → 中身は開けたときの基準のダンジョン（D-171, D-187）、演出ラインは行の effectMinRarity
function Chest.pileSource(pileKey: string, state: any, master: any): { dungeon: any, effectMinRarity: number }?
	if not Chest.isSpecialPile(pileKey) then
		local d = master.dungeons[pileKey]
		return if d then { dungeon = d, effectMinRarity = d.chestEffectMinRarity } else nil
	end
	if string.sub(pileKey, 1, #Chest.RARE_PREFIX) == Chest.RARE_PREFIX then
		local d = master.dungeons[string.sub(pileKey, #Chest.RARE_PREFIX + 1)]
		if d and d.rareChestEffectMinRarity then
			return { dungeon = d, effectMinRarity = d.rareChestEffectMinRarity }
		end
		return nil
	end
	local row = master.specialChests[pileKey]
	if row == nil or row.rarityTable == nil then
		return nil
	end
	return {
		dungeon = Chest.baseDungeon(state, master),
		effectMinRarity = row.effectMinRarity,
	}
end

-- 特別な宝箱のランクを表から1つ抽選する（D-166。受け取り箱へ入れるときに決める）
function Chest.rollSpecialRank(pileKey: string, rng: Rng.Rng, master: any): number
	local row = master.specialChests[pileKey]
	assert(row and row.rarityTable, `表を持たない特別な宝箱の山: {pileKey}`)
	return rng:pickWeighted(row.rarityTable, weightOf).rank
end

function Chest.add(state: any, pileKey: string, rank: number, n: number)
	local row = state.chests[pileKey]
	if row == nil then
		row = {}
		state.chests[pileKey] = row
	end
	for r = #row + 1, rank do
		row[r] = 0
	end
	row[rank] += n
end

function Chest.count(state: any, pileKey: string, rank: number): number
	local row = state.chests[pileKey]
	return if row then row[rank] or 0 else 0
end

-- ランクごとの合計（画面はこの単位で表示する）
function Chest.countByRank(state: any, master: any): { number }
	local out = table.create(master.rarityCount, 0)
	for _, row in state.chests do
		for r, n in row do
			out[r] += n
		end
	end
	return out
end

function Chest.total(state: any): number
	local n = 0
	for _, row in state.chests do
		for _, v in row do
			n += v
		end
	end
	return n
end

-- その宝箱の山の未開封の数
function Chest.pileTotal(state: any, pileKey: string): number
	local n = 0
	for _, v in state.chests[pileKey] or {} do
		n += v
	end
	return n
end

-- 山から1つ引く（ランクごとの残り数で重み付け。D-089）。数は減らさない
function Chest.draw(state: any, pileKey: string, rng: Rng.Rng): number
	local entries = {}
	for r, v in state.chests[pileKey] do
		if v > 0 then
			table.insert(entries, { rank = r, weight = v })
		end
	end
	return rng:pickWeighted(entries, function(e)
		return e.weight
	end).rank
end

-- 宝箱を1つ開封して状態に反映する（数を減らすのと倉庫の空き確認は呼び出し側）
-- chest = { pileKey, rank }。中身の表は Chest.pileSource（特別な宝箱は開けたときの一番深い踏破ダンジョン：D-171）
-- 売却用アイテム（素材）は常にその場で売る（D-167）。items には残したものだけ、売った素材は soldItems に入れる
function Chest.open(state: any, chest: any, rng: Rng.Rng, master: any): any
	local source = Chest.pileSource(chest.pileKey, state, master)
	assert(source, `中身の表がない宝箱の山: {chest.pileKey}`)
	local dungeon = source.dungeon
	local contents = Chest.rollContents(chest.rank, dungeon, rng, master)
	local created = {}
	for _, e in contents.equipment do
		table.insert(created, Inventory.newEquipment(state, e).uid)
	end
	local kept, soldItems, soldItemsGold = {}, {}, 0
	for itemId, c in contents.items do
		local gold = Inventory.gainItem(state, itemId, c, master)
		if gold > 0 then
			soldItems[itemId] = c
			soldItemsGold += gold
		else
			kept[itemId] = c
		end
	end
	state.gold += contents.gold
	return {
		pileKey = chest.pileKey,
		rank = chest.rank,
		equipmentUids = created,
		items = kept,
		soldItems = soldItems,
		soldItemsGold = soldItemsGold,
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
