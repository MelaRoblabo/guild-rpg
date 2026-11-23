--!strict
-- ダンジョンの数値を自動調整して src/data/Dungeons.luau を生成する（D-069）
-- 使い方: lune run tools/sim/calibrate [-- --runs 600]
--
-- 各ダンジョンについて、テンプレートの想定段階のパーティ（バランス編成）で
--   1. 罠レベル  ：罠回避率が trapEvade になる値
--   2. 強さ      ：踏破率が targetClear になるよう、ratios 全体の倍率を二分探索
--   3. 距離      ：所要秒（中央値）が timeTarget になる値
--   4. 経験値    ：次の段階に進む手前のレベルで、5回の探索で1レベル上がる値（転生の経験値ボーナス込み）
--   5. ゴールド  ：tier に応じた等比（経済は M5 で調整）
-- 宝箱の表・演出ライン（chestEffectMinRarity・rareChestEffectMinRarity）と報酬のゴールドの基準額（rewardGoldBase、D-198）は
-- テンプレートの値をそのまま写す。
-- を決める。

local fs = require("@lune/fs")
local process = require("@lune/process")

local Data = require("../../src/data")
local Expedition = require("../../src/core/Expedition")
local Formulas = require("../../src/core/Formulas")
local MasterData = require("../../src/core/MasterData")
local Rng = require("../../src/core/Rng")
local Stages = require("./Stages")
local Templates = require("./DungeonTemplates")

local RUNS = 600
for i, a in process.args do
	if a == "--runs" then
		RUNS = tonumber(process.args[i + 1]) or RUNS
	end
end

local DEFAULT_CLEAR = 0.60
local DEFAULT_TRAP_EVADE = 0.65
local RUNS_PER_LEVEL = 5
local GOLD_BASE, GOLD_GROWTH = 15, 1.45

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

-- テンプレートから仮のダンジョン行を作る
local rows = {}
for i, t in Templates do
	rows[i] = {
		id = t.id,
		name = t.name,
		tier = i,
		floors = t.floors,
		distance = 1,
		refAgi = 10,
		terrainTags = t.terrainTags,
		base = { hp = 10, atk = 1, pdef = 0, mdef = 0 },
		monsters = t.monsters,
		bosses = t.bosses,
		trapLevel = 1,
		trapDamageRate = t.trapDamageRate,
		chestRarityWeights = t.chestRarityWeights,
		chestEffectMinRarity = t.chestEffectMinRarity,
		rareChestEffectMinRarity = t.rareChestEffectMinRarity, -- D-171, D-185
		rewardGoldBase = t.rewardGoldBase, -- D-198
		battleReward = { exp = 100, gold = math.floor(GOLD_BASE * GOLD_GROWTH ^ (i - 1) + 0.5) },
		sellableItems = t.sellableItems,
		jobPotionTargets = t.jobPotionTargets,
		modifierPool = t.modifierPool,
		unlockAfterClear = if i > 1 then Templates[i - 1].id else nil,
	}
end

local data = cloneDeep(Data)
data.Dungeons = rows
local master = MasterData.load(data)
local K = master.K

local function snapsFor(stageIndex: number): { any }
	local out = {}
	for _, d in Stages.party(master, stageIndex, "balanced") do
		table.insert(out, Formulas.memberSnapshot(d, master))
	end
	return out
end

local function runMany(dungeonId: string, snaps: { any }, n: number)
	local clears, expPerMember, times = 0, 0, {}
	for r = 1, n do
		local log = Expedition.simulate({
			seed = Rng.derive(777, r),
			departAt = 0,
			dungeonId = dungeonId,
			members = snaps,
		}, master)
		if log.result == "clear" then
			clears += 1
		end
		local e = 0
		for _, v in log.rewards.exp do
			e += v
		end
		expPerMember += e / #snaps
		table.insert(times, log.totalSeconds)
	end
	table.sort(times)
	return clears / n, expPerMember / n, times[math.ceil(n / 2)]
end

local function avgAtk(snaps: { any }): number
	local s = 0
	for _, x in snaps do
		s += x.atk
	end
	return s / #snaps
end

