--!strict
-- ログインの流れ（S-01 まとめ → 帰ったパーティの獲得演出 → カットイン最大1回 → カレンダー1回。D-132・D-155・D-208・D-281）。
-- 純粋な関数（Lune でテストする）。
--   summarize(events, view)：ログイン（reason "load"）で届いた出来事を1枚のまとめにする。
--     - まとめは受け取った報酬の合計だけ（D-281）：gold＝持ち帰ったゴールド＋自動売却のゴールド、
--       chestsByRank＝宝箱のレアリティごとの数、inbox＝受け取り箱に届いた物（アイコン＋数）。
--       宝箱のレアリティは、出来事にレアリティごとの数（chestsByRank：{ [rank]: 数 }）があるときだけ分ける。
--       ないときは rank = nil の1つ（レアリティを表さない閉じた箱：D-087）にまとめる。
--     - show：受け取った報酬（ゴールド・宝箱・受け取り箱に届いた物）が1つでもあればまとめを出す（D-281）。
--       休息ボーナスは廃止（D-280）。パーティの行・ギルドLv の行は出さない（D-281）。
--     - returned：留守の間に帰ったパーティごとの帰還の出来事（パーティの番号の順）。まとめを閉じたあと、
--       パーティごとに左の帰還のトーストで見せる（D-281）。
--     - cutIn：最大1回（D-132）。新しいダンジョンの解放を先に（D-238 ②）、なければギルドLvアップ（上がった分の報酬を合わせる）。
--     - loginBonus：その日の最初のログインで届いたログインボーナス（カレンダーをまとめの後に1回：D-208）。

local LoginFlow = {}

export type ChestCount = { rank: number?, n: number }

export type InboxLine = { kind: "gold" | "chest" | "item" | "unique", id: string?, rank: number?, n: number }

export type ReturnGroup = { partyIndex: number, events: { any } }

export type CutIn =
	{ kind: "dungeon", dungeonId: string }
	| { kind: "guild", level: number, rewards: { [string]: number } }

export type Summary = {
	show: boolean,
	gold: number,
	chests: number,
	chestsByRank: { ChestCount },
	inbox: { InboxLine },
	inboxCount: number,
	returned: { ReturnGroup },
	guildLevel: number?,
	unlocked: { string },
	cutIn: CutIn?,
	loginBonus: any?,
}

-- rank の小さい順（コモンから）。レアリティが分からない箱（nil）は最後
local function sortChests(byRank: { [number]: number }, unknown: number): { ChestCount }
	local out: { ChestCount } = {}
	for rank, n in byRank do
		if n > 0 then
			table.insert(out, { rank = rank, n = n })
		end
	end
	table.sort(out, function(a, b)
		return (a.rank :: number) < (b.rank :: number)
	end)
	if unknown > 0 then
		table.insert(out, { rank = nil, n = unknown })
	end
	return out
end

-- 受け取り箱に届いた物を、ゴールド → 宝箱（rank の順）→ アイテム（id の順）→ ユニークで並べる。
--   要約の受け取り箱（Game.query.inbox）は宝箱のランクを返さない（D-087）ので、ランクのない宝箱は rank = nil の1つにまとめる。
--   中身は要約の形（gold・items・chests・uniqueId が件の直下）でも、状態の形（rewards の下）でも読む
local function inboxLines(entries: { any }): { InboxLine }
	local gold, uniques, unknownChests = 0, 0, 0
	local chests: { [number]: number } = {}
	local items: { [string]: number } = {}
	for _, entry in entries do
		local r = entry.rewards or entry
		gold += r.gold or 0
		for _, c in r.chests or {} do
			if c.rank then
				chests[c.rank] = (chests[c.rank] or 0) + c.count
			else
				unknownChests += c.count
			end
		end
		for id, n in r.items or {} do
			items[id] = (items[id] or 0) + n
		end
		if r.uniqueId then
			uniques += 1
		end
	end
	local out: { InboxLine } = {}
	if gold > 0 then
		table.insert(out, { kind = "gold", n = gold })
	end
	for _, c in sortChests(chests, unknownChests) do
		table.insert(out, { kind = "chest", rank = c.rank, n = c.n })
	end
	local ids = {}
	for id in items do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		table.insert(out, { kind = "item", id = id, n = items[id] })
	end
	if uniques > 0 then
		table.insert(out, { kind = "unique", n = uniques })
	end
	return out
