--!strict
-- 探索シミュレーター（docs/system/09_cli_sim_autoplay.md §2）
-- パーティ名は s<段階>[_<編成>]（tools/sim/Stages.luau）。例 s1、s5_magic
-- 使い方:
--   lune run tools/sim -- expedition --dungeon dng_graveyard --party s1 --runs 10000 --seed 1
--   lune run tools/sim -- sweep --runs 2000 [--dungeon <id>] [--party <name>]
--   lune run tools/sim -- show --dungeon dng_graveyard --party s1 --seed 1   （ログ1件を文章で表示）
-- 結果は out/sim/ に Markdown と JSON で保存する。

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Data = require("../src/data")
local Expedition = require("../src/core/Expedition")
local Formulas = require("../src/core/Formulas")
local MasterData = require("../src/core/MasterData")
local Rng = require("../src/core/Rng")
local Stages = require("@self/Stages")

-- 引数 -----------------------------------------------------------------
local positional, opts = {}, {}
do
	local i = 1
	local a = process.args
	while i <= #a do
		local v = a[i]
		if string.sub(v, 1, 2) == "--" and #v > 2 then
			opts[string.sub(v, 3)] = a[i + 1]
			i += 1
		elseif v ~= "--" then
			table.insert(positional, v)
		end
		i += 1
	end
end
local mode = positional[1] or "sweep"

