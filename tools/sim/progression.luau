--!strict
-- 育成シミュレーター：1パーティで転生を繰り返し、各周回（Lv1→上限）の所要時間を測る（D-071）
-- 使い方:
--   lune run tools/sim/progression                       現在の値で測る
--   lune run tools/sim/progression -- --tune 4 --write   周回ごとの経験値倍率（expCycleMult）を目標時間に合わせて
--                                                        4回反復調整し、src/data/Constants.luau に書き込む
-- 想定するプレイ：
--   - パーティは初期の4人（StarterSet）のまま。プレイヤーは常に探索を続ける（待ち時間なし）
--   - 行き先は「踏破率50%以上のうち、1秒あたりの経験値が最も多いダンジョン」。未踏破の最深ダンジョンの
--     踏破率が40%以上なら、解放のためにそこへ行く
--   - 装備は「踏破済みの最深ダンジョン」相当に更新し続ける（アイテムレベル＝tier、レアリティ＝最低ランク+1、+1）
--   - 全員が上限レベルに達したら転生。加算分は無料の引き直し＋1回の最良値（D-072）

local fs = require("@lune/fs")
local process = require("@lune/process")

local Data = require("../../src/data")
local Expedition = require("../../src/core/Expedition")
local Formulas = require("../../src/core/Formulas")
local Game = require("../../src/core/Game")
local MasterData = require("../../src/core/MasterData")
local Party = require("../../src/core/Party")
local Rng = require("../../src/core/Rng")
local Types = require("../../src/core/Types")

-- 目標：周回ごとの所要時間（時間）。0周目＝最初の転生まで（D-071）
local TARGET_HOURS = { 1, 1, 2, 4, 8, 16, 24, 48, 72 }

local opts = { tune = 0, write = false, writeGuild = false, seeds = 2 }
do
	local a = process.args
	local i = 1
	while i <= #a do
		if a[i] == "--tune" then
			opts.tune = tonumber(a[i + 1]) or 4
			i += 1
		elseif a[i] == "--seeds" then
			opts.seeds = tonumber(a[i + 1]) or 2
			i += 1
		elseif a[i] == "--write-guild" then
			opts.writeGuild = true
		elseif a[i] == "--write" then
			opts.write = true
		end
		i += 1
	end
end

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

local T0 = 1767225600
local SAMPLE = 24

