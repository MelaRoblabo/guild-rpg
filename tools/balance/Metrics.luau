--!strict
-- 自動プレイ（1日の流れ）1回の結果から、成績表の指標を出す（MB。目標の表 src/data/BalanceTargets.luau の metric）
-- ゲームのルールも目標の値も持たない。値は数か、名前つきの数の表（配分・ダンジョンごと・途中の目安）。

local Ledger = require("../autoplay/Ledger")
local Policy = require("../autoplay/Policy")

local Metrics = {}

local DAY = 86400
local FINAL_REBIRTH = "初めて最後の転生（上限レベル最大）に到達"

-- 1時間あたりの価値のオンライン÷留守番。留守は「留守番が動く6時間までの分」で割る（D-292）
local function onlineRatio(r: any, key: string, extra: string?): number?
	local on, off = r.ledger.value.online, r.ledger.value.offline
	local hOn = r.time.online / 3600
	local hAct = r.time.offlineActive / 3600
	if hOn <= 0 or hAct <= 0 then
		return nil
	end
	local a = (on[key] + (if extra then on[extra] else 0)) / hOn
	local b = off[key] / hAct
	if b <= 0 then
		return nil
	end
	return a / b
end

-- 最後の転生に届くまでの「残高÷その日の収入」の最大（D-296。届いた後は数えない：D-199）
local function maxBalanceDays(r: any): number?
	local lastDay = math.huge
	local t = r.milestones[FINAL_REBIRTH]
	if t then
		lastDay = (t - r.dayBase) // DAY + 1
	end
	local m: number? = nil
	for _, d in r.dayRows do
		if d.day <= lastDay and d.income > 0 then
			local v = d.gold / d.income
			if m == nil or v > m then
				m = v
			end
		end
	end
	return m
end

-- 途中の目安の日（D-295）：最初のログインからの日数
local function milestoneDays(r: any): { [string]: number }
	local out = {}
	local function put(key: string, t: number)
		if out[key] == nil then
			out[key] = (t - r.firstLogin) / DAY
		end
	end
	for _, ev in r.stats.timeline do
		local what = ev.what
		if string.sub(what, 1, #"解放：") == "解放：" or string.find(what, "^パーティ枠 → %d") then
			put(what, ev.at)
		end
	end
	for _, key in { "初めての転生", FINAL_REBIRTH, "パーティ枠が最大" } do
		local t = r.milestones[key]
		if t then
			put(key, t)
		end
	end
	return out
end

-- 討伐に要ったパーティ数の割合（D-179。到着順）
local function raidPartiesNeeded(r: any): { [string]: number }?
	local rs = Ledger.raidSummary(r.ledger)
	if rs.slots == 0 then
		return nil
	end
	return {
		["1"] = rs.needed[1] / rs.slots,
		["2"] = rs.needed[2] / rs.slots,
		["3"] = rs.needed[3] / rs.slots,
		["4以上"] = rs.needed[4] / rs.slots,
		["届かない"] = rs.notEnough / rs.slots,
	}
end

local function total(r: any, resource: string): number
	local n = 0
	for _, v in r.ledger.totals[resource] do
		n += v
	end
	return n
end

-- 指標の名前 → 計算。値が出せないときは nil
Metrics.autoplay = {
	daysToMaxGrowth = function(r: any): number?
		if r.reachedAt == nil then
			return nil
		end
		return (r.reachedAt - r.firstLogin) / DAY
	end,
	milestoneDays = milestoneDays,
	onlineRatioGold = function(r: any): number?
		return onlineRatio(r, "gold")
	end,
	onlineRatioChests = function(r: any): number?
		return onlineRatio(r, "chests", "raidChests") -- レイドの宝箱を含む（D-200）
	end,
	maxBalanceDays = maxBalanceDays,
	merchantGoodShare = function(_r: any): number?
		local ms = Policy.merchantStats
		if ms.offers == 0 then
			return nil
		end
		return ms.upgrades / ms.offers
	end,
	shareGold = function(r: any): { [string]: number }
		return (Ledger.sharesByKey(r.ledger.totals, { "gold" }))
	end,
	shareChests = function(r: any): { [string]: number }
		return (Ledger.sharesByKey(r.ledger.totals, { "chests" }))
	end,
	shareTickets = function(r: any): { [string]: number }
		return (Ledger.sharesByKey(r.ledger.totals, { "tickets" }))
	end,
	shareTools = function(r: any): { [string]: number }
		return (Ledger.sharesByKey(r.ledger.totals, { "tools" }))
	end,
	toolsTotal = function(r: any): number
		return total(r, "tools")
	end,
	-- 1日あたりの指南書・手鏡・ロケットの数（D-298）。最大の育成に届いた日（届かなければ回した日数）で割る
	toolsPerDay = function(r: any): number?
		local days = if r.reachedAt then (r.reachedAt - r.firstLogin) / DAY else r.finishedDays
		if days <= 0 then
			return nil
		end
		return total(r, "tools") / days
	end,
	friendGoldShare = function(r: any): number
		return (Ledger.sharesByKey(r.ledger.totals, { "gold" })).friend
	end,
	raidPartiesNeeded = raidPartiesNeeded,
}

-- 目標の表で使っている autoplay の指標をすべて計算する。表にない指標名はエラー
function Metrics.computeAutoplay(r: any, names: { string }): { [string]: any }
	local out = {}
	for _, name in names do
		local f = Metrics.autoplay[name]
		assert(f, `未知の指標（autoplay）: {name}。tools/balance/Metrics.luau に計算を足す`)
		out[name] = f(r)
	end
	-- 参考（目標なし）：日数と最後の日
	out._finishedDays = r.finishedDays
	return out
end

return Metrics
