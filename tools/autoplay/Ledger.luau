--!strict
-- 報酬の入手先の帳簿（docs/system/09_cli_sim_autoplay.md §3、D-160, D-161）
-- advance のイベントと、方針が実行したコマンドの結果から、報酬を入手先ごとに数える。ゲームのルールは持たない。
--   入手先：adventure（オンラインで出した探索）・offline（留守番の探索）・quest・login・playtime・friend・
--           mapevent（レアダンジョン・レイド）・guild（ギルドレベル）・referral（紹介）・merchant（商人で買った装備）
--   報酬  ：gold（入手先が直接くれたゴールド）・chests（宝箱の数）・tickets（ステータススロットチケット）・
--           tools（指南書・手鏡・ロケット。D-255 で旧ポーションから名前が変わった。アイテムの kind は potion_* のまま）
--           chestGold（宝箱の中身から出たゴールド：中身のゴールド・素材の自動売却・装備の売却。宝箱の入手先に付ける）
-- 普通のダンジョンの宝箱の山はオンラインと留守番の宝箱が混ざるので、中身は山に入った数の割合で按分する。

local Ledger = {}

Ledger.SOURCES = {
	"adventure",
	"offline",
	"quest",
	"login",
	"playtime",
	"friend",
	"mapevent",
	"guild",
	"referral",
	"merchant",
}
Ledger.RESOURCES = { "gold", "chestGold", "chests", "tickets", "tools" }

-- 配分の表（D-160）の列。key は目標の表（src/data/BalanceTargets.luau の columns）と同じ。
-- 留守番の探索は「冒険」に数える（D-200）。「プレイ時間」の列はプレイ時間報酬だけ。
-- 目標の値はここに書かない（MB：目標は src/data/BalanceTargets.luau だけに置く）
Ledger.COLUMNS = {
	{ key = "adventure", name = "冒険", sources = { "adventure", "offline" } },
	{ key = "quest", name = "クエスト", sources = { "quest" } },
	{ key = "login", name = "ログイン", sources = { "login" } },
	{ key = "playtime", name = "プレイ時間", sources = { "playtime" } },
	{ key = "friend", name = "フレンド", sources = { "friend" } },
	{ key = "mapevent", name = "マップイベント", sources = { "mapevent" } },
	{ key = "guild", name = "ギルドレベル", sources = { "guild" } },
}

local INBOX_SOURCE =
	{ quest = "quest", login = "login", playtime = "playtime", raid = "mapevent", referral = "referral" }

export type Weights = { [string]: number }

function Ledger.new(master: any): any
	local L = {
		master = master,
		totals = {}, -- resource → source → 量
		day = {}, -- その日の分（Ledger.takeDay で取り出して空にする）
		pileMix = {}, -- 普通のダンジョンの山 → { adventure = n, offline = m }（未開封の数）
		equipSource = {}, -- 装備の uid → Weights（売ったときの入手先）
		value = { -- 1時間あたりの価値（D-161）。オンラインで出した探索と留守番の探索
			-- raidChests：レイド（オンラインでだけ出せる派遣）の宝箱。帰還ではなく受け取り箱に届くので別に数える
			online = { gold = 0, chests = 0, exp = 0, returns = 0, raidChests = 0 },
			offline = { gold = 0, chests = 0, exp = 0, returns = 0, raidChests = 0 },
		},
		raids = {}, -- レイドの時間帯 → { hp, hits = { ダメージ… }, defeated }（D-179 の HP・ダメージの確認）
	}
	for _, r in Ledger.RESOURCES do
		L.totals[r] = {}
		L.day[r] = {}
	end
	return L
end

local function add(L: any, resource: string, src: string | Weights, n: number)
	if n == 0 then
		return
	end
	if type(src) == "string" then
		L.totals[resource][src] = (L.totals[resource][src] or 0) + n
		L.day[resource][src] = (L.day[resource][src] or 0) + n
	else
		for s, w in src do
			add(L, resource, s, n * w)
		end
	end
end

local function addItems(L: any, items: any, src: string | Weights)
	local master = L.master
	for itemId, n in items or {} do
		local row = master.items[itemId]
		if row then
			if row.kind == "ticket" then
				add(L, "tickets", src, n)
			elseif string.sub(row.kind, 1, 6) == "potion" then -- 指南書・手鏡・ロケット（D-255）
				add(L, "tools", src, n)
			end
		end
	end
end

-- 宝箱の山の入手先（中身を開けたときに使う）。普通の山は割合を1箱分減らす
local function pileSource(L: any, pileKey: string): string | Weights
	if string.sub(pileKey, 1, 8) == "special:" then
		local kind = string.match(pileKey, "^special:([^:]+)")
		if kind == "rare" or kind == "raid" then
			return "mapevent"
		end
		return INBOX_SOURCE[kind :: string] or kind :: string
	end
	local mix = L.pileMix[pileKey]
	local total = if mix then (mix.adventure or 0) + (mix.offline or 0) else 0
	if total <= 0 then
		return "adventure"
	end
	local w = { adventure = (mix.adventure or 0) / total, offline = (mix.offline or 0) / total }
	mix.adventure = math.max(0, (mix.adventure or 0) - w.adventure)
	mix.offline = math.max(0, (mix.offline or 0) - w.offline)
	return w
end