local function runOnce(master: any, seed: number)
	local K = master.K
	local state = Game.newState(master, seed, T0)
	local now = T0
	local uids = table.clone(state.parties[1].slots)
	local cycle = 0
	local cycleStart = now
	local cycleSeconds = {}
	local cycleTickets = {}
	local cycleGuildExp = {}
	local cycleGuildInfo = {}
	local guildExpAtStart = 0
	local guildTicketsAtStart = 0
	local ticketsAtStart = 0
	local firstClears = {}
	local evalRng = Rng.new(seed * 7919)
	local rebirthRng = Rng.new(seed * 104729)
	local choice: string? = nil
	local needEval = true

	local function ctx(t: number)
		return { now = t, master = master, online = true }
	end

	local function bestClearedTier(): number
		local best = 1
		for _, d in master.dungeonList do
			if state.clearedDungeons[d.id] then
				best = math.max(best, d.tier)
			end
		end
		return best
	end

	local function upgradeGear()
		local tier = bestClearedTier()
		local d = master.dungeonList[tier]
		for _, e in state.equipment do
			if e.equippedBy then
				e.itemLevel = tier
				e.rarity = math.min(5, d.minChestRank + 1)
				e.grade = 1
			end
		end
	end

	local function evaluate(): string
		local snaps = Party.snapshots(state, 1, master)
		local best, bestScore = "dng_graveyard", -1
		local pushTarget = nil
		for _, d in master.dungeonList do
			if state.unlockedDungeons[d.id] then
				local clears, exp, secs = 0, 0, 0
				for _ = 1, SAMPLE do
					local log = Expedition.simulate(
						{ seed = evalRng:nextU32(), departAt = 0, dungeonId = d.id, members = snaps },
						master
					)
					if log.result == "clear" then
						clears += 1
					end
					for _, v in log.rewards.exp do
						exp += v
					end
					secs += log.totalSeconds
				end
				local rate = clears / SAMPLE
				if not state.clearedDungeons[d.id] and rate >= 0.4 then
					pushTarget = d.id
				end
				local score = exp / secs
				if rate >= 0.5 and score > bestScore then
					best, bestScore = d.id, score
				end
			end
		end
		return pushTarget or best
	end

	local function allAtCap(): boolean
		for _, uid in uids do
			local a = state.adventurers[uid]
			if a.level < a.levelCap then
				return false
			end
		end
		return true
	end

	local function rebirthAll()
		for _, uid in uids do
			local a = state.adventurers[uid]
			local newCount = a.rebirthCount + 1
			for _, s in Types.STAT_KEYS do
				local prev = a.baseStats[s]
				local best = 0
				for _ = 1, K.rebirthFreeRerolls + 1 do
					best = math.max(best, Formulas.rollRebirthBonus(prev, newCount, rebirthRng, K))
				end
				a.baseStats[s] = math.floor(prev / 2) + best
			end
			a.rebirthCount = newCount
			a.level = 1
			a.exp = 0
			a.levelCap = math.min(a.levelCap + K.levelCapPerRebirth, K.levelCapMax)
			if table.find(K.rebirthGiftAddAt, newCount) and #a.giftIds < K.giftMax then
				local pool = {}
				for _, g in master.giftList do
					if not table.find(a.giftIds, g.id) then
						table.insert(pool, g.id)
					end
				end
				table.insert(a.giftIds, pool[rebirthRng:int(1, #pool)])
			end
		end
	end

	local guard = 0
	while cycle < #TARGET_HOURS do
		guard += 1
		assert(guard < 400000, "ループが終わらない")
		if allAtCap() then
			table.insert(cycleSeconds, now - cycleStart)
			-- アイテムイベント由来のチケット（ギルド報酬分を除く）
			local guildTickets = state.stats.ticketsFromGuild or 0
			local tickets = (state.items.itm_slot_ticket or 0) - guildTickets
			table.insert(cycleTickets, tickets - ticketsAtStart)
			ticketsAtStart = tickets
			table.insert(cycleGuildInfo, { level = state.guild.level, tickets = guildTickets - guildTicketsAtStart })
			guildTicketsAtStart = guildTickets
			local gexp = state.stats.guildExpTotal or 0
			table.insert(cycleGuildExp, gexp - guildExpAtStart)
			guildExpAtStart = gexp
			if cycle == #TARGET_HOURS - 1 then
				break
			end
			rebirthAll()
			cycle += 1
			cycleStart = now
			needEval = true
		end
		if needEval or choice == nil then
			upgradeGear()
			choice = evaluate()
			needEval = false
		end
		local r = Game.execute(state, { type = "Dispatch", partyIndex = 1, dungeonId = choice }, ctx(now))
		assert(r.ok, r.error)
		local e = Game.query.expeditionOf(state, 1)
		now = e.returnAt
		for _, ev in Game.advance(state, ctx(now)) do
			if ev.type == "LevelUp" or ev.type == "DungeonUnlocked" then
				needEval = true
			end
			if ev.type == "FirstClear" then
				local a = state.adventurers[uids[1]]
				firstClears[ev.dungeonId] = { cycle = cycle, level = a.level, hours = (now - T0) / 3600 }
			end
		end
		-- 宝箱は経験値に関係しないので捨てる（倉庫・保管上限の影響を避ける）
		state.chests = {}
	end
	local _ = guildTicketsAtStart
	return cycleSeconds, firstClears, cycleTickets, cycleGuildExp, cycleGuildInfo
end

local lastTickets = {}
local lastGuildExp = {}
local lastGuildInfo = {}
local function measure(master: any)
	local sums = {}
	local clearsBySeed = {}
	lastTickets = {}
	lastGuildExp = {}
	for seed = 1, opts.seeds do
		local secs, clears, tickets, gexp, ginfo = runOnce(master, seed)
		if seed == 1 then
			lastGuildInfo = ginfo
		end
		for k, v in gexp do
			lastGuildExp[k] = (lastGuildExp[k] or 0) + v / opts.seeds
		end
		for k, v in secs do
			sums[k] = (sums[k] or 0) + v / opts.seeds
		end
		for k, v in tickets do
			lastTickets[k] = (lastTickets[k] or 0) + v / opts.seeds
		end
		clearsBySeed[seed] = clears
	end
	return sums, clearsBySeed[1]
end

local data = cloneDeep(Data)
local master = MasterData.load(data)

local function report(secs: { number }, clears: any)
	local total = 0
	print(
		"周回  上限Lv  所要（時間）  目標（時間）  倍率   チケット(探索)  ギルドLv  チケット(ギルド)"
	)
	for k, s in secs do
		total += s
		print(
			string.format(
				"%3d   %4d   %10.2f   %10.2f   %8.3f   %8.0f   %8d   %8d",
				k - 1,
				math.min(master.K.levelCapInitial + master.K.levelCapPerRebirth * (k - 1), master.K.levelCapMax),
				s / 3600,
				TARGET_HOURS[k],
				master.K.expCycleMult[k],
				lastTickets[k] or 0,
				lastGuildInfo[k] and lastGuildInfo[k].level or 0,
				lastGuildInfo[k] and lastGuildInfo[k].tickets or 0
			)
		)
	end
	print(string.format("合計 %.1f 時間", total / 3600))
	print("\nダンジョンの初踏破（周回・レベル・累計時間）")
	for _, d in master.dungeonList do
		local c = clears[d.id]
		if c then
			print(string.format("  %-14s 周回%d Lv%3d  %.1f時間", d.name, c.cycle, c.level, c.hours))
		else
			print(string.format("  %-14s 未踏破", d.name))
		end
	end
end

local secs, clears = measure(master)
for iter = 1, opts.tune do
	local mult = data.Constants.expCycleMult
	for k = 1, #TARGET_HOURS do
		if secs[k] and secs[k] > 0 then
			mult[k] = mult[k] * (TARGET_HOURS[k] * 3600) / secs[k]
		end
	end
	master = MasterData.load(data)
	secs, clears = measure(master)
	print(`反復 {iter}: ` .. table.concat(
		(function()
			local t = {}
			for _, s in secs do
				table.insert(t, string.format("%.2fh", s / 3600))
			end
			return t
		end)(),
		" "
	))
end

report(secs, clears)

-- ギルドレベル表の生成（D-074） --------------------------------------------
-- 周回 k の終わりにギルドレベル 10(k+1) になるよう必要経験値を決め、
-- 「1回の転生で4人が必要とするチケット × PLAY_SHARE」から、アイテムイベント由来の分を引いた残りを
-- その周回のレベルアップ報酬に均等に割り振る。10の倍数のレベルではポーションも配る。
local PLAY_SHARE = 0.5 -- 遊んで手に入る割合
local ROLLS_FIRST, ROLLS_LAST = 100, 300 -- 1キャラが「良い結果」に届く期待回数（転生1回目・8回目）
local LEVELS_PER_CYCLE = 10

local function ticketsNeededForRebirth(n: number): number
	local rolls = ROLLS_FIRST + (ROLLS_LAST - ROLLS_FIRST) * (n - 1) / 7
	local paid = rolls - 1 - master.K.rebirthFreeRerolls
	return 4 * paid * PLAY_SHARE
end

if opts.writeGuild then
	local levels = {}
	local maxLevel = 100
	local cycles = #TARGET_HOURS
	for lv = 1, maxLevel do
		levels[lv] = { level = lv, expToNext = 0, rewards = {} }
	end
	for k = 1, cycles do
		local startLv = if k == 1 then 1 else LEVELS_PER_CYCLE * (k - 1)
		local endLv = LEVELS_PER_CYCLE * k
		local ups = endLv - startLv
		local gexp = lastGuildExp[k] or lastGuildExp[#lastGuildExp]
		local perLevel = math.max(1, math.floor(gexp / ups + 0.5))
		local n = math.min(k, 8)
		local need = ticketsNeededForRebirth(n) - (lastTickets[k] or 0)
		local perLevelTickets = math.max(1, math.ceil(need / ups))
		for lv = startLv, endLv - 1 do
			levels[lv].expToNext = perLevel
			levels[lv + 1].rewards = { itm_slot_ticket = perLevelTickets }
		end
	end
	-- 最終周回の後（90〜99）は最終周回と同じ
	local last = levels[LEVELS_PER_CYCLE * cycles - 1]
	for lv = LEVELS_PER_CYCLE * cycles, maxLevel - 1 do
		levels[lv].expToNext = last.expToNext
		levels[lv + 1].rewards = table.clone(levels[LEVELS_PER_CYCLE * cycles].rewards)
	end
	for lv = 10, maxLevel, 10 do
		levels[lv].rewards.itm_potion_appearance_change = 1
		levels[lv].rewards.itm_potion_appearance_keep = 1
	end
	local out = {
		"--!strict",
		"-- ギルドレベル（D-074）",
		"-- ※このファイルは tools/sim/progression.luau（--write-guild）が生成する。手で編集しない。",
		"-- expToNext：そのレベルから次のレベルまでの必要ギルド経験値 / rewards：そのレベルに上がったときの報酬",
		"",
		"return {",
		`	maxLevel = {maxLevel},`,
		"	levels = {",
	}
	for _, row in levels do
		local r = {}
		local keys = {}
		for id in row.rewards do
			table.insert(keys, id)
		end
		table.sort(keys)
		for _, id in keys do
			table.insert(r, `{id} = {row.rewards[id]}`)
		end
		table.insert(
			out,
			`		\{ level = {row.level}, expToNext = {row.expToNext}, rewards = \{ {table.concat(r, ", ")} \} \},`
		)
	end
	table.insert(out, "	},")
	table.insert(out, "}")
	fs.writeFile("src/data/GuildLevels.luau", table.concat(out, "\n") .. "\n")
	print("書き込み: src/data/GuildLevels.luau")
end

if opts.write then
	local parts = {}
	for _, m in data.Constants.expCycleMult do
		table.insert(parts, string.format("%.4g", m))
	end
	local path = "src/data/Constants.luau"
	local text = fs.readFile(path)
	local replaced, n =
		string.gsub(text, "expCycleMult = {[^}]*}", "expCycleMult = { " .. table.concat(parts, ", ") .. " }")
	assert(n == 1, "Constants.luau の expCycleMult が見つからない")
	fs.writeFile(path, replaced)
	print("\n書き込み: " .. path)
end
