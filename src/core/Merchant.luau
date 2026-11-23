--!strict
-- 旅の商人（D-152, D-167, D-179, D-187, D-189、docs/system/06_formulas.md §12）
--   品ぞろえはプレイヤーごと：Rng.new(Rng.derive(state.seed, eventSlot)) から作る（rngCounter は進めない。保存しない）
--   品は装備だけ（チケットなど量を管理している品は売らない）。アイテムレベル・レアリティは踏破済みの範囲まで：
--     品ごとに、候補のダンジョン（踏破済み。まだどこも踏破していなければ古い墓地：D-187）から等確率で1つ選び、
--     そのダンジョンの宝箱のレアリティの表からコモンを除いた表（Merchant.rarityTable。コモンしかない表ならコモン：D-189）で
--     レアリティを引き、宝箱の中身と同じ抽選で装備を作る（Chest.rollEquipment）
--   候補のダンジョンは、その時間帯で最初に買ったときに state.merchant.dungeonIds に写す（3分間のうちに
--   新しく踏破しても、品ぞろえと「買った」の並びがずれないように）
-- 状態を持たない（関数の集合）。

local Chest = require("./Chest")
local Inventory = require("./Inventory")
local Rng = require("./Rng")

local Merchant = {}

-- 今の踏破済みのダンジョン（並び順）。なければ並びの先頭（古い墓地：D-187）だけ
function Merchant.currentDungeonIds(state: any, master: any): { string }
	local ids = {}
	for _, d in master.dungeonList do
		if state.clearedDungeons[d.id] then
			table.insert(ids, d.id)
		end
	end
	if #ids == 0 then
		table.insert(ids, master.dungeonList[1].id)
	end
	return ids
end

-- その時間帯の候補のダンジョン（最初に買ったときに写したものがあればそれ）
function Merchant.dungeonIdsFor(state: any, slot: number, master: any): { string }
	local m = state.merchant
	if m and m.eventSlot == slot and m.dungeonIds then
		return m.dungeonIds
	end
	return Merchant.currentDungeonIds(state, master)
end

-- 価格（06章 §12）：floor(売却価格 × merchantPriceMult × (1 + merchantGradeCoef × grade) × (修飾語つきなら 1 + merchantModifierCoef))
function Merchant.price(item: any, master: any): number
	local K = master.K
	return math.floor(
		Inventory.equipmentSellPrice(item, master)
			* K.merchantPriceMult
			* (1 + K.merchantGradeCoef * item.grade)
			* (if item.modifierId then 1 + K.merchantModifierCoef else 1)
	)
end

local function uniform(_e: any): number
	return 1
end

local function weightOf(e: any): number
	return e.weight
end

-- 品のレアリティの表（D-189）：そのダンジョンの宝箱の表（chestRarityTable）からコモン（rank 1）を除いたもの。
-- コモンしかない表のときは宝箱の表のまま（コモン）。宝箱で出る範囲は超えない
function Merchant.rarityTable(dungeon: any): { any }
	local out = {}
	for _, e in dungeon.chestRarityTable do
		if e.rank > 1 then
			table.insert(out, e)
		end
	end
	return if #out > 0 then out else dungeon.chestRarityTable
end

-- 品ぞろえ：{ { item = 装備の中身（baseId・rarity・grade・itemLevel・modifierId・modifierValue）, price, dungeonId } }
-- 乱数の消費順：品の数 → 品ごとに（ダンジョン → レアリティ → 装備の抽選）
function Merchant.goods(state: any, slot: number, master: any): { any }
	local K = master.K
	local rng = Rng.new(Rng.derive(state.seed, slot))
	local dungeonIds = Merchant.dungeonIdsFor(state, slot, master)
	local n = rng:int(K.merchantItemCount.min, K.merchantItemCount.max)
	local out = {}
	for _ = 1, n do
		local d = master.dungeons[rng:pickWeighted(dungeonIds, uniform)]
		local rank = rng:pickWeighted(Merchant.rarityTable(d), weightOf).rank -- D-189
		local item = Chest.rollEquipment(rank, d, rng, master)
		table.insert(out, { item = item, price = Merchant.price(item, master), dungeonId = d.id })
	end
	return out
end

-- その時間帯の「買った」（今の時間帯のものでなければ、何も買っていない）
function Merchant.boughtFor(state: any, slot: number): { boolean }
	local m = state.merchant
	if m and m.eventSlot == slot then
		return m.bought
	end
	return {}
end

-- 買う（呼び出し側で時間帯・窓を確かめておく）。エラーコードか、作った装備を返す
function Merchant.buy(state: any, slot: number, index: any, master: any): (string?, any)
	local goods = Merchant.goods(state, slot, master)
	if type(index) ~= "number" or index ~= math.floor(index) or goods[index] == nil then
		return "ITEM_NOT_FOUND", nil
	end
	if Merchant.boughtFor(state, slot)[index] then
		return "ALREADY_BOUGHT", nil
	end
	local g = goods[index]
	if state.gold < g.price then
		return "NOT_ENOUGH_GOLD", nil
	end
	if Inventory.warehouseFree(state) < 1 then
		return "WAREHOUSE_FULL", nil
	end
	-- 今の時間帯の状態に切り替える（古い時間帯の分は捨てる：03章）
	if state.merchant == nil or state.merchant.eventSlot ~= slot then
		local bought = table.create(#goods, false)
		state.merchant =
			{ eventSlot = slot, bought = bought, dungeonIds = table.clone(Merchant.dungeonIdsFor(state, slot, master)) }
	end
	state.merchant.bought[index] = true
	state.gold -= g.price
	local e = Inventory.newEquipment(state, g.item)
	e.fromMerchant = true -- 自動売却・一括売却で売らない（D-152, D-175）
	return nil, { equipment = e, price = g.price }
end

return Merchant
