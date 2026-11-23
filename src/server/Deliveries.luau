--!strict
-- 届け物（D-180、11章 §3.6）
-- 他のプレイヤー宛ての報酬（紹介で招待した側への報酬など）を、そのプレイヤーのセーブとは別の DataStore の鍵に置く。
-- 他人のセーブ（ロックを持っていない記録）は直接書き換えない。受け取る側が次のログインで読み出し、受け取り箱へ入れたら消す。
--
-- 値：{ items = { Delivery } }。鍵：Config.deliveryKeyPrefix .. UserId（届け先）
-- Delivery：{ id, kind, fromUserId, at, data? }
--   id     ：届け物の識別子。書き込む側が決める（例："referral:<招待された人の UserId>"）。同じ id は箱に1つだけ
--   kind   ：種類（例："referral"）。中身（報酬の内容）はマスターデータから受け取る側の core が決める
--   data   ：種類ごとの補足（任意）。数値の報酬は入れない

local DataStoreService = game:GetService("DataStoreService")

local Config = require("./Config")
local Persistence = require("./Persistence")

export type Delivery = { id: string, kind: string, fromUserId: number, at: number, data: any? }
type Box = { items: { Delivery } }
export type PushStatus = "ok" | "duplicate" | "full" | "error"

local Deliveries = {}
Deliveries.__index = Deliveries

local function keyOf(userId: number): string
	return Config.deliveryKeyPrefix .. tostring(userId)
end

local function itemsOf(box: any): { Delivery }
	if type(box) == "table" and type(box.items) == "table" then
		return box.items
	end
	return {}
end

function Deliveries.new()
	local self = setmetatable({}, Deliveries)
	self.store = DataStoreService:GetDataStore(Config.deliveryStoreName)
	return self
end

-- 書き込み：toUserId の箱に届け物を1つ足す。同じ id がすでにあれば足さない（書き込む側の再試行で二重にしない）。
-- 届け先がオンラインかどうかに関係なく使える（受け取りは次のログイン）。
function Deliveries.push(
	self: any,
	toUserId: number,
	id: string,
	kind: string,
	fromUserId: number,
	data: any?
): PushStatus
	local status: PushStatus = "ok"
	local ok = Persistence.updateWithRetry(self.store, keyOf(toUserId), function(old)
		local items = itemsOf(old)
		for _, d in items do
			if d.id == id then
				status = "duplicate"
				return nil -- 書かない
			end
		end
		if #items >= Config.deliveryMaxItems then
			status = "full"
			return nil
		end
		status = "ok"
		local newItems = table.clone(items)
		table.insert(newItems, { id = id, kind = kind, fromUserId = fromUserId, at = os.time(), data = data })
		local box: Box = { items = newItems }
		return box
	end)
	if not ok then
		return "error"
	end
	if status == "full" then
		warn(`[Deliveries] 届け物の箱がいっぱい（{toUserId}、{id}）`)
	end
	return status
end

-- 読み出し：userId の箱の中身を返す（消さない）。UpdateAsync で読み、書かずに中止する（キャッシュの古い値を読まない）。
-- 戻り値：(成功したか, 届け物の一覧)
function Deliveries.read(self: any, userId: number): (boolean, { Delivery })
	local items: { Delivery } = {}
	local ok = Persistence.updateWithRetry(self.store, keyOf(userId), function(old)
		items = itemsOf(old)
		return nil -- 書かない
	end)
	if not ok then
		return false, {}
	end
	return true, items
end

-- 消す：受け取り箱へ入れて、そのプレイヤーのセーブを保存できたものだけを id で消す。
-- 読み出したあとに届いた別の届け物は残る。
function Deliveries.remove(self: any, userId: number, ids: { string }): boolean
	if #ids == 0 then
		return true
	end
	local drop: { [string]: boolean } = {}
	for _, id in ids do
		drop[id] = true
	end
	return (
		Persistence.updateWithRetry(self.store, keyOf(userId), function(old)
			local kept = {}
			local changed = false
			for _, d in itemsOf(old) do
				if drop[d.id] then
					changed = true
				else
					table.insert(kept, d)
				end
			end
			if not changed then
				return nil
			end
			local box: Box = { items = kept }
			return box
		end)
	)
end

return Deliveries
