--!strict
-- 探索シミュレーターの指標（MB。目標の表 src/data/BalanceTargets.luau の source = "sim"）
-- 段階のパーティは tools/sim/Stages.luau（段階 i ＝ ダンジョン i に初めて挑むころ。バランス編成）。
--   stageClearRate       : 段階 i のパーティでダンジョン i の踏破率（D-069）
--   stageMedianSeconds   : 同じく所要秒の中央値（D-069・D-097・D-098）
--   earlyUnlockClearRate : 段階 i と i+1 の中間のパーティ（ダンジョン i でしばらく育てた、踏破の手前：D-300）で
--                          ダンジョン i+1 を先に開けたときの踏破率（D-294）

local Expedition = require("../../src/core/Expedition")
local Formulas = require("../../src/core/Formulas")
local Rng = require("../../src/core/Rng")
local Stages = require("../sim/Stages")

local SimMetrics = {}

local function snapsFor(master: any, stageIndex: number): { any }
	local out = {}
	for _, d in Stages.party(master, stageIndex, "balanced") do
		table.insert(out, Formulas.memberSnapshot(d, master))
	end
	return out
end

-- 段階 i と i+1 の中間のパーティ（D-300：前のダンジョンでしばらく育てた、踏破の手前）。
-- 基礎ステータスは2つの段階の平均（切り捨て）、装備はアイテムレベル・レアリティ・グレードの平均（切り捨て）
local function midSnapsFor(master: any, i: number): { any }
	local a, b = Stages.list[i], Stages.list[i + 1]
	local gear = {
		k = a.k,
		level = a.level,
		gearTier = (a.gearTier + b.gearTier) // 2,
		rarity = (a.rarity + b.rarity) // 2,
		grade = (a.grade + b.grade) // 2,
	}
	local out = {}
	for slot, jobId in Stages.COMPOSITIONS.balanced.jobs do
		local m = Stages.member(master, jobId, slot, gear, nil)
		local sa = Stages.baseStats(master, jobId, a.k, a.level)
		local sb = Stages.baseStats(master, jobId, b.k, b.level)
		for s, v in sa do
			m.baseStats[s] = (v + sb[s]) // 2
		end
		table.insert(out, Formulas.memberSnapshot(m, master))
	end
	return out
end

local function runMany(master: any, dungeonId: string, snaps: { any }, n: number, seed: number): (number, number)
	local clears, times = 0, {}
	for i = 1, n do
		local log = Expedition.simulate({
			seed = Rng.derive(seed, i),
			departAt = 0,
			dungeonId = dungeonId,
			members = snaps,
		}, master)
		if log.result == "clear" then
			clears += 1
		end
		table.insert(times, log.totalSeconds)
	end
	table.sort(times)
	return clears / n, times[math.ceil(n / 2)]
end

-- names の指標を計算する。値はダンジョンID → 数
function SimMetrics.compute(master: any, names: { string }, runs: number, seed: number): { [string]: any }
	local want = {}
	for _, n in names do
		want[n] = true
	end
	local list = master.dungeonList
	local out: { [string]: any } = {}
	for _, n in names do
		out[n] = {}
	end
	for i, dg in list do
		if Stages.list[i] == nil then
			continue
		end
		local snaps = snapsFor(master, i)
		if want.stageClearRate or want.stageMedianSeconds then
			local clear, median = runMany(master, dg.id, snaps, runs, seed)
			if want.stageClearRate then
				out.stageClearRate[dg.id] = clear
			end
			if want.stageMedianSeconds then
				out.stageMedianSeconds[dg.id] = median
			end
		end
		local nextDg = list[i + 1]
		if want.earlyUnlockClearRate and nextDg and Stages.list[i + 1] then
			local clear = runMany(master, nextDg.id, midSnapsFor(master, i), runs, seed + 1)
			out.earlyUnlockClearRate[nextDg.id] = clear
		end
	end
	for _, n in names do
		assert(
			n == "stageClearRate" or n == "stageMedianSeconds" or n == "earlyUnlockClearRate",
			`未知の指標（sim）: {n}。tools/balance/SimMetrics.luau に計算を足す`
		)
	end
	return out
end

return SimMetrics
