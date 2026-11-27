--!strict
-- 受け取り箱（D-164, D-176、docs/system/03_state_model.md InboxEntry、05章 ClaimInbox）
-- クエスト・プレイ時間・ログインボーナス（のちにレイド・紹介）の報酬の受け取り口。
--   Inbox.push   報酬（マスターデータの rewards の形）を受け取り箱に1件入れる。宝箱のランクはここで決める（D-166）
--   Inbox.grant  受け取り箱を通さずにその場で渡す（クエスト：D-286）
--   Inbox.claim  受け取れるものを全部受け取る。受け取れないもの（所属枠がいっぱいのユニークなど）は残す。期限はない（D-176）
-- 状態を持たない（関数の集合）。乱数は呼び出し側から受け取る。

local Chest = require("./Chest")
local Formulas = require("./Formulas")
local Hiring = require("./Hiring")
local Inventory = require("./Inventory")
local Rng = require("./Rng")

local Inbox = {}

export type Source = "quest" | "playtime" | "login" | "raid" | "referral"

local function rosterCount(state: any): number
	local n = 0
	for _ in state.adventurers do
		n += 1
	end
	return n
end

-- そのユニークを持っているか、受け取り箱に届いているか（同じユニークを二重に配らない：D-155）
function Inbox.hasUnique(state: any, uniqueId: string): boolean
	for _, a in state.adventurers do
		if a.uniqueId == uniqueId then
			return true
		end
	end
	for _, entry in state.inbox or {} do
		if entry.rewards.uniqueId == uniqueId then
			return true
		end
	end
	return false
end

-- 報酬の形（rewards）を受け取り箱の中身にする。rank の無い宝箱は SpecialChests の表でランクを引き、
-- 宝箱の山×ランクごとにまとめる（並びは spec の順・ランクの低い順）
-- ゴールドは goldMult × 入れたときの基準のダンジョンの rewardGoldBase（D-190、06章 §22）。額はここで決めて保存する
local function resolve(state: any, spec: any, takeRng: () -> Rng.Rng, master: any): any
	local out: any = {}
	if spec.goldMult and spec.goldMult > 0 then
		local gold = Formulas.rewardGold(Chest.baseDungeon(state, master), spec.goldMult, master.K)
		if gold > 0 then
			out.gold = gold
		end
	end
	if spec.items then
		local items = {}
		local any = false
		for itemId, n in spec.items do
			items[itemId] = n
			any = true
		end
		if any then
			out.items = items
		end
	end
	if spec.chests and #spec.chests > 0 then
		local chests = {}
		local rng: Rng.Rng? = nil
		for _, c in spec.chests do
			if c.rank then
				table.insert(chests, { pileKey = c.pileKey, rank = c.rank, count = c.count })
			else
				if rng == nil then
					rng = takeRng()
				end
				local byRank: { [number]: number } = {}
				for _ = 1, c.count do
					local rank = Chest.rollSpecialRank(c.pileKey, rng :: Rng.Rng, master)
					byRank[rank] = (byRank[rank] or 0) + 1
				end
				for rank = 1, master.rarityCount do
					if byRank[rank] then
						table.insert(chests, { pileKey = c.pileKey, rank = rank, count = byRank[rank] })
					end
				end
			end
		end
		out.chests = chests
	end
	return out
end

-- 受け取り箱に1件入れる。spec はマスターデータの rewards の形、uniqueId はログインボーナス7日目のユニーク（D-155）
-- takeRng は宝箱のランクを引くときだけ呼ぶ（1件につき最大1本）
function Inbox.push(
	state: any,
	source: Source,
	at: number,
	spec: any?,
	takeRng: () -> Rng.Rng,
	master: any,
	uniqueId: string?
): any
	local rewards = resolve(state, spec or {}, takeRng, master)
	rewards.uniqueId = uniqueId
	local entry = { uid = `inb_{state.nextUid}`, source = source, at = at, rewards = rewards }
	state.nextUid += 1
	table.insert(state.inbox, entry)
	return entry
end