-- advance のイベント
function Ledger.onAdvance(L: any, events: { any })
	for _, ev in events do
		if ev.type == "ExpeditionReturned" then
			local src = if ev.eventSlot then "mapevent" elseif ev.offline then "offline" else "adventure"
			add(L, "gold", src, ev.gold + (ev.itemsSoldGold or 0))
			add(L, "chests", src, ev.chests)
			addItems(L, ev.items, src)
			if not ev.eventSlot and ev.chests > 0 then
				local mix = L.pileMix[ev.dungeonId] or {}
				L.pileMix[ev.dungeonId] = mix
				local k = if ev.offline then "offline" else "adventure"
				mix[k] = (mix[k] or 0) + ev.chests
			end
			local v = if ev.offline then L.value.offline else L.value.online
			v.gold += ev.gold + (ev.itemsSoldGold or 0)
			v.chests += ev.chests
			v.returns += 1
		elseif ev.type == "GuildLevelUp" then
			addItems(L, ev.rewards, "guild")
		elseif ev.type == "RaidHit" then
			local r = L.raids[ev.eventSlot] or { hp = ev.hp, hits = {}, defeated = false }
			L.raids[ev.eventSlot] = r
			table.insert(r.hits, ev.damage)
			r.defeated = r.defeated or ev.defeated
		end
	end
end

-- 方針が実行したコマンド（Policy.setListener に渡す）
function Ledger.onCommand(L: any, _state: any, cmd: any, result: any, extra: any)
	if cmd.type == "ClaimInbox" then
		for _, entry in extra or {} do
			local src = INBOX_SOURCE[entry.source] or entry.source
			local r = entry.rewards
			add(L, "gold", src, r.gold or 0)
			addItems(L, r.items, src)
			for _, c in r.chests or {} do
				add(L, "chests", src, c.count)
				if entry.source == "raid" then
					L.value.online.raidChests += c.count
				end
			end
		end
		return
	end
	for _, ev in result.events or {} do
		if ev.type == "QuestClaimed" or ev.type == "QuestBonusClaimed" then
			-- クエストはその場で受け取る（D-286）
			local r = ev.rewards or {}
			add(L, "gold", "quest", r.gold or 0)
			addItems(L, r.items, "quest")
			for _, c in r.chests or {} do
				add(L, "chests", "quest", c.count)
			end
		elseif ev.type == "FriendReward" then
			add(L, "gold", "friend", ev.gold)
		elseif ev.type == "ChestsOpened" then
			for _, list in { ev.normal, ev.special } do
				for _, res in list do
					local src = pileSource(L, res.pileKey)
					add(L, "chestGold", src, res.gold + (res.soldItemsGold or 0) + (res.autoSoldGold or 0))
					addItems(L, res.items, src)
					for _, uid in res.equipmentUids do
						L.equipSource[uid] = src
					end
				end
			end
		elseif ev.type == "Sold" then
			for _, uid in ev.equipmentUids do
				local price = if extra then extra[uid] else nil
				if price then
					add(L, "chestGold", L.equipSource[uid] or "adventure", price)
				end
				L.equipSource[uid] = nil
			end
		elseif ev.type == "MerchantBought" then
			L.equipSource[ev.equipmentUid] = "merchant"
		end
	end
end

-- その日の分を取り出して空にする
function Ledger.takeDay(L: any): any
	local d = L.day
	L.day = {}
	for _, r in Ledger.RESOURCES do
		L.day[r] = {}
	end
	return d
end

-- 経験値の計測（D-161 の価値の比較）：冒険者ごとの（転生回数, レベル, 経験値）を覚えておき、増えた分を数える
function Ledger.expSnapshot(state: any): any
	local snap = {}
	for uid, a in state.adventurers do
		snap[uid] = { rb = a.rebirthCount, lv = a.level, exp = a.exp }
	end
	return snap
end

function Ledger.expGained(state: any, snap: any, expToNext: (number, number) -> number): number
	local sum = 0
	for uid, a in state.adventurers do
		local s = snap[uid]
		if s and s.rb == a.rebirthCount then
			local g = a.exp - s.exp
			for lv = s.lv, a.level - 1 do
				g += expToNext(lv, a.rebirthCount)
			end
			sum += math.max(0, g)
		end
	end
	return sum
end

-- レイドの要約（D-179）：出た時間帯の数・討伐率・参加パーティ数・1パーティのダメージ÷HP・討伐に要ったパーティ数の分布
function Ledger.raidSummary(L: any): any
	local s = { slots = 0, defeated = 0, parties = 0, ratios = {}, needed = { 0, 0, 0, 0 }, notEnough = 0 }
	for _, r in L.raids do
		s.slots += 1
		s.parties += #r.hits
		if r.defeated then
			s.defeated += 1
		end
		local acc, need = 0, nil
		for i, d in r.hits do
			table.insert(s.ratios, d / math.max(1, r.hp))
			acc += d
			if need == nil and acc > r.hp then
				need = i
			end
		end
		if need then
			local k = math.min(need, 4)
			s.needed[k] += 1
		else
			s.notEnough += 1
		end
	end
	table.sort(s.ratios)
	return s
end

-- 列（D-160 の表）ごとの割合（%）を列の key で返す
function Ledger.sharesByKey(totals: any, resources: { string }): ({ [string]: number }, number)
	local list, all = Ledger.shares(totals, resources)
	local out = {}
	for i, c in Ledger.COLUMNS do
		out[c.key] = list[i]
	end
	return out, all
end

-- 列（D-160 の表）ごとの割合（%）。resources は合わせて数える報酬の一覧
function Ledger.shares(totals: any, resources: { string }): ({ number }, number)
	local col = {}
	local all = 0
	for i, c in Ledger.COLUMNS do
		local n = 0
		for _, r in resources do
			for _, s in c.sources do
				n += totals[r][s] or 0
			end
		end
		col[i] = n
	end
	-- 表にない入手先（紹介・商人）も分母に入れる
	for _, r in resources do
		for _, n in totals[r] do
			all += n
		end
	end
	local out = {}
	for i, n in col do
		out[i] = if all > 0 then n / all * 100 else 0
	end
	return out, all
end

return Ledger
