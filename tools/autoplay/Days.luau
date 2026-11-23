--!strict
-- 自動プレイの「1日の流れ」（docs/system/09_cli_sim_autoplay.md §3、D-161。M7b-6）
-- 使い方: lune run tools/autoplay -- --days 15 --profile heavy --seed 1 [--friends 0] [--policy greedy]
-- 1日のオンラインの時間（Schedule.profiles）を何回かのログインに分け、ログアウトの間は留守番として時間を進める
-- （core の Game.advance に ctx.online = false）。ログインしたら自動再派遣を外し、帰還のたびに方針（Policy）で出し直す。
-- ログアウトのときに各パーティへ自動再派遣を付ける。最大の育成に届いたらそこで止める。
-- 測るもの：最大の育成までの暦日数、1時間あたりの価値（オンライン／留守番）、報酬の入手先の配分（D-160）、
--           ゴールドの残高の推移（D-163）、日ごとの要約（CSV）。

local fs = require("@lune/fs")

local Formulas = require("../../src/core/Formulas")
local Game = require("../../src/core/Game")
local MapEvent = require("../../src/core/MapEvent")
local Party = require("../../src/core/Party")
local Rng = require("../../src/core/Rng")
local Ledger = require("./Ledger")
local Policy = require("./Policy")
local Schedule = require("./Schedule")

local Days = {}

local T0 = 1767225600 -- 2026-01-01 00:00 UTC（ツールの起点。ゲームの数値ではない）
local DAY = 86400

-- 最大の育成（D-161 の「最大の育成まで」）：決定・仕様書に定義がないので、ここでは
--   パーティ枠を最後まで拡張し、パーティに入っている全員が最後の転生（上限レベル levelCapMax）で上限レベルに届いた状態
-- とする（要確認）
local MAX_GROWTH_TEXT =
	"パーティ枠を最後まで拡張し、パーティに入っている全員が最後の転生（上限レベル levelCapMax）で上限レベルに届いた状態（仮の定義）"