-- 受け取り箱を通さずに、その場で渡す（クエストの受け取り：D-286）。spec はマスターデータの rewards の形。
-- ゴールド・アイテム・宝箱（宝箱の山へ）を入れ、渡した中身（resolve の形：gold・items・chests）を返す
function Inbox.grant(state: any, spec: any?, takeRng: () -> Rng.Rng, master: any): any
	local r = resolve(state, spec or {}, takeRng, master)
	if r.gold then
		state.gold += r.gold
	end
	for itemId, n in r.items or {} do
		Inventory.gainItem(state, itemId, n, master)
	end
	for _, c in r.chests or {} do
		Chest.add(state, c.pileKey, c.rank, c.count)
	end
	return r
end

-- まとめて受け取る（D-164, D-176）。受け取れたものの合計と、残った件数を返す
--   ゴールド・アイテム・宝箱はいつでも受け取れる（宝箱は宝箱の山へ。上限なし：D-084）
--   ユニークは所属枠に空きがあるときだけ加入する。空きがなければその件に残す
--   すでに持っているユニークは加入させない（二重に配らないので通常は起きない）
function Inbox.claim(state: any, now: number, master: any): any
	local gold = 0
	local items: { [string]: number } = {}
	local chestByPile: { [string]: number } = {}
	local pileOrder: { string } = {}
	local joined = {}
	local blocked: string? = nil
	local remaining = {}
	local roster = rosterCount(state)

	for _, entry in state.inbox do
		local r = entry.rewards
		if r.gold then
			state.gold += r.gold
			gold += r.gold
		end
		for itemId, n in r.items or {} do
			Inventory.gainItem(state, itemId, n, master)
			items[itemId] = (items[itemId] or 0) + n
		end
		for _, c in r.chests or {} do
			Chest.add(state, c.pileKey, c.rank, c.count)
			if chestByPile[c.pileKey] == nil then
				chestByPile[c.pileKey] = 0
				table.insert(pileOrder, c.pileKey)
			end
			chestByPile[c.pileKey] += c.count
		end
		local keepUnique: string? = nil
		if r.uniqueId then
			local u = master.uniques[r.uniqueId]
			local owned = false
			for _, a in state.adventurers do
				owned = owned or a.uniqueId == r.uniqueId
			end
			if u and not owned then
				if roster < state.expansions.rosterSize then
					local uid = `adv_{state.nextUid}`
					state.nextUid += 1
					local cand = {
						uniqueId = u.id,
						name = u.name,
						gender = u.gender,
						appearanceId = u.appearanceId,
						jobId = u.jobId,
						giftIds = u.giftIds,
					}
					state.adventurers[uid] = Hiring.newAdventurer(uid, cand, u.baseStats, now, master)
					roster += 1
					table.insert(joined, { uid = uid, uniqueId = u.id })
				else
					keepUnique = r.uniqueId
					blocked = "ROSTER_FULL"
				end
			end
		end
		if keepUnique then
			table.insert(
				remaining,
				{ uid = entry.uid, source = entry.source, at = entry.at, rewards = { uniqueId = keepUnique } }
			)
		end
	end
	state.inbox = remaining

	local chests = {}
	for _, key in pileOrder do
		table.insert(chests, { pileKey = key, count = chestByPile[key] })
	end
	return { gold = gold, items = items, chests = chests, joined = joined, remaining = #remaining, blocked = blocked }
end

-- 画面用の要約（宝箱のランクは返さない：D-087）。宝箱は山ごとの数
function Inbox.summary(state: any): { any }
	local out = {}
	for _, entry in state.inbox or {} do
		local r = entry.rewards
		local chests = {}
		local index: { [string]: number } = {}
		for _, c in r.chests or {} do
			if index[c.pileKey] == nil then
				table.insert(chests, { pileKey = c.pileKey, count = 0 })
				index[c.pileKey] = #chests
			end
			chests[index[c.pileKey]].count += c.count
		end
		table.insert(out, {
			uid = entry.uid,
			source = entry.source,
			at = entry.at,
			gold = r.gold,
			items = r.items,
			chests = if #chests > 0 then chests else nil,
			uniqueId = r.uniqueId,
		})
	end
	return out
end

return Inbox
