--!strict
-- 旅の商人（D-152, D-167, D-179, D-187, D-189、docs/system/06_formulas.md §12）
--   品ぞろえはプレイヤーごと：Rng.new(Rng.derive(state.seed, eventSlot)) から作る（rngCounter は進めない。保存しない）
--   品は装備だけ（チケットなど量を管理している品は売らない）。アイテムレベル・レアリティは踏破済みの範囲まで：
--     品ごとに、候補のダンジョン（踏破済みのうち深い方から merchantDungeonCount 個＝一番深いダンジョンとその1つ浅いダンジョン：D-202。
--     まだどこも踏破していなければ古い墓地：D-187）から等確率で1つ選び、
--     そのダンジョンの宝箱のレアリティの表からコモンを除き上位を重くした表（Merchant.rarityTable。コモンしかない表ならコモン：D-189, D-204）で
--     レアリティを引き、宝箱の中身と同じ抽選で装備を作る（Chest.rollEquipment）
--   候補のダンジョンは、商人へ派遣したときに探索の記録（dungeonIds）に写す（とどまっている間に
--   新しく踏破しても、品ぞろえと「買った」の並びがずれないように）。「買った」も探索の記録（bought）に持つ（D-274）
-- 商人への派遣（D-274）：買えるのは、その時間帯の商人のところにパーティが着いていて、まだ帰っていない間だけ。
--   派遣は1つの商人に1パーティだけ（DispatchEvent）。片道秒 = ceil(場所の distance × travelSecondsPerDistance)（俊敏は効かない）。
--   着いたパーティは Leave（LeaveMerchant）を押すまでとどまる。ログアウトしたら、ログアウトの時刻（まだ着いていなければ着いた時刻）に帰り始める。
--   保存できる値にするため、とどまれる長さに上限（merchantStayMaxSeconds）を置き、上限で帰り始める。
--   探索の記録（expedition）：merchant = true, eventSlot, placeId, arriveAt, leaveAt（帰り始めた時刻。まだなら nil）, dungeonIds, bought
--   state.merchant = { eventSlot }：最後に派遣した時間帯（同じ商人へ2回目を送らない。帰ってきたあとも）
-- 状態を持たない（関数の集合）。

local Chest = require("./Chest")
local Inventory = require("./Inventory")
local MapEvent = require("./MapEvent")
local Rng = require("./Rng")

local Merchant = {}

-- 場所の行（master.mapEventPlaces）
local function placeOf(placeId: string, master: any): any
	for _, p in master.mapEventPlaces do
		if p.id == placeId then
			return p
		end
	end
	error("unknown map event place: " .. tostring(placeId))
end

-- ギルドの街から商人の場所までの片道秒（D-274）
function Merchant.travelSeconds(placeId: string, master: any): number
	return math.ceil(placeOf(placeId, master).distance * master.K.travelSecondsPerDistance)
end

-- その時間帯の商人へ向かった（向かっている・とどまっている）探索。なければ nil
function Merchant.expeditionFor(state: any, slot: number): any?
	for _, e in state.expeditions do
		if e.merchant and e.eventSlot == slot then
			return e
		end
	end
	return nil
end

-- とどまるのをやめる時刻（Leave を押した時刻。まだなら上限の時刻）
function Merchant.stayEnd(e: any, K: any): number
	return e.leaveAt or (e.arriveAt + K.merchantStayMaxSeconds)
end

-- パーティが商人のところにいるか（着いていて、まだ帰り始めていない）
function Merchant.isHere(e: any, now: number, K: any): boolean
	return e.arriveAt <= now and now < Merchant.stayEnd(e, K)
end

-- 探索の記録を作る（DispatchEvent）。uid は呼び出し側で付ける
function Merchant.planExpedition(
	state: any,
	slot: number,
	partyIndex: number,
	memberUids: { string },
	dungeonId: string,
	now: number,
	master: any
): any
	local K = master.K
	local ev = MapEvent.eventAt(slot, master)
	local travel = Merchant.travelSeconds(ev.placeId, master)
	local stay = K.merchantStayMaxSeconds
	return {
		uid = "",
		partyIndex = partyIndex,
		dungeonId = dungeonId, -- 表示用（レイドと同じく踏破済みの一番深いダンジョン）。行き先は placeId
		seed = 0,
		departAt = now,
		arriveAt = now + travel,
		returnAt = now + travel * 2 + stay,
		memberUids = memberUids,
		log = {
			engineVersion = 0,
			seed = 0,
			dungeonId = dungeonId,
			departAt = now,
			result = "merchant",
			reachedFloor = 0,
			travelSeconds = travel,
			replaySeconds = stay, -- とどまっている長さ（Leave で縮める）
			totalSeconds = travel * 2 + stay,
			floors = {},
			rewards = { exp = {}, gold = 0, chests = {}, items = {}, floorsCleared = 0, guildExp = 0 },
		},
		eventSlot = slot,
		merchant = true,
		placeId = ev.placeId,
		dungeonIds = table.clone(Merchant.currentDungeonIds(state, master)),
		bought = {},
	}
end

-- 帰り始める（Leave・ログアウト）。at が着く前なら着いた時刻、上限より後なら上限の時刻にそろえる
function Merchant.leave(e: any, at: number, K: any)
	local t = math.clamp(at, e.arriveAt, e.arriveAt + K.merchantStayMaxSeconds)
	local log = e.log
	e.leaveAt = t
	log.replaySeconds = t - e.arriveAt
	log.totalSeconds = log.travelSeconds * 2 + log.replaySeconds
	e.returnAt = t + log.travelSeconds
end

