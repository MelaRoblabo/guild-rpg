--!strict
-- 雇用・面接（ゲーム仕様書02章 §3、Q-006 仮採用、D-046、D-050〜D-055）
-- 候補の抽選・ステータスの抽選・冒険者の作成。コマンドの検証は Game が行う。

local Appearance = require("./Appearance")
local Rng = require("./Rng")
local Types = require("./Types")

local Hiring = {}

local function weightOf(e: any): number
	return e.weight
end

local function hireWeightOf(j: any): number
	return j.hireWeight
end

-- 所持していないユニークのうち「特別な訪問者」で出るもの
local function availableVisitors(state: any, master: any): { any }
	local owned = {}
	for _, a in state.adventurers do
		if a.uniqueId then
			owned[a.uniqueId] = true
		end
	end
	local out = {}
	for _, u in master.raw.Uniques do
		if u.acquire == "visitor" and not owned[u.id] then
			table.insert(out, u)
		end
	end
	return out
end

-- 候補1人を抽選する
-- 乱数の消費順：特別な訪問者の判定 →（一般）職業 → 見た目 → 名前 → ギフト
local function rollCandidate(state: any, rng: Rng.Rng, master: any, takenUniques: { [string]: boolean }): any
	local K = master.K
	local visitors = {}
	for _, u in availableVisitors(state, master) do
		if not takenUniques[u.id] then
			table.insert(visitors, u)
		end
	end
	if rng:chance(K.specialVisitorChance) and #visitors > 0 then
		local u = rng:pickWeighted(visitors, function(_x)
			return 1
		end)
		takenUniques[u.id] = true
		return {
			kind = "unique",
			uniqueId = u.id,
			name = u.name,
			gender = u.gender,
			appearanceId = u.appearanceId,
			jobId = u.jobId,
			giftIds = table.clone(u.giftIds),
		}
	end
	local job = rng:pickWeighted(master.raw.Jobs, hireWeightOf)
	local look = Appearance.roll(nil, job.outfitClass, rng, master)
	local name = Appearance.rollName(look.gender, look.looks, rng, master)
	local gift = rng:pickWeighted(master.giftList, weightOf)
	return {
		kind = "general",
		name = name,
		gender = look.gender,
		appearanceId = look.appearanceId,
		jobId = job.id,
		giftIds = { gift.id },
	}
end

function Hiring.rollCandidates(state: any, rng: Rng.Rng, master: any): { any }
	local out = {}
	local taken = {}
	for _ = 1, state.expansions.candidateSlots do
		table.insert(out, rollCandidate(state, rng, master, taken))
	end
	return out
end

-- 面接のステータス抽選（Q-006：ギルドレベルで上限が上がる）。乱数の消費順は STAT_KEYS の順
function Hiring.rollStats(guildLevel: number, rng: Rng.Rng, master: any): Types.StatBlock
	local K = master.K
	local out: any = {}
	for _, s in Types.STAT_KEYS do
		local r = K.hireStatRange[s]
		out[s] = rng:int(r.min, r.max + math.floor(r.maxPerGuildLevel * (guildLevel - 1)))
	end
	return out
end

-- 合計値：HP を除く4項目の合計（Q-006）。HP は別に表示する
function Hiring.total(stats: Types.StatBlock): number
	return stats.str + stats.mag + stats.agi + stats.dex
end

-- ユニークの固定ステータス
function Hiring.uniqueStats(uniqueId: string, master: any): Types.StatBlock
	return table.clone(master.uniques[uniqueId].baseStats)
end

-- 冒険者を作る（uid は呼び出し側で払い出す）
function Hiring.newAdventurer(uid: string, candidate: any, stats: Types.StatBlock, now: number, master: any): any
	return {
		uid = uid,
		uniqueId = candidate.uniqueId,
		name = candidate.name,
		appearanceId = candidate.appearanceId,
		gender = candidate.gender,
		jobId = candidate.jobId,
		level = 1,
		levelCap = master.K.levelCapInitial,
		exp = 0,
		rebirthCount = 0,
		baseStats = table.clone(stats),
		giftIds = table.clone(candidate.giftIds),
		equipment = {},
		locked = false,
		hiredAt = now,
	}
end

return Hiring
