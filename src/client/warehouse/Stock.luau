--!strict
-- 倉庫の一覧（S-50、D-119・D-120・D-167・D-231 ⑮）。純粋な関数（Lune でテストする）。
--   - 一覧は倉庫の品だけ（装備中の品は出さない）。枠（武器・防具・補助）ごと。
--   - 並べ替え：rarity（レアリティ→グレード→性能）・power（一括売却の比べる値。補助は売却額）・sell（売却額）・new（新しい順）。
--     desc＝高い順（新しい順）。同じなら新しい品を先に。
--   - 一括売却（Bulk Sell）：今の枠の、入にしたレアリティの品。エンチャント装備（修飾語つき）は「エンチャントも売る」が入のときだけ、
--     プラス（+1 以上）は「プラスも売る」が入のときだけ。保護中・装備中は売らない（D-120・D-231 ⑮・D-303）。
--   - core の関数は呼び出し側から deps で受け取る（Roblox と Lune で require の道が違うため）。

export type Deps = {
	value: (item: any, master: any) -> number?, -- Formulas.bulkSellValue
	price: (item: any, master: any) -> number, -- Inventory.equipmentSellPrice
}

local Stock = {}

Stock.SLOTS = { "weapon", "armor", "sub" }

local function serial(uid: string): number
	return tonumber(string.match(uid, "(%d+)$")) or 0
end

local function slotOf(item: any, master: any): string?
	local base = master.equipmentBases[item.baseId]
	return if base then base.slot else nil
end

-- 並べる値（大きいほど「高い」）
local function keys(item: any, sort: string, master: any, deps: Deps): { number }
	if sort == "power" then
		return { deps.value(item, master) or deps.price(item, master), item.rarity, item.grade }
	elseif sort == "sell" then
		return { deps.price(item, master), item.rarity }
	elseif sort == "new" then
		return {}
	end
	return { item.rarity, item.grade, deps.value(item, master) or deps.price(item, master) }
end

-- 倉庫の品（その枠、装備中を除く）を並べた uid の列
function Stock.list(state: any, slot: string, prefs: any, master: any, deps: Deps): { string }
	local rows = {}
	for uid, item in state.equipment do
		if item.equippedBy == nil and slotOf(item, master) == slot then
			table.insert(rows, { uid = uid, n = serial(uid), k = keys(item, prefs.whSort, master, deps) })
		end
	end
	local desc = prefs.whDesc ~= false
	table.sort(rows, function(a, b)
		for i = 1, math.max(#a.k, #b.k) do
			local x, y = a.k[i] or 0, b.k[i] or 0
			if x ~= y then
				if desc then
					return x > y
				end
				return x < y
			end
		end
		if a.n ~= b.n then
			-- 新しい順の並べ替えでは向きに従う。それ以外は同じ値なら新しい品を先に
			if prefs.whSort == "new" and not desc then
				return a.n < b.n
			end
			return a.n > b.n
		end
		return a.uid < b.uid
	end)
	local out = {}
	for _, r in rows do
		table.insert(out, r.uid)
	end
	return out
end

export type BulkFilter = {
	rarityOn: (rank: number) -> boolean, -- そのレアリティを売るか
	enchanted: boolean, -- エンチャント装備も売るか
	plus: boolean, -- プラス（+1 以上）も売るか
}

-- 一括売却の対象（今の枠、入切に合う品。保護中・装備中を除く）と合計額（D-303）
function Stock.bulkPlan(state: any, slot: string, filter: BulkFilter, master: any, deps: Deps): ({ string }, number)
	local out, total = {}, 0
	for uid, item in state.equipment do
		if
			item.equippedBy == nil
			and not item.locked
			and (filter.enchanted or item.modifierId == nil)
			and (filter.plus or (item.grade or 0) == 0)
			and filter.rarityOn(item.rarity)
			and slotOf(item, master) == slot
		then
			table.insert(out, uid)
			total += deps.price(item, master)
		end
	end
	table.sort(out, function(a, b)
		return serial(a) < serial(b)
	end)
	return out, total
end

-- 選んだ品の売却の合計額
function Stock.total(state: any, uids: { string }, master: any, deps: Deps): number
	local sum = 0
	for _, uid in uids do
		local item = state.equipment[uid]
		if item then
			sum += deps.price(item, master)
		end
	end
	return sum
end

-- アイテムのタブ：持っているチケット・ポーション（売却用アイテムは手に入れたときに売るので出さない：D-167）。データの順
function Stock.items(state: any, master: any): { { itemId: string, count: number } }
	local out = {}
	for _, row in master.raw.Items do
		local n = (state.items or {})[row.id] or 0
		if n > 0 and row.kind ~= "sellable" then
			table.insert(out, { itemId = row.id, count = n })
		end
	end
	return out
end

return Stock