end

function LoginFlow.summarize(events: { any }, view: any, _now: number, _master: any): Summary
	local byParty: { [number]: { any } } = {}
	local gold, chests, unknownChests = 0, 0, 0
	local byRank: { [number]: number } = {}
	local guildLevel: number? = nil
	local guildRewards: { [string]: number } = {}
	local unlocked: { string } = {}
	local loginBonus = nil
	local inboxUids: { string } = {}
	for _, e in events do
		if e.type == "ExpeditionReturned" then
			local list = byParty[e.partyIndex] or {}
			table.insert(list, e)
			byParty[e.partyIndex] = list
			gold += (e.gold or 0) + (e.itemsSoldGold or 0)
			local n = e.chests or 0
			chests += n
			local ranked = 0
			for rank, c in e.chestsByRank or {} do
				byRank[rank] = (byRank[rank] or 0) + c
				ranked += c
			end
			unknownChests += math.max(0, n - ranked)
		elseif e.type == "GuildLevelUp" then
			guildLevel = math.max(guildLevel or 0, e.level)
			for id, n in e.rewards or {} do
				guildRewards[id] = (guildRewards[id] or 0) + n
			end
		elseif e.type == "DungeonUnlocked" then
			table.insert(unlocked, e.dungeonId)
		elseif e.type == "LoginBonus" then
			loginBonus = e
		end
		if e.inboxUid then
			table.insert(inboxUids, e.inboxUid) -- ログインボーナス・レイドの報酬など、受け取り箱に届いた（D-164）
		end
	end
	-- 届いた件の中身は要約（view.inbox）から引く
	local entries = {}
	for _, uid in inboxUids do
		for _, entry in view.inbox or {} do
			if entry.uid == uid then
				table.insert(entries, entry)
				break
			end
		end
	end
	local returned: { ReturnGroup } = {}
	for index, list in byParty do
		table.insert(returned, { partyIndex = index, events = list })
	end
	table.sort(returned, function(a, b)
		return a.partyIndex < b.partyIndex
	end)
	local cutIn: CutIn? = nil
	if #unlocked > 0 then
		cutIn = { kind = "dungeon", dungeonId = unlocked[#unlocked] }
	elseif guildLevel then
		cutIn = { kind = "guild", level = guildLevel, rewards = guildRewards }
	end
	return {
		show = gold > 0 or chests > 0 or #inboxUids > 0,
		gold = gold,
		chests = chests,
		chestsByRank = sortChests(byRank, unknownChests),
		inbox = inboxLines(entries),
		inboxCount = #inboxUids,
		returned = returned,
		guildLevel = guildLevel,
		unlocked = unlocked,
		cutIn = cutIn,
		loginBonus = loginBonus,
	}
end

export type RewardLine = { kind: "gold" | "chest" | "item", id: string?, n: number }

-- ログインボーナスの1日分の中身を、ゴールド → 宝箱 → チケット → ほかのアイテム（id の順）で並べる（D-155・D-190）
--   goldOf(goldMult) で額にする（基準のダンジョンの rewardGoldBase × goldMult：06章 §22）
function LoginFlow.dayRewards(spec: any, goldOf: (number) -> number): { RewardLine }
	local out: { RewardLine } = {}
	if spec == nil then
		return out
	end
	if spec.goldMult and spec.goldMult > 0 then
		table.insert(out, { kind = "gold", n = goldOf(spec.goldMult) })
	end
	local chests = 0
	for _, c in spec.chests or {} do
		chests += c.count
	end
	if chests > 0 then
		table.insert(out, { kind = "chest", n = chests })
	end
	local ids = {}
	for id in spec.items or {} do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local ta, tb = a == "itm_slot_ticket", b == "itm_slot_ticket"
		if ta ~= tb then
			return ta
		end
		return a < b
	end)
	for _, id in ids do
		table.insert(out, { kind = "item", id = id, n = spec.items[id] })
	end
	return out
end

-- カレンダーのマスの状態：受け取った日（today）より前は past、同じ日は today、後は future
function LoginFlow.cellState(day: number, today: number): "past" | "today" | "future"
	if day < today then
		return "past"
	elseif day == today then
		return "today"
	end
	return "future"
end

return LoginFlow