-- --set key=value,key=value で定数を一時的に上書きする（バランス調整の試算用。データは変更しない）
local function cloneDeep(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = cloneDeep(x)
	end
	return out
end
local data = cloneDeep(Data)
local overrides = {}
if opts.set then
	for pair in string.gmatch(opts.set, "[^,]+") do
		local k, v = string.match(pair, "^([%w_]+)=([%d%.%-]+)$")
		assert(k and data.Constants[k] ~= nil, `--set の指定が不正: {pair}`)
		data.Constants[k] = tonumber(v)
		table.insert(overrides, pair)
	end
end
-- --hp-mult / --atk-mult でダンジョンの基準値を一律に掛ける（試算用）
for _, key in { "hp", "atk" } do
	local m = tonumber(opts[key .. "-mult"])
	if m then
		for _, d in data.Dungeons do
			d.base[key] = math.floor(d.base[key] * m)
		end
		table.insert(overrides, `{key}×{m}`)
	end
end
local master = MasterData.load(data)
local runs = tonumber(opts.runs) or 2000
local baseSeed = tonumber(opts.seed) or 1

-- 1組の統計 -------------------------------------------------------------
local function percentile(sorted: { number }, p: number): number
	if #sorted == 0 then
		return 0
	end
	local idx = math.clamp(math.ceil(#sorted * p), 1, #sorted)
	return sorted[idx]
end

local function simulateSet(dungeonId: string, presetName: string, n: number, seed: number)
	local stageIndex, comp = Stages.parse(presetName)
	local defs = Stages.party(master, stageIndex, comp)
	local preset = {
		desc = `段階{stageIndex}（転生{Stages.list[stageIndex].k}回・Lv{Stages.list[stageIndex].level}） {Stages.COMPOSITIONS[comp].desc}`,
	}
	local snaps = {}
	for _, d in defs do
		table.insert(snaps, Formulas.memberSnapshot(d, master))
	end
	local dungeon = master.dungeons[dungeonId]

	local s = {
		dungeon = dungeonId,
		party = presetName,
		runs = n,
		clears = 0,
		reachedSum = 0,
		reachedHist = {},
		times = {},
		chestTotal = 0,
		chestByRank = table.create(master.rarityCount, 0), -- D-085：レアリティの数だけ
		runsWithChest = 0,
		gold = 0,
		exp = 0,
		battles = 0,
		turns = 0,
		retreat = { wipe = 0, timeout = 0, trap = 0 },
		damageBySlot = { 0, 0, 0, 0 },
		downBySlot = { 0, 0, 0, 0 },
		giftTriggers = {},
		items = {},
		travelSeconds = 0,
	}
	for i = 1, n do
		local log = Expedition.simulate({
			seed = Rng.derive(seed, i),
			departAt = 0,
			dungeonId = dungeonId,
			members = snaps,
		}, master)
		if log.result == "clear" then
			s.clears += 1
		else
			s.retreat[log.retreatReason] += 1
		end
		s.reachedSum += log.reachedFloor
		s.reachedHist[log.reachedFloor] = (s.reachedHist[log.reachedFloor] or 0) + 1
		table.insert(s.times, log.totalSeconds)
		s.travelSeconds = log.travelSeconds
		if #log.rewards.chests > 0 then
			s.runsWithChest += 1
		end
		for _, c in log.rewards.chests do
			s.chestTotal += 1
			s.chestByRank[c.rank] += 1
		end
		s.gold += log.rewards.gold
		for _, e in log.rewards.exp do
			s.exp += e
		end
		for id, c in log.rewards.items do
			s.items[id] = (s.items[id] or 0) + c
		end
		local prevHp = {}
		for mi, sn in snaps do
			prevHp[mi] = sn.maxHp
		end
		for _, f in log.floors do
			if f.kind == "battle" then
				s.battles += 1
				s.turns += #(f.turns :: any)
				for _, t in f.turns :: any do
					if t.monster then
						s.damageBySlot[t.monster.target] += t.monster.amount
					end
				end
			end
			for _, t in f.giftTriggers do
				s.giftTriggers[t.giftId] = (s.giftTriggers[t.giftId] or 0) + 1
			end
			prevHp = f.hpAfter
		end
		for mi, hp in prevHp do
			if hp <= 0 then
				s.downBySlot[snaps[mi].slot] += 1
			end
		end
	end
	table.sort(s.times)
	local sumT = 0
	for _, t in s.times do
		sumT += t
	end
	return {
		dungeon = dungeonId,
		dungeonName = dungeon.name,
		floors = dungeon.floors,
		party = presetName,
		partyDesc = preset.desc,
		runs = n,
		clearRate = s.clears / n,
		avgReachedFloor = s.reachedSum / n,
		reachedHist = (function()
			local out = {}
			for f, c in s.reachedHist do
				out[tostring(f)] = c / n
			end
			return out
		end)(),
		retreatRate = { wipe = s.retreat.wipe / n, timeout = s.retreat.timeout / n, trap = s.retreat.trap / n },
		travelSeconds = s.travelSeconds,
		timeAvg = sumT / n,
		timeMedian = percentile(s.times, 0.5),
		timeP90 = percentile(s.times, 0.9),
		chestsPerRun = s.chestTotal / n,
		chestRunRate = s.runsWithChest / n,
		chestByRank = s.chestByRank,
		goldPerRun = s.gold / n,
		expPerRun = s.exp / n,
		turnsPerBattle = if s.battles > 0 then s.turns / s.battles else 0,
		damageShareBySlot = (function()
			local total = 0
			for _, d in s.damageBySlot do
				total += d
			end
			local out = {}
			for i, d in s.damageBySlot do
				out[i] = if total > 0 then d / total else 0
			end
			return out
		end)(),
		downRateBySlot = (function()
			local out = {}
			for i, d in s.downBySlot do
				out[i] = d / n
			end
			return out
		end)(),
		giftTriggersPerRun = (function()
			local out = {}
			for g, c in s.giftTriggers do
				out[g] = c / n
			end
			return out
		end)(),
		itemsPerRun = (function()
			local out = {}
			for id, c in s.items do
				out[id] = c / n
			end
			return out
		end)(),
		chestsPerHour = (s.chestTotal / n) / (sumT / n) * 3600,
		goldPerHour = (s.gold / n) / (sumT / n) * 3600,
	}
end

-- 出力 -----------------------------------------------------------------
local function pct(x: number): string
	return string.format("%.1f%%", x * 100)
end

local function f1(x: number): string
	return string.format("%.1f", x)
end

local function writeReport(name: string, results: { any })
	fs.writeDir("out/sim")
	local stamp = os.date("%Y%m%d-%H%M%S")
	local base = `out/sim/{stamp}-{name}`
	fs.writeFile(base .. ".json", serde.encode("json", results, true))

	local lines = {
		`# 探索シミュレーション（{name}）`,
		"",
		`各組 {runs} 回、seed={baseSeed}、エンジン v{Expedition.ENGINE_VERSION}`
			.. (if #overrides > 0 then `、上書き: {table.concat(overrides, ", ")}` else ""),
		"",
		"| ダンジョン | パーティ | 踏破率 | 平均到達F | 撤退(戦闘/時間切れ/罠) | 所要秒 中央/90% | 宝箱/回 | 宝箱あり | G/回 | 経験値/回 | 宝箱/時 | ターン/戦 | 戦闘不能率 隊列1-4 | 被弾割合 隊列1-4 |",
		"| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
	}
	for _, r in results do
		table.insert(
			lines,
			string.format(
				"| %s(%dF) | %s | %s | %s | %s/%s/%s | %d/%d | %.2f | %s | %s | %s | %s | %s | %s | %s |",
				r.dungeonName,
				r.floors,
				r.party,
				pct(r.clearRate),
				f1(r.avgReachedFloor),
				pct(r.retreatRate.wipe),
				pct(r.retreatRate.timeout),
				pct(r.retreatRate.trap),
				r.timeMedian,
				r.timeP90,
				r.chestsPerRun,
				pct(r.chestRunRate),
				f1(r.goldPerRun),
				f1(r.expPerRun),
				f1(r.chestsPerHour),
				f1(r.turnsPerBattle),
				table.concat({
					pct(r.downRateBySlot[1]),
					pct(r.downRateBySlot[2]),
					pct(r.downRateBySlot[3]),
					pct(r.downRateBySlot[4]),
				}, " "),
				table.concat({
					pct(r.damageShareBySlot[1]),
					pct(r.damageShareBySlot[2]),
					pct(r.damageShareBySlot[3]),
					pct(r.damageShareBySlot[4]),
				}, " ")
			)
		)
	end
	table.insert(lines, "")
	table.insert(lines, "パーティの説明：")
	local seen = {}
	for _, r in results do
		if not seen[r.party] then
			seen[r.party] = true
			table.insert(lines, `- {r.party}: {r.partyDesc}`)
		end
	end
	local md = table.concat(lines, "\n") .. "\n"
	fs.writeFile(base .. ".md", md)
	print(md)
	print(`保存: {base}.md / .json`)
end

-- ログ1件を文章で表示 ----------------------------------------------------
local function showLog(dungeonId: string, presetName: string, seed: number)
	local stageIndex, comp = Stages.parse(presetName)
	local snaps = {}
	for _, d in Stages.party(master, stageIndex, comp) do
		table.insert(snaps, Formulas.memberSnapshot(d, master))
	end
	local log = Expedition.simulate({ seed = seed, departAt = 0, dungeonId = dungeonId, members = snaps }, master)
	local jobName = {}
	for _, sn in snaps do
		jobName[sn.slot] = master.jobs[sn.jobId].name
		print(
			`隊列{sn.slot} {jobName[sn.slot]} HP{sn.maxHp} 攻{sn.atk} 物防{sn.pdef} 魔防{sn.mdef} 俊{sn.agi} 技{sn.dex} 魔{sn.mag}`
		)
	end
	print(`\n{master.dungeons[dungeonId].name}へ出発（片道 {log.travelSeconds} 秒）`)
	for _, f in log.floors do
		if f.kind == "battle" then
			local st = f.monsterStats
			print(
				`[{f.floor}F] {master.monsters[f.monsterId].name}（HP{st.hp} 攻{st.atk} 物防{st.pdef} 魔防{st.mdef}）→ {f.outcome}（{#f.turns}ターン）`
			)
		else
			print(`[{f.floor}F] イベント: {f.event} {serde.encode("json", f.detail)}`)
		end
		local hp = {}
		for i, sn in snaps do
			table.insert(hp, `{jobName[sn.slot]}{f.hpAfter[i]}`)
		end
		print("      HP: " .. table.concat(hp, " / "))
	end
	print(
		`\n結果: {log.result}{if log.retreatReason then "（" .. log.retreatReason .. "）" else ""} 所要 {log.totalSeconds} 秒`
	)
	print(`報酬: 宝箱 {#log.rewards.chests} 個、{log.rewards.gold}G、ギルド経験値 {log.rewards.guildExp}`)
end

-- 実行 -----------------------------------------------------------------
if mode == "expedition" then
	local r = simulateSet(opts.dungeon or "dng_graveyard", opts.party or "s1", runs, baseSeed)
	writeReport(`{r.dungeon}-{r.party}`, { r })
elseif mode == "sweep" then
	-- 各ダンジョンを「想定段階の前・想定・次」のバランス編成と、想定段階の各編成で回す
	local results = {}
	for _, d in master.dungeonList do
		if opts.dungeon == nil or opts.dungeon == d.id then
			local names = {}
			if opts.party then
				names = { opts.party }
			else
				local i = d.tier
				if i > 1 then
					table.insert(names, `s{i - 1}`)
				end
				table.insert(names, `s{i}`)
				if Stages.list[i + 1] then
					table.insert(names, `s{i + 1}`)
				end
				for _, c in { "phys", "magic", "nohealer", "reversed", "gifts" } do
					table.insert(names, `s{i}_{c}`)
				end
			end
			for _, name in names do
				table.insert(results, simulateSet(d.id, name, runs, baseSeed))
			end
		end
	end
	writeReport("sweep", results)
elseif mode == "show" then
	showLog(opts.dungeon or "dng_graveyard", opts.party or "s1", baseSeed)
else
	print("使い方: lune run tools/sim -- expedition|sweep|show [--dungeon id] [--party name] [--runs n] [--seed n]")
	process.exit(1)
end
