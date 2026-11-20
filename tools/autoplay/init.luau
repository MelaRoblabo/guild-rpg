--!strict
-- 自動プレイヤー（docs/system/09_cli_sim_autoplay.md §3）
-- 使い方: lune run tools/autoplay -- --hours 10 --seed 1
-- 帰還のたびに方針（Policy）で管理し、指標を1時間ごとに集計して out/autoplay/ に保存する。
-- プレイヤーはずっとオンラインで、帰還したらすぐ操作する想定（自動再派遣は使わない）。

local fs = require("@lune/fs")
local process = require("@lune/process")

local Data = require("../../src/data")
local Game = require("../../src/core/Game")
local MasterData = require("../../src/core/MasterData")
local Rng = require("../../src/core/Rng")
local Policy = require("./Policy")

local opts = { hours = 10, seed = 1 }
do
	local a = process.args
	for i = 1, #a do
		if a[i] == "--hours" then
			opts.hours = tonumber(a[i + 1]) or opts.hours
		elseif a[i] == "--seed" then
			opts.seed = tonumber(a[i + 1]) or opts.seed
		end
	end
end

local master = MasterData.load(Data)
local T0 = 1767225600
local state = Game.newState(master, opts.seed, T0)
local rng = Rng.new(opts.seed * 31337)
local now = T0
local stats = {
	rebirths = 0,
	rebirthRerolls = 0,
	maxRebirth = 0,
	hired = 0,
	timeline = {},
}
local returnsTimes = {}
local hourly = {}

local function ctx(t: number)
	return { now = t, master = master, online = true }
end

local function snapshotHour(h: number)
	local maxLv, minLv, maxReb = 0, math.huge, 0
	for _, a in state.adventurers do
		local lvScore = a.rebirthCount * 1000 + a.level
		maxLv = math.max(maxLv, lvScore)
		minLv = math.min(minLv, lvScore)
		maxReb = math.max(maxReb, a.rebirthCount)
	end
	local deepest = "-"
	for _, d in master.dungeonList do
		if state.clearedDungeons[d.id] then
			deepest = d.name
		end
	end
	-- その1時間の帰還間隔
	local inHour = {}
	for _, t in returnsTimes do
		if t > T0 + (h - 1) * 3600 and t <= T0 + h * 3600 then
			table.insert(inHour, t)
		end
	end
	local gap = if #inHour > 1 then (inHour[#inHour] - inHour[1]) / (#inHour - 1) else 0
	table.insert(hourly, {
		hour = h,
		gold = state.gold,
		guildLevel = state.guild.level,
		parties = state.expansions.partySlots,
		roster = (function()
			local n = 0
			for _ in state.adventurers do
				n += 1
			end
			return n
		end)(),
		returns = #inHour,
		gap = gap,
		chestsOpened = state.stats.chestsOpened or 0,
		tickets = state.items.itm_slot_ticket or 0,
		rebirths = stats.rebirths,
		best = string.format("転生%d Lv%d", maxLv // 1000, maxLv % 1000),
		worst = string.format("転生%d Lv%d", minLv // 1000, minLv % 1000),
		deepest = deepest,
		goldFromSales = state.stats.goldFromSales or 0,
	})
end

local endAt = T0 + math.floor(opts.hours * 3600)
local nextHour = 1
Policy.manage(state, ctx(now), rng, stats)
while now < endAt do
	local nextT = math.huge
	for _, e in state.expeditions do
		nextT = math.min(nextT, e.returnAt)
	end
	if nextT == math.huge then
		nextT = now + 60
	end
	nextT = math.min(nextT, endAt)
	while nextT >= T0 + nextHour * 3600 and nextHour <= opts.hours do
		-- 時間の区切りの直前まで進めてから集計
		local t = T0 + nextHour * 3600
		for _, ev in Game.advance(state, ctx(t)) do
			if ev.type == "ExpeditionReturned" then
				table.insert(returnsTimes, ev.at)
			end
		end
		snapshotHour(nextHour)
		nextHour += 1
	end
	now = nextT
	for _, ev in Game.advance(state, ctx(now)) do
		if ev.type == "ExpeditionReturned" then
			table.insert(returnsTimes, ev.at)
			if state.stats.firstReturnLogged == nil then
				state.stats.firstReturnLogged = 1
				table.insert(stats.timeline, { at = ev.at, what = "最初の帰還" })
			end
		elseif ev.type == "DungeonUnlocked" then
			table.insert(stats.timeline, { at = ev.at, what = `解放：{master.dungeons[ev.dungeonId].name}` })
		elseif ev.type == "UniqueJoined" then
			table.insert(
				stats.timeline,
				{ at = ev.at, what = `ユニーク加入：{master.uniques[ev.uniqueId].name}` }
			)
		end
	end
	local before = table.clone(state.expansions)
	Policy.manage(state, ctx(now), rng, stats)
	for k, v in state.expansions do
		if v ~= before[k] then
			table.insert(stats.timeline, { at = now, what = `拡張：{k} → {v}` })
		end
	end
end

-- レポート -------------------------------------------------------------------
local function hms(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d:%02d", sec // 3600, (sec % 3600) // 60, sec % 60)
end

local lines = {
	`# 自動プレイ（方針 greedy、seed {opts.seed}、{opts.hours}時間）`,
	"",
	`最初の宝箱を開けた時刻：{if state.stats.firstChestOpenedAt
		then hms(state.stats.firstChestOpenedAt - T0)
		else "-"}`,
	"",
	"## 1時間ごと",
	"",
	"| 時間 | ギルドLv | パーティ | 所属 | 帰還回数 | 帰還間隔(秒) | 所持金 | 売却益(累計) | チケット | 転生(累計) | 最も育った | 最も遅れた | 最深の踏破 |",
	"| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
}
for _, h in hourly do
	table.insert(
		lines,
		string.format(
			"| %d | %d | %d | %d | %d | %.0f | %d | %d | %d | %d | %s | %s | %s |",
			h.hour,
			h.guildLevel,
			h.parties,
			h.roster,
			h.returns,
			h.gap,
			h.gold,
			h.goldFromSales,
			h.tickets,
			h.rebirths,
			h.best,
			h.worst,
			h.deepest
		)
	)
end
table.insert(lines, "")
table.insert(lines, "## 出来事")
table.insert(lines, "")
for _, ev in stats.timeline do
	table.insert(lines, `- {hms(ev.at - T0)} {ev.what}`)
end
table.insert(lines, "")
table.insert(
	lines,
	`雇用 {stats.hired}人 ／ 転生 {stats.rebirths}回（引き直し {stats.rebirthRerolls}回）`
)
local md = table.concat(lines, "\n") .. "\n"
fs.writeDir("out/autoplay")
local path = `out/autoplay/{os.date("%Y%m%d-%H%M%S")}-seed{opts.seed}-{opts.hours}h.md`
fs.writeFile(path, md)
print(md)
print("保存: " .. path)
