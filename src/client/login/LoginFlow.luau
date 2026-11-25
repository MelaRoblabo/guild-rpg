--!strict
-- ログインの流れ（S-01 まとめ → カットイン最大1回 → カレンダー1回。D-109・D-132・D-155・D-208）。純粋な関数（Lune でテストする）。
--   summarize(events, view)：ログイン（reason "load"）で届いた出来事を1枚のまとめにする。
--     - parties：メンバーのいるパーティごとに、留守の間に帰ったか（moved）、持ち帰った宝箱・ゴールド、Lv が上がった人。
--       動かなかったパーティ（自動再派遣がオフ）は moved = false（D-161・D-162）。
--     - gold：持ち帰ったゴールド＋自動売却のゴールドの合計。guildLevel：上がったあとの Lv（上がっていなければ nil）。
--     - show：留守番が動いた（帰還）・休息ボーナスがたまった・受け取り箱に届いた、のどれかがあればまとめを出す（D-208 ④）。
--       ギルドLvアップ・ダンジョン解放も出す（D-132）。休息ボーナスは出来事がないので、要約の lastSavedAt（前回の保存＝留守の始まり）
--       から今までの留守に core と同じ式（留守の時間 × restBonusRate、上限 restBonusMaxSeconds：06章 §13）で、たまった分があるかを見る。
--     - cutIn：最大1回（D-132）。新しいダンジョンの解放を先に（D-238 ②）、なければギルドLvアップ（上がった分の報酬を合わせる）。
--     - loginBonus：その日の最初のログインで届いたログインボーナス（カレンダーをまとめの後に1回：D-208）。

local LoginFlow = {}

export type PartyRow = {
	index: number,
	moved: boolean,
	chests: number,
	gold: number,
	members: { { uid: string, up: boolean } },
}

export type CutIn =
	{ kind: "dungeon", dungeonId: string }
	| { kind: "guild", level: number, rewards: { [string]: number } }

export type Summary = {
	show: boolean,
	parties: { PartyRow },
	gold: number,
	chests: number,
	guildLevel: number?,
	unlocked: { string },
	cutIn: CutIn?,
	loginBonus: any?,
}

function LoginFlow.summarize(events: { any }, view: any, now: number, master: any): Summary
	local ups: { [string]: boolean } = {}
	local byParty: { [number]: { chests: number, gold: number } } = {}
	local gold, chests = 0, 0
	local guildLevel: number? = nil
	local guildRewards: { [string]: number } = {}
	local unlocked: { string } = {}
	local loginBonus = nil
	local inboxArrived = false
	for _, e in events do
		if e.type == "ExpeditionReturned" then
			local p = byParty[e.partyIndex] or { chests = 0, gold = 0 }
			local g = (e.gold or 0) + (e.itemsSoldGold or 0)
			p.chests += e.chests or 0
			p.gold += g
			byParty[e.partyIndex] = p
			gold += g
			chests += e.chests or 0
		elseif e.type == "LevelUp" then
			ups[e.uid] = true
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
			inboxArrived = true -- ログインボーナス・レイドの報酬など、受け取り箱に届いた（D-164）
		end
	end
	local parties: { PartyRow } = {}
	for i, party in view.parties or {} do
		local members = {}
		for _, uid in party.slots or {} do
			if uid and view.adventurers[uid] then
				table.insert(members, { uid = uid, up = ups[uid] == true })
			end
		end
		if #members > 0 then
			local p = byParty[i]
			table.insert(parties, {
				index = i,
				moved = p ~= nil,
				chests = if p then p.chests else 0,
				gold = if p then p.gold else 0,
				members = members,
			})
		end
	end
	local cutIn: CutIn? = nil
	if #unlocked > 0 then
		cutIn = { kind = "dungeon", dungeonId = unlocked[#unlocked] }
	elseif guildLevel then
		cutIn = { kind = "guild", level = guildLevel, rewards = guildRewards }
	end
	return {
		show = next(byParty) ~= nil or guildLevel ~= nil or #unlocked > 0 or inboxArrived or LoginFlow.restGained(
			view,
			now,
			master
		),
		parties = parties,
		gold = gold,
		chests = chests,
		guildLevel = guildLevel,
		unlocked = unlocked,
		cutIn = cutIn,
		loginBonus = loginBonus,
	}
end

-- 留守の間に休息ボーナスがたまったか（D-161・D-162・D-208 ④）。上限に達していれば、たまっていない
function LoginFlow.restGained(view: any, now: number, master: any): boolean
	local K = master.K
	local from = view.lastSavedAt
	if from == nil or (view.restBonusSeconds or 0) <= 0 then
		return false
	end
	local gained = math.floor(math.max(0, now - from) * K.restBonusRate)
	local before = (view.restBonusSeconds or 0) - gained
	return gained > 0 and before < K.restBonusMaxSeconds
end

-- 休息ボーナスの輪の割合（上限に対する今の秒：D-162）
function LoginFlow.restShare(view: any, master: any): number
	local max = master.K.restBonusMaxSeconds
	if max <= 0 then
		return 0
	end
	return math.clamp((view.restBonusSeconds or 0) / max, 0, 1)
end

-- 受け取り箱の件数（宝箱ボタンの中の箱。D-164）
function LoginFlow.inboxCount(view: any): number
	return #(view.inbox or {})
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
