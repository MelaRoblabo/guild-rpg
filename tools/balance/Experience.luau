--!strict
-- 体験の指標（MX。docs/reports/MX_engagement.md）
-- 自動プレイの出来事の記録（Days.run の opts.trace）から、「理論上、続けたくなるか」を測る値を出す。
-- ゲームのルールも目標の値も持たない（目標とスコアの線は src/data の表に置く）。
--
-- 出来事の分け方：
--   節目（big）    ：ダンジョンの解放・転生・ユニークの加入・パーティ枠とトレーニング場の拡張・転職・初めてのレアリティ
--   ごほうび（small）：レベルアップ・演出つきの開封・装備の更新・商人で買う・クエストの受け取り・ログインボーナス・雇用・初踏破・
--                      ほかの拡張
--   留守の間に起きたことは、次のログインの時刻に見たものとして数える
--   新しさ（novelty）：初めて起きたこと（各ダンジョンの解放、各レアリティを初めて開ける、各ユニーク、パーティ枠、
--                      各転生の回数に初めて届く、各転職先、各マップイベントの種類に初めて出る、初めて商人で買う）

local Experience = {}

local DAY = 86400
local BIG = { DungeonUnlocked = true, Reborn = true, UniqueJoined = true, JobChanged = true }
local BIG_EXPANSION = { exp_party = true, exp_training = true }
local SMALL = {
	LevelUp = true,
	MerchantBought = true,
	QuestClaimed = true,
	QuestBonusClaimed = true,
	LoginBonus = true,
	Hired = true,
	FirstClear = true,
	AutoEquipped = true,
	Expanded = true,
}

export type Collector = {
	sessions: { { login: number, logout: number?, moments: { { at: number, kind: string } } } },
	novelties: { { at: number, key: string } },
	seen: { [string]: boolean },
	offlineChests: number,
	loginPayoffs: { number },
	dailyQuests: number,
	commands: number,
	firstLogin: number?,
	firstChestAt: number?,
	firstUpgradeAt: number?,
	maxRebirth: number,
	bigTimes: { number },
	pending: { { kind: string } },
	chestsPerLogin: { number },
}

function Experience.new(): Collector
	return {
		sessions = {},
		novelties = {},
		seen = {},
		offlineChests = 0,
		loginPayoffs = {},
		dailyQuests = 0,
		commands = 0,
		firstLogin = nil,
		firstChestAt = nil,
		firstUpgradeAt = nil,
		maxRebirth = 0,
		bigTimes = {},
		pending = {},
		chestsPerLogin = {},
	}
end