local lines = {}
local EXP_PER_SEC_GROWTH = 1.08 -- D-097
-- ダンジョンの経験値の基準にする倍率（M6 時点の周回1の倍率で固定）
local EXP_REF_MULT = 1.31
local prevExpPerSec: number? = nil
for i, t in Templates do
	local row = master.dungeons[t.id]
	local snaps = snapsFor(t.stage)
	local stage = Stages.list[t.stage]

	-- 1. 罠レベル（D-017）
	local dexSum, agiSum = 0, 0
	for _, s in snaps do
		dexSum += s.dex * s.trapDexMult
		agiSum += s.agi
	end
	local e = t.trapEvade or DEFAULT_TRAP_EVADE
	row.trapLevel = math.max(1, math.floor(dexSum * (1 - e) / (e * K.trapK) + 0.5))
	row.refAgi = math.max(1, math.floor(agiSum / #snaps + 0.5))

	-- 2. 強さ：踏破率が目標になる倍率を対数二分探索
	local target = t.targetClear or DEFAULT_CLEAR
	local ref = avgAtk(snaps)
	local function apply(scale: number)
		row.base = {
			hp = math.max(1, math.floor(t.ratios.hp * ref * scale + 0.5)),
			atk = math.max(1, math.floor(t.ratios.atk * ref * scale + 0.5)),
			pdef = math.floor(t.ratios.pdef * ref * scale + 0.5),
			mdef = math.floor(t.ratios.mdef * ref * scale + 0.5),
		}
	end
	local lo, hi = math.log(0.05), math.log(20)
	for _ = 1, 22 do
		local mid = (lo + hi) / 2
		apply(math.exp(mid))
		local clear = runMany(t.id, snaps, RUNS)
		if clear > target then
			lo = mid
		else
			hi = mid
		end
	end
	apply(math.exp((lo + hi) / 2))

	-- 3. 距離（所要秒の中央値が目標になるよう）
	local clear, expPer, median = runMany(t.id, snaps, RUNS)
	local replay = median - 2 * math.ceil(row.distance * K.travelSecondsPerDistance)
	local oneWay = math.max(3, (t.timeTarget - replay) / 2)
	row.distance = math.floor(oneWay / K.travelSecondsPerDistance * 10 + 0.5) / 10

	-- 4. 経験値：次の段階に進むレベル（転生をまたぐ場合はレベル上限）の手前で、
	--    RUNS_PER_LEVEL 回の探索で1レベル上がる量（転生の経験値ボーナスを考慮）
	local nextStage = Stages.list[t.stage + 1]
	local cap = math.min(K.levelCapInitial + K.levelCapPerRebirth * stage.k, K.levelCapMax)
	local targetLevel = if nextStage and nextStage.k == stage.k then nextStage.level - 1 else cap - 1
	local bonus = 1 + K.rebirthExpBonusPerCount * stage.k
	-- 周回の倍率（expCycleMult）とは切り離す。倍率を調整するたびにダンジョンの経験値が動かないように（M6）
	local wantPerRun = math.floor(K.expBase * targetLevel ^ K.expExponent * EXP_REF_MULT) / RUNS_PER_LEVEL / bonus
	row.battleReward.exp = math.max(1, math.floor(100 * wantPerRun / math.max(expPer, 0.001) + 0.5))

	local _, _, median2 = runMany(t.id, snaps, RUNS)
	-- 5. 深いダンジョンほど1秒あたりの経験値が多い（D-097：浅い所を回り続けないように）
	--    前のダンジョンの EXP_PER_SEC_GROWTH 倍を下回るなら経験値を引き上げる
	local perSec = expPer * row.battleReward.exp / 100 / math.max(median2, 1)
	if prevExpPerSec and perSec < prevExpPerSec * EXP_PER_SEC_GROWTH then
		local want = prevExpPerSec * EXP_PER_SEC_GROWTH * median2
		row.battleReward.exp = math.max(1, math.ceil(100 * want / math.max(expPer, 0.001)))
		perSec = expPer * row.battleReward.exp / 100 / math.max(median2, 1)
	end
	prevExpPerSec = perSec
	print(
		string.format(
			"%-6s %-12s 段階%2d 踏破%5.1f%% 所要%4d秒 HP%7d 攻%6d 物防%6d 魔防%6d 罠Lv%4d 距離%5.1f 経験値%7d",
			tostring(i),
			t.name,
			t.stage,
			clear * 100,
			median2,
			row.base.hp,
			row.base.atk,
			row.base.pdef,
			row.base.mdef,
			row.trapLevel,
			row.distance,
			row.battleReward.exp
		)
	)
	table.insert(lines, row)
end

-- 生成 ------------------------------------------------------------------
local function numList(xs: { number }): string
	local q = {}
	for _, x in xs do
		table.insert(q, tostring(x))
	end
	return "{ " .. table.concat(q, ", ") .. " }"
end

local function list(xs: { string }): string
	local q = {}
	for _, x in xs do
		table.insert(q, `"{x}"`)
	end
	return "{ " .. table.concat(q, ", ") .. " }"
end

local function weighted(xs: { any }): string
	local q = {}
	for _, x in xs do
		table.insert(q, `\{ id = "{x.id}", weight = {x.weight} \}`)
	end
	return "{ " .. table.concat(q, ", ") .. " }"
end

local out = {
	"--!strict",
	"-- ダンジョン（ゲーム仕様書05章、D-068, D-069）",
	"-- ※このファイルは tools/sim/calibrate.luau が tools/sim/DungeonTemplates.luau から生成する。手で編集しない。",
	"-- tier: 難易度の段階（装備のアイテムレベルにもなる） / refAgi: 移動時間の基準俊敏（D-069）",
	"-- base: 1体目のモンスターの HP・攻撃力・物理防御・魔法防御（D-003）",
	"",
	"return {",
}
for _, r in lines do
	table.insert(out, "\t{")
	table.insert(out, `\t\tid = "{r.id}",`)
	table.insert(out, `\t\tname = "{r.name}",`)
	table.insert(out, `\t\ttier = {r.tier},`)
	table.insert(out, `\t\tfloors = {r.floors},`)
	table.insert(out, `\t\tdistance = {r.distance},`)
	table.insert(out, `\t\trefAgi = {r.refAgi},`)
	table.insert(out, `\t\tterrainTags = {list(r.terrainTags)},`)
	table.insert(
		out,
		`\t\tbase = \{ hp = {r.base.hp}, atk = {r.base.atk}, pdef = {r.base.pdef}, mdef = {r.base.mdef} \},`
	)
	table.insert(out, `\t\tmonsters = {weighted(r.monsters)},`)
	table.insert(out, `\t\tbosses = {weighted(r.bosses)},`)
	table.insert(out, `\t\ttrapLevel = {r.trapLevel},`)
	if r.trapDamageRate then
		table.insert(out, `\t\ttrapDamageRate = {r.trapDamageRate},`)
	end
	table.insert(out, `\t\tchestRarityWeights = {numList(r.chestRarityWeights)},`)
	table.insert(out, `\t\tchestEffectMinRarity = {r.chestEffectMinRarity},`)
	if r.rareChestEffectMinRarity then
		table.insert(out, `\t\trareChestEffectMinRarity = {r.rareChestEffectMinRarity},`)
	end
	table.insert(out, `\t\tbattleReward = \{ exp = {r.battleReward.exp}, gold = {r.battleReward.gold} \},`)
	table.insert(out, `\t\trewardGoldBase = {r.rewardGoldBase},`)
	table.insert(out, `\t\tsellableItems = {weighted(r.sellableItems)},`)
	table.insert(out, `\t\tjobPotionTargets = {list(r.jobPotionTargets)},`)
	table.insert(out, `\t\tmodifierPool = {list(r.modifierPool)},`)
	if r.unlockAfterClear then
		table.insert(out, `\t\tunlockAfterClear = "{r.unlockAfterClear}",`)
	end
	table.insert(out, "\t},")
end
table.insert(out, "}")
fs.writeFile("src/data/Dungeons.luau", table.concat(out, "\n") .. "\n")
print("\n生成: src/data/Dungeons.luau")