-- マップに出ている商人（画面用：D-274）。今の時間帯の商人（まだ誰も向かっていなくて締め切り前）と、
-- パーティが向かっている・とどまっている商人。{ { eventSlot, placeId, phase, closesIn?, arriveIn?, partyIndex? } }
--   phase："open"（向かうパーティを待っている）・"coming"（向かっている）・"here"（着いている）
function Merchant.presence(state: any, now: number, master: any): { any }
	local K = master.K
	local out = {}
	local cur = MapEvent.eventAt(MapEvent.slotOf(now, K), master)
	local listed: { [number]: boolean } = {}
	for _, e in state.expeditions do
		if e.merchant and now < Merchant.stayEnd(e, K) then
			listed[e.eventSlot] = true
			table.insert(out, {
				eventSlot = e.eventSlot,
				placeId = e.placeId,
				phase = if now < e.arriveAt then "coming" else "here",
				arriveIn = math.max(0, e.arriveAt - now),
				partyIndex = e.partyIndex,
			})
		elseif e.merchant then
			listed[e.eventSlot] = true -- 帰り道：商人はもういない
		end
	end
	if
		cur.kind == "merchant"
		and now < cur.closeAt
		and not listed[cur.eventSlot]
		and not Merchant.sent(state, cur.eventSlot)
	then
		table.insert(out, {
			eventSlot = cur.eventSlot,
			placeId = cur.placeId,
			phase = "open",
			closesIn = cur.closeAt - now,
		})
	end
	table.sort(out, function(a, b)
		return a.eventSlot < b.eventSlot
	end)
	return out
end

-- 今の候補のダンジョン（D-202）：踏破済みのうち深い方から merchantDungeonCount 個（tier の大きい順。同じ tier は並びの先）。
-- 返す順は並び順。踏破がその数より少なければ踏破済みの全部、なければ並びの先頭（古い墓地：D-187）だけ
function Merchant.currentDungeonIds(state: any, master: any): { string }
	local cleared = {}
	for i, d in master.dungeonList do
		if state.clearedDungeons[d.id] then
			table.insert(cleared, { d = d, i = i })
		end
	end
	if #cleared == 0 then
		return { master.dungeonList[1].id }
	end
	table.sort(cleared, function(a, b)
		if a.d.tier ~= b.d.tier then
			return a.d.tier > b.d.tier
		end
		return a.i < b.i
	end)
	local picked = {}
	for k = 1, math.min(master.K.merchantDungeonCount, #cleared) do
		table.insert(picked, cleared[k])
	end
	table.sort(picked, function(a, b)
		return a.i < b.i
	end)
	local ids = {}
	for _, e in picked do
		table.insert(ids, e.d.id)
	end
	return ids
end

-- その時間帯の候補のダンジョン（派遣したときに写したものがあればそれ）
function Merchant.dungeonIdsFor(state: any, slot: number, master: any): { string }
	local e = Merchant.expeditionFor(state, slot)
	if e and e.dungeonIds then
		return e.dungeonIds
	end
	return Merchant.currentDungeonIds(state, master)
end

-- その時間帯の商人へもう派遣したか（帰ってきたあとも true）
function Merchant.sent(state: any, slot: number): boolean
	return (state.merchant ~= nil and state.merchant.eventSlot == slot) or Merchant.expeditionFor(state, slot) ~= nil
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

-- 品のレアリティの表（D-189, D-204）：そのダンジョンの宝箱の表（chestRarityTable）からコモン（rank 1）を除き、
-- 重みに merchantRarityBias ^ (rank − 2) を掛けたもの（上位ほど出やすい）。
-- コモンしかない表のときは宝箱の表のまま（コモン）。宝箱の表にない rank は出ない（宝箱で出る範囲は超えない）
function Merchant.rarityTable(dungeon: any, K: any): { any }
	local out = {}
	for _, e in dungeon.chestRarityTable do
		if e.rank > 1 then
			table.insert(out, { rank = e.rank, weight = e.weight * K.merchantRarityBias ^ (e.rank - 2) })
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
		local rank = rng:pickWeighted(Merchant.rarityTable(d, K), weightOf).rank -- D-189, D-204
		local item = Chest.rollEquipment(rank, d, rng, master)
		table.insert(out, { item = item, price = Merchant.price(item, master), dungeonId = d.id })
	end
	return out
end

-- その時間帯の「買った」（パーティが向かっていなければ、何も買っていない）
function Merchant.boughtFor(state: any, slot: number): { boolean }
	local e = Merchant.expeditionFor(state, slot)
	return (e and e.bought) or {}
end

-- 買う（呼び出し側で、パーティが商人のところにいることを確かめておく）。エラーコードか、作った装備を返す
function Merchant.buy(state: any, slot: number, index: any, master: any): (string?, any)
	local e = Merchant.expeditionFor(state, slot)
	if e == nil then
		return "MERCHANT_NO_PARTY", nil
	end
	local goods = Merchant.goods(state, slot, master)
	if type(index) ~= "number" or index ~= math.floor(index) or goods[index] == nil then
		return "ITEM_NOT_FOUND", nil
	end
	if e.bought[index] then
		return "ALREADY_BOUGHT", nil
	end
	local g = goods[index]
	if state.gold < g.price then
		return "NOT_ENOUGH_GOLD", nil
	end
	if Inventory.warehouseFree(state) < 1 then
		return "WAREHOUSE_FULL", nil
	end
	e.bought[index] = true
	state.gold -= g.price
	local item = Inventory.newEquipment(state, g.item)
	item.fromMerchant = true -- 自動売却・一括売却で売らない（D-152, D-175）
	return nil, { equipment = item, price = g.price }
end

return Merchant