local function current(c: Collector): any
	return c.sessions[#c.sessions]
end

local function moment(c: Collector, at: number?, kind: string, offline: boolean?)
	if offline then
		table.insert(c.pending, { kind = kind })
		return
	end
	local s = current(c)
	if s == nil or at == nil then
		return
	end
	table.insert(s.moments, { at = at, kind = kind })
	if kind == "big" then
		table.insert(c.bigTimes, at)
	end
end

local function novelty(c: Collector, at: number?, key: string)
	if at == nil or c.seen[key] then
		return
	end
	c.seen[key] = true
	table.insert(c.novelties, { at = at, key = key })
end

-- Days.run の opts.trace に渡す関数
function Experience.collector(c: Collector): (any, boolean) -> ()
	return function(ev: any, online: boolean)
		local t = ev.type
		if t == "Login" then
			c.firstLogin = c.firstLogin or ev.at
			table.insert(c.sessions, { login = ev.at, logout = nil, moments = {} })
			-- 留守の間に起きたことは、ログインして見た時刻に数える
			for _, p in c.pending do
				moment(c, ev.at, p.kind)
			end
			c.pending = {}
			-- 留守の間に届いた宝箱（戻ってきた見返り）。最初のログインは数えない
			if #c.sessions > 1 then
				table.insert(c.loginPayoffs, c.offlineChests)
			end
			c.offlineChests = 0
			return
		elseif t == "Logout" then
			local s = current(c)
			if s then
				s.logout = ev.at
			end
			return
		end
		if not online and t == "ExpeditionReturned" then
			c.offlineChests += ev.chests or 0
		end
		if t == "Command" then
			c.commands += 1
			if ev.command == "Equip" then
				c.firstUpgradeAt = c.firstUpgradeAt or ev.at
				moment(c, ev.at, "small")
			end
			return
		end
		if t == "ChestsOpened" then
			c.firstChestAt = c.firstChestAt or ev.at
			local newRarity, effect = false, false
			for _, list in { ev.normal or {}, ev.special or {} } do
				for _, res in list do
					effect = effect or res.effect == true
					if not c.seen[`rarity:{res.rank}`] then
						newRarity = true
					end
					novelty(c, ev.at, `rarity:{res.rank}`)
				end
			end
			table.insert(c.chestsPerLogin, ev.opened or 0)
			if newRarity then
				moment(c, ev.at, "big")
			elseif effect then
				moment(c, ev.at, "small")
			end
			return
		end
		if t == "AutoEquipped" then
			c.firstUpgradeAt = c.firstUpgradeAt or ev.at
		end
		if online and t == "QuestCompleted" and ev.period == "daily" then
			c.dailyQuests += 1
		end
		local off = not online
		if BIG[t] or (t == "Expanded" and BIG_EXPANSION[ev.expansionId]) then
			moment(c, ev.at, "big", off)
		elseif SMALL[t] then
			moment(c, ev.at, "small", off)
		end
		if t == "DungeonUnlocked" then
			novelty(c, ev.at, `dungeon:{ev.dungeonId}`)
		elseif t == "UniqueJoined" then
			novelty(c, ev.at, `unique:{ev.uniqueId}`)
		elseif t == "Expanded" then
			novelty(c, ev.at, `expansion:{ev.expansionId}:{ev.value}`)
		elseif t == "Reborn" then
			novelty(c, ev.at, `rebirth:{ev.rebirthCount}`)
		elseif t == "JobChanged" then
			novelty(c, ev.at, `job:{ev.to}`)
		elseif t == "EventDispatched" then
			novelty(c, ev.at, `event:{ev.kind}`)
		elseif t == "MerchantBought" then
			novelty(c, ev.at, "merchant")
		end
	end
end

local function percentile(list: { number }, p: number): number?
	if #list == 0 then
		return nil
	end
	local s = table.clone(list)
	table.sort(s)
	return s[math.clamp(math.ceil(#s * p), 1, #s)]
end

local function median(list: { number }): number?
	return percentile(list, 0.5)
end

-- 集計。endAt：測った終わり（最大の育成に届いた時刻、または最後のログアウト）
function Experience.finish(c: Collector, endAt: number, onlineMinutesPerDay: number): { [string]: any }
	local out: { [string]: any } = {}
	local first = c.firstLogin or 0
	out.firstChestSec = if c.firstChestAt then c.firstChestAt - first else nil
	out.firstUpgradeSec = if c.firstUpgradeAt then c.firstUpgradeAt - first else nil

	-- ごほうびの間隔（オンライン中）：ログイン→最初、出来事の間、最後→ログアウト
	local gaps, longest, withBig, firstSessionBig = {}, {}, 0, 0
	for i, s in c.sessions do
		local logout = s.logout or s.login
		local times = {}
		local big = false
		for _, m in s.moments do
			table.insert(times, m.at)
			big = big or m.kind == "big"
			if i == 1 and m.kind == "big" then
				firstSessionBig += 1
			end
		end
		table.sort(times)
		local prev = s.login
		local maxGap = 0
		for _, t in times do
			table.insert(gaps, t - prev)
			maxGap = math.max(maxGap, t - prev)
			prev = t
		end
		table.insert(gaps, logout - prev)
		maxGap = math.max(maxGap, logout - prev)
		table.insert(longest, maxGap)
		if big then
			withBig += 1
		end
	end
	out.rewardGapP90Sec = percentile(gaps, 0.9)
	out.longestGapMedianSec = median(longest)
	out.sessionsWithBigShare = if #c.sessions > 0 then withBig / #c.sessions else nil
	out.firstSessionBig = firstSessionBig

	-- 新しさ：日ごとの数と、新しさのない最長の日数（測った終わりまで）
	local days = math.max(1, math.ceil((endAt - first) / DAY))
	local times = {}
	for _, n in c.novelties do
		table.insert(times, n.at)
	end
	table.sort(times)
	local prev, drought = first, 0
	for _, t in times do
		drought = math.max(drought, t - prev)
		prev = t
	end
	drought = math.max(drought, endAt - prev)
	out.noveltyDroughtDays = drought / DAY
	out.noveltyDroughtShare = if endAt > first then drought / (endAt - first) else nil
	out.noveltyTotal = #c.novelties
	out.noveltyFirstWeek = 0
	for _, t in times do
		if t - first < 7 * DAY then
			out.noveltyFirstWeek += 1
		end
	end

	-- 後半の手応え：測った期間の後半（日数の半分より後）の新しさの数と、1回のプレイあたりの節目の数
	local half = first + (endAt - first) / 2
	out.noveltyLateHalf = 0
	for _, t in times do
		if t >= half then
			out.noveltyLateHalf += 1
		end
	end
	local lateSessions, lateBig = 0, 0
	for _, s in c.sessions do
		if s.login >= half then
			lateSessions += 1
			for _, m in s.moments do
				if m.kind == "big" then
					lateBig += 1
				end
			end
		end
	end
	out.bigPerSessionLate = if lateSessions > 0 then lateBig / lateSessions else nil
	out.chestsPerOpenMedian = median(c.chestsPerLogin)

	-- 停滞：節目のない日（暦日）の連続の最長
	local bigDays: { [number]: boolean } = {}
	for _, t in c.bigTimes do
		bigDays[(t - first) // DAY] = true
	end
	local run, longestFlat, flatDays = 0, 0, 0
	for d = 0, days - 1 do
		if bigDays[d] then
			run = 0
		else
			run += 1
			flatDays += 1
			longestFlat = math.max(longestFlat, run)
		end
	end
	out.flatDaysLongest = longestFlat
	out.flatDaysShare = flatDays / days

	-- 戻ってきた見返り：留守の間に宝箱が届いていたログインの割合と量
	local hit, sum = 0, 0
	for _, n in c.loginPayoffs do
		if n > 0 then
			hit += 1
		end
		sum += n
	end
	out.loginPayoffShare = if #c.loginPayoffs > 0 then hit / #c.loginPayoffs else nil
	out.loginPayoffChests = if #c.loginPayoffs > 0 then sum / #c.loginPayoffs else nil

	-- 毎日の習慣：デイリークエストを1日に達成した数（お題は1日3つ）
	out.dailyQuestsPerDay = c.dailyQuests / days

	-- 作業感：オンライン1時間あたりの操作の数
	local onlineHours = days * onlineMinutesPerDay / 60
	out.commandsPerHour = if onlineHours > 0 then c.commands / onlineHours else nil
	return out
end

-- 時刻表（レポート用）：最初のプレイの出来事と、日ごとの新しさ
function Experience.timeline(c: Collector): any
	local first = c.firstLogin or 0
	local s1 = c.sessions[1]
	local firstSession = {}
	if s1 then
		for _, m in s1.moments do
			table.insert(firstSession, { min = (m.at - first) / 60, kind = m.kind })
		end
	end
	local nov = {}
	for _, n in c.novelties do
		table.insert(nov, { day = (n.at - first) / DAY, key = n.key })
	end
	return { firstSession = firstSession, novelties = nov, sessions = #c.sessions }
end

return Experience