local function maxPartySlots(master: any): number
	local e = master.expansions.exp_party
	return e.steps[#e.steps].value
end

local function partyMembers(state: any): { any }
	local out = {}
	for _, p in state.parties do
		for _, uid in p.slots do
			if uid ~= Party.EMPTY and state.adventurers[uid] then
				table.insert(out, state.adventurers[uid])
			end
		end
	end
	return out
end

local function maxGrowthReached(state: any, master: any): boolean
	if state.expansions.partySlots < maxPartySlots(master) then
		return false
	end
	local members = partyMembers(state)
	if #members < state.expansions.partySlots * Party.SIZE then
		return false
	end
	local capMax = master.K.levelCapMax
	for _, a in members do
		if a.levelCap < capMax or a.level < capMax then
			return false
		end
	end
	return true
end

local function short(n: number): string
	local s = if n < 0 then "-" else ""
	n = math.abs(n)
	if n >= 10 ^ 8 then
		return s .. string.format("%.2f億", n / 10 ^ 8)
	elseif n >= 10 ^ 4 then
		return s .. string.format("%.1f万", n / 10 ^ 4)
	end
	return s .. tostring(math.floor(n))
end

local function count(t: any): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

function Days.run(opts: any, master: any): any
	local K = master.K
	local sessions = Schedule.profiles[opts.profile]
	assert(sessions, `未知の型: {opts.profile}（light / core / heavy）`)
	local friends = opts.friends or Schedule.friendCount
	local dayBase = T0 - Schedule.tzOffsetHours * 3600 -- 1日目の 0時（Schedule の地域の時計）
	local firstLogin = dayBase + math.floor(sessions[1].at * 3600)
	local onlinePerDay = 0
	for _, s in sessions do
		onlinePerDay += s.minutes
	end

	local state = Game.newState(master, opts.seed, firstLogin)
	local rng = Rng.new(opts.seed * 31337)
	local ledger = Ledger.new(master)
	Policy.setListener(function(st, cmd, r, extra)
		Ledger.onCommand(ledger, st, cmd, r, extra)
	end)
	local stats = { rebirths = 0, rebirthRerolls = 0, maxRebirth = 0, hired = 0, trainedLevels = 0, timeline = {} }
	local function ctx(t: number, online: boolean): any
		return { now = t, master = master, online = online, friendCount = friends }
	end
	local function expToNext(lv: number, rb: number): number
		return Formulas.expToNext(lv, K, rb)
	end
	local function note(t: number, what: string)
		table.insert(stats.timeline, { at = t, what = what })
	end

	local time = { online = 0, offline = 0, offlineActive = 0 }
	local milestones: { [string]: number } = {}
	local function mark(key: string, t: number)
		if milestones[key] == nil then
			milestones[key] = t
			note(t, key)
		end
	end
	local function watchEvents(evs: { any })
		for _, ev in evs do
			if ev.type == "DungeonUnlocked" then
				note(ev.at, `解放：{master.dungeons[ev.dungeonId].name}`)
			elseif ev.type == "UniqueJoined" then
				note(ev.at, `ユニーク加入：{master.uniques[ev.uniqueId].name}`)
			end
		end
	end

	local function stepOnline(t: number): { any }
		local snap = Ledger.expSnapshot(state)
		local evs = Game.advance(state, ctx(t, true))
		ledger.value.online.exp += Ledger.expGained(state, snap, expToNext)
		Ledger.onAdvance(ledger, evs)
		watchEvents(evs)
		return evs
	end

	-- 次に起きる時刻：帰還・マップイベントの始まり（商人、または空いているパーティがいてレアダンジョン・レイド）・フレンドボタン
	local function nextWake(now: number, limit: number): number
		local t = limit
		for _, e in state.expeditions do
			t = math.min(t, e.returnAt)
		end
		local interval = K.mapEventIntervalSeconds
		local idle = Policy.hasIdleParty(state)
		local slot = MapEvent.slotOf(now, K) + 1
		while MapEvent.startOf(slot, K) < t do
			local kind = MapEvent.eventAt(slot, master).kind
			if
				(kind == "merchant" and Schedule.behavior.merchant)
				or ((kind == "rareDungeon" or kind == "raid") and idle and Schedule.behavior.mapEvents)
			then
				t = MapEvent.startOf(slot, K)
				break
			end
			slot += 1
			if slot * interval > limit then
				break
			end
		end
		if friends > 0 then
			local f = Game.query.friend(state, now, friends, master)
			if f.blocker ~= "DAILY_LIMIT" and f.blocker ~= "NO_FRIEND" then
				t = math.min(t, math.max(f.nextAt, now + 1))
			end
		end
		return math.max(t, now + 1)
	end

	local function checkMilestones(t: number)
		local capMax = K.levelCapMax
		for _, a in state.adventurers do
			if a.rebirthCount >= 1 then
				mark("初めての転生", t)
			end
			if a.levelCap >= capMax then
				mark("初めて最後の転生（上限レベル最大）に到達", t)
				if a.level >= capMax then
					mark("初めて1人が最大の育成（最後の転生で上限レベル）", t)
				end
			end
		end
		if state.expansions.partySlots >= maxPartySlots(master) then
			mark("パーティ枠が最大", t)
		end
		local members = partyMembers(state)
		if #members > 0 then
			local allCap = true
			for _, a in members do
				allCap = allCap and a.levelCap >= capMax
			end
			if allCap and state.expansions.partySlots >= maxPartySlots(master) then
				mark("パーティの全員が最後の転生に到達", t)
			end
		end
		if maxGrowthReached(state, master) then
			mark("最大の育成", t)
		end
	end

	local dayRows = {}
	local logoutAt: number? = nil
	local prevGold = state.gold
	local reachedAt: number? = nil
	local finishedDays = 0

	for d = 0, opts.days - 1 do
		local dayStart = dayBase + d * DAY
		local dayOnline, dayOffline = 0, 0
		for _, s in sessions do
			local loginAt = dayStart + math.floor(s.at * 3600)
			local endAt = loginAt + s.minutes * 60
			-- 留守番（D-161）：ログアウトからログインまでを core の留守の計算で進める
			if logoutAt then
				local inflight = 0 -- ログアウトの前にオンラインで出した探索の経験値（オンラインの価値に数える）
				for _, e in state.expeditions do
					if not e.offline and not e.raidDamage then
						for _, v in e.log.rewards.exp do
							inflight += v
						end
					end
				end
				local snap = Ledger.expSnapshot(state)
				local evs = Game.advance(state, ctx(loginAt, false))
				local gained = Ledger.expGained(state, snap, expToNext)
				ledger.value.online.exp += math.min(gained, inflight)
				ledger.value.offline.exp += math.max(0, gained - inflight)
				Ledger.onAdvance(ledger, evs)
				watchEvents(evs)
				local away = loginAt - logoutAt
				time.offline += away
				time.offlineActive += math.min(away, K.offlineMaxSeconds)
				dayOffline += away
			end
			-- ログイン：その日の最初のオンラインの advance でログインボーナス・クエストの入れ替え（D-155, D-153）
			stepOnline(loginAt)
			Policy.onLogin(state, ctx(loginAt, true))
			Policy.manage(state, ctx(loginAt, true), rng, stats)
			local now = loginAt
			while now < endAt do
				now = math.min(nextWake(now, endAt), endAt)
				local evs = stepOnline(now)
				local returned = false
				for _, ev in evs do
					if ev.type == "ExpeditionReturned" or ev.type == "RaidReturned" then
						returned = true
						break
					end
				end
				local before = state.expansions.partySlots
				if returned then
					Policy.manage(state, ctx(now, true), rng, stats)
				else
					Policy.glance(state, ctx(now, true), rng, stats)
				end
				if state.expansions.partySlots ~= before then
					note(now, `パーティ枠 → {state.expansions.partySlots}`)
				end
				checkMilestones(now)
				if milestones["最大の育成"] then
					break
				end
			end
			-- ログアウト：自動再派遣を付け、最後に保存した時刻を書く（サーバーの保存の代わり：D-161, D-193）
			local outAt = math.min(now, endAt)
			Policy.onLogout(state, ctx(outAt, true))
			state.lastSavedAt = outAt
			logoutAt = outAt
			time.online += outAt - loginAt
			dayOnline += outAt - loginAt
			if milestones["最大の育成"] then
				reachedAt = milestones["最大の育成"]
				break
			end
		end

		-- 日ごとの要約
		local dayLedger = Ledger.takeDay(ledger)
		local function sum(res: string): number
			local n = 0
			for _, v in dayLedger[res] do
				n += v
			end
			return n
		end
		local minReb, maxReb, minLv, maxLv = math.huge, 0, math.huge, 0
		for _, a in partyMembers(state) do
			minReb = math.min(minReb, a.rebirthCount)
			maxReb = math.max(maxReb, a.rebirthCount)
			local sc = a.rebirthCount * 1000 + a.level
			minLv = math.min(minLv, sc)
			maxLv = math.max(maxLv, sc)
		end
		local deepest = "-"
		for _, dg in master.dungeonList do
			if state.clearedDungeons[dg.id] then
				deepest = dg.name
			end
		end
		local qDone = { daily = 0, weekly = 0 }
		for _, period in { "daily", "weekly" } do
			for _, e in state.quests[period].entries do
				if e.done then
					qDone[period] += 1
				end
			end
		end
		local unopened = 0
		for _, v in Game.query.chestsByRank(state, master) do
			unopened += v
		end
		local income = sum("gold") + sum("chestGold")
		local ed = stats.eventDispatches or {}
		table.insert(dayRows, {
			day = d + 1,
			onlineMin = dayOnline / 60,
			offlineH = dayOffline / 3600,
			gold = state.gold,
			income = income,
			goldDirect = sum("gold"),
			spent = income - (state.gold - prevGold),
			guildLevel = state.guild.level,
			parties = state.expansions.partySlots,
			roster = count(state.adventurers),
			minReb = if minReb == math.huge then 0 else minReb,
			maxReb = maxReb,
			best = string.format("転生%d Lv%d", maxLv // 1000, maxLv % 1000),
			worst = if minLv == math.huge then "-" else string.format("転生%d Lv%d", minLv // 1000, minLv % 1000),
			deepest = deepest,
			chestsGained = sum("chests"),
			chestsOpened = state.stats.chestsOpened or 0,
			unopened = unopened,
			tickets = state.items.itm_slot_ticket or 0,
			ticketsGained = sum("tickets"),
			rare = ed.rareDungeon or 0,
			raid = ed.raid or 0,
			merchant = state.stats.merchantBought or 0,
			friendGold = dayLedger.gold.friend or 0,
			questsDaily = qDone.daily,
			questsWeekly = qDone.weekly,
			loginDay = state.login.day,
			playtimeSteps = state.playtime.claimedSteps,
			rebirths = state.stats.rebirths or 0,
		})
		prevGold = state.gold
		finishedDays = d + 1
		if reachedAt then
			break
		end
	end

	return {
		state = state,
		ledger = ledger,
		stats = stats,
		dayRows = dayRows,
		time = time,
		milestones = milestones,
		reachedAt = reachedAt,
		firstLogin = firstLogin,
		dayBase = dayBase,
		finishedDays = finishedDays,
		onlinePerDay = onlinePerDay,
		friends = friends,
	}
end

-- レポート -------------------------------------------------------------------

local function pct(x: number): string
	return string.format("%.1f", x)
end

local function dayOf(t: number, base: number): string
	local sec = t - base
	local d = sec // DAY
	local rem = sec % DAY
	return string.format("%d日目 %02d:%02d", d + 1, rem // 3600, (rem % 3600) // 60)
end

function Days.report(r: any, opts: any, elapsed: number): (string, string)
	local L = r.ledger
	local lines = {
		`# 自動プレイ・1日の流れ（型 {opts.profile}、方針 {opts.policy}、seed {opts.seed}、{opts.days}日）`,
		"",
		`- 1日のオンライン：{r.onlinePerDay}分（ログイン{#Schedule.profiles[opts.profile]}回。tools/autoplay/Schedule.luau。仮）`,
		`- 友達の数（ctx.friendCount）：{r.friends}`,
		`- 進めた暦日数：{r.finishedDays}日 ／ 実行時間：{string.format("%.1f", elapsed)}秒`,
		"",
		"## 最大の育成までの暦日数（D-161）",
		"",
		`定義：{MAX_GROWTH_TEXT}`,
		"",
	}
	if r.reachedAt then
		table.insert(
			lines,
			`- 到達：{dayOf(r.reachedAt, r.dayBase)}（{string.format("%.1f", (r.reachedAt - r.firstLogin) / DAY)}日）`
		)
	else
		table.insert(lines, `- {r.finishedDays}日では未到達`)
	end
	local keys = {
		"初めての転生",
		"初めて最後の転生（上限レベル最大）に到達",
		"初めて1人が最大の育成（最後の転生で上限レベル）",
		"パーティ枠が最大",
		"パーティの全員が最後の転生に到達",
		"最大の育成",
	}
	for _, k in keys do
		local t = r.milestones[k]
		table.insert(lines, `- {k}：{if t then dayOf(t, r.dayBase) else "-"}`)
	end

	-- 1時間あたりの価値（D-161：オンラインはオフラインの10倍以上）
	local on, off = L.value.online, L.value.offline
	local hOn = r.time.online / 3600
	local hOff = r.time.offline / 3600
	local hAct = r.time.offlineActive / 3600
	local function per(v: number, h: number): number
		return if h > 0 then v / h else 0
	end
	local function ratio(a: number, b: number): string
		return if b > 0 then string.format("%.1f倍", a / b) else "-"
	end
	table.insert(lines, "")
	table.insert(lines, "## 1時間あたりの価値：オンライン／留守番（D-161 の目標は10倍以上）")
	table.insert(lines, "")
	table.insert(
		lines,
		`オンライン {string.format("%.1f", hOn)}時間、留守 {string.format("%.1f", hOff)}時間（うち留守番が動く6時間までの分 {string.format(
			"%.1f",
			hAct
		)}時間）。`
	)
	table.insert(
		lines,
		"オンラインはオンラインで出した探索（ログアウトの時点で出ていた探索を含む）、留守番は留守番の探索の分。経験値は休息ボーナス・個人の補正を掛けた後（留守の計算の中でログアウト前の探索の分は概算で引く）。"
	)
	table.insert(lines, "")
	table.insert(
		lines,
		"| 価値 | オンライン/時 | 留守/時（留守の全時間） | 比 | 留守/時（6時間まで） | 比 |"
	)
	table.insert(lines, "| --- | --- | --- | --- | --- | --- |")
	for _, row in { { "経験値", "exp" }, { "ゴールド（探索）", "gold" }, { "宝箱", "chests" } } do
		local a, b, c = per(on[row[2]], hOn), per(off[row[2]], hOff), per(off[row[2]], hAct)
		table.insert(
			lines,
			string.format(
				"| %s | %s | %s | %s | %s | %s |",
				row[1],
				short(a),
				short(b),
				ratio(a, b),
				short(c),
				ratio(a, c)
			)
		)
	end

	-- 報酬の入手先の配分（D-160）
	table.insert(lines, "")
	table.insert(lines, "## 報酬の入手先の配分（D-160。%）")
	table.insert(lines, "")
	table.insert(
		lines,
		"ゴールド（直接）は入手先が直接くれた分（探索のゴールドと素材の自動売却・受け取り箱・フレンド）。ゴールド（宝箱込み）は宝箱の中身のゴールドと装備の売却を、宝箱の入手先に足したもの。紹介・商人は表にないが分母に入れる。"
	)
	table.insert(lines, "")
	local header = "| 報酬 | 行 |"
	local sep = "| --- | --- |"
	for _, c in Ledger.COLUMNS do
		header ..= ` {c.name} |`
		sep ..= " --- |"
	end
	header ..= " 合計 |"
	sep ..= " --- |"
	table.insert(lines, header)
	table.insert(lines, sep)
	local rows = {
		{ "ゴールド（直接）", { "gold" }, "gold" },
		{ "ゴールド（宝箱込み）", { "gold", "chestGold" }, "gold" },
		{ "宝箱", { "chests" }, "chests" },
		{ "チケット", { "tickets" }, "tickets" },
		{ "ポーション", { "potions" }, "potions" },
	}
	for _, row in rows do
		local shares, total = Ledger.shares(L.totals, row[2])
		local a = `| {row[1]} | 実測 |`
		for _, s in shares do
			a ..= ` {pct(s)} |`
		end
		a ..= ` {short(total)} |`
		table.insert(lines, a)
		if row[1] ~= "ゴールド（宝箱込み）" then
			local b = `| | 目標 |`
			local targets = Ledger.TARGETS[row[3]]
			for i = 1, #Ledger.COLUMNS do
				local t = targets[i]
				b ..= ` {if t == true then "あり" elseif t == nil then "—" else tostring(t)} |`
			end
			b ..= " |"
			table.insert(lines, b)
		end
	end
	table.insert(lines, "")
	table.insert(lines, "入手先ごとの量（合計）：")
	table.insert(lines, "")
	local h2 = "| 報酬 |"
	local s2 = "| --- |"
	for _, s in Ledger.SOURCES do
		h2 ..= ` {s} |`
		s2 ..= " --- |"
	end
	table.insert(lines, h2)
	table.insert(lines, s2)
	for _, res in Ledger.RESOURCES do
		local a = `| {res} |`
		for _, s in Ledger.SOURCES do
			a ..= ` {short(L.totals[res][s] or 0)} |`
		end
		table.insert(lines, a)
	end

	-- ゴールドの残高の推移（D-163）
	table.insert(lines, "")
	table.insert(lines, "## ゴールドの残高の推移（D-163：後半に積み上がらないか）")
	table.insert(lines, "")
	table.insert(lines, "| 日 | 収入 | 支出 | 残高 | 残高÷その日の収入 |")
	table.insert(lines, "| --- | --- | --- | --- | --- |")
	for _, d in r.dayRows do
		table.insert(
			lines,
			string.format(
				"| %d | %s | %s | %s | %s |",
				d.day,
				short(d.income),
				short(d.spent),
				short(d.gold),
				if d.income > 0 then string.format("%.2f", d.gold / d.income) else "-"
			)
		)
	end

	-- 日ごとの要約
	table.insert(lines, "")
	table.insert(lines, "## 日ごと")
	table.insert(lines, "")
	table.insert(
		lines,
		"| 日 | ギルドLv | パーティ | 所属 | 最も育った | 最も遅れた | 最深の踏破 | 宝箱(入手) | 未開封 | チケット | レア/レイド(累計) | 商人(累計) | クエスト日/週 | 転生(累計) |"
	)
	table.insert(lines, "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for _, d in r.dayRows do
		table.insert(
			lines,
			string.format(
				"| %d | %d | %d | %d | %s | %s | %s | %.0f | %d | %d | %d/%d | %d | %d/%d | %d |",
				d.day,
				d.guildLevel,
				d.parties,
				d.roster,
				d.best,
				d.worst,
				d.deepest,
				d.chestsGained,
				d.unopened,
				d.tickets,
				d.rare,
				d.raid,
				d.merchant,
				d.questsDaily,
				d.questsWeekly,
				d.rebirths
			)
		)
	end

	table.insert(lines, "")
	table.insert(lines, "## 出来事")
	table.insert(lines, "")
	for _, ev in r.stats.timeline do
		table.insert(lines, `- {dayOf(ev.at, r.dayBase)} {ev.what}`)
	end
	table.insert(lines, "")
	table.insert(
		lines,
		`雇用 {r.stats.hired}人 ／ 転生 {r.stats.rebirths}回 ／ トレーニングで上げたレベル {r.stats.trainedLevels}`
	)

	-- CSV
	local cols = {
		"day",
		"onlineMin",
		"offlineH",
		"gold",
		"income",
		"goldDirect",
		"spent",
		"guildLevel",
		"parties",
		"roster",
		"minReb",
		"maxReb",
		"deepest",
		"chestsGained",
		"chestsOpened",
		"unopened",
		"tickets",
		"ticketsGained",
		"rare",
		"raid",
		"merchant",
		"friendGold",
		"questsDaily",
		"questsWeekly",
		"loginDay",
		"playtimeSteps",
		"rebirths",
	}
	local csv = { table.concat(cols, ",") }
	for _, d in r.dayRows do
		local vals = {}
		for _, c in cols do
			local v = d[c]
			if type(v) == "number" and math.abs(v) < 0.005 then
				table.insert(vals, "0")
			elseif type(v) == "number" then
				table.insert(
					vals,
					if math.abs(v) >= 100 or v == math.floor(v)
						then string.format("%.0f", v)
						else string.format("%.2f", v)
				)
			else
				table.insert(vals, tostring(v))
			end
		end
		table.insert(csv, table.concat(vals, ","))
	end
	return table.concat(lines, "\n") .. "\n", table.concat(csv, "\n") .. "\n"
end

-- 実行して out/autoplay/ に Markdown と CSV を保存し、要約を表示する
function Days.main(opts: any, master: any, clock: () -> number)
	local started = clock()
	local r = Days.run(opts, master)
	local elapsed = clock() - started
	local md, csv = Days.report(r, opts, elapsed)
	fs.writeDir("out/autoplay")
	local base = `out/autoplay/{os.date("%Y%m%d-%H%M%S")}-{opts.profile}-{opts.policy}-seed{opts.seed}-{opts.days}d`
	fs.writeFile(base .. ".md", md)
	fs.writeFile(base .. ".csv", csv)
	if opts.quiet then
		print(`保存: {base}.md / .csv（{string.format("%.1f", elapsed)}秒）`)
	else
		print(md)
		print(`保存: {base}.md / {base}.csv`)
	end
end

return Days
