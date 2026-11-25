--!strict
-- 雇用・面接（ゲーム仕様書02章 §3、Q-006 仮採用、D-046、D-050〜D-055）
-- 候補の抽選・ステータスの抽選・冒険者の作成。コマンドの検証は Game が行う。

local Appearance = require("./Appearance")
local ExclusiveGift = require("./ExclusiveGift")
local Rng = require("./Rng")
local Types = require("./Types")
local Visitor = require("./Visitor")

local Hiring = {}

local function weightOf(e: any): number
	return e.weight
end

local function hireWeightOf(j: any): number
	return j.hireWeight
end

-- 候補1人を抽選する
-- 乱数の消費順：今週の訪問者の判定 → 特別な訪問者の判定（Visitor.roll：D-170）→（一般）職業 → 見た目 → 名前 → ギフト
local function rollCandidate(
	state: any,
	rng: Rng.Rng,
	master: any,
	now: number,
	takenUniques: { [string]: boolean },
	takenNames: { [string]: boolean }
): any
	local u = Visitor.roll(state, rng, master, now, takenUniques)
	if u then
		return {
			kind = "unique",
			uniqueId = u.id,
			name = u.name,
			gender = u.gender,
			appearanceId = u.appearanceId,
			jobId = u.jobId,
			giftIds = ExclusiveGift.uniqueGiftIds(u), -- 専用ギフトを含む（D-165）
		}
	end
	local job = rng:pickWeighted(master.raw.Jobs, hireWeightOf)
	local look = Appearance.roll(nil, job.outfitClass, rng, master)
	local name = Appearance.rollName(look.gender, look.looks, rng, master, takenNames)
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

-- now は今週の訪問者を決めるのに使う（D-158）
function Hiring.rollCandidates(state: any, rng: Rng.Rng, master: any, now: number): { any }
	local out = {}
	local taken = {}
	local takenNames = {} -- 同じ回の候補で名前を重ねない（D-260）
	for _ = 1, state.expansions.candidateSlots do
		local c = rollCandidate(state, rng, master, now, taken, takenNames)
		takenNames[c.name] = true
		table.insert(out, c)
	end
	return out
end

-- 面接のステータス抽選（Q-006）。範囲はギルドの成長に関係なく一定（D-081）。乱数の消費順は STAT_KEYS の順
function Hiring.rollStats(rng: Rng.Rng, master: any): Types.StatBlock
	local K = master.K
	local out: any = {}
	for _, s in Types.STAT_KEYS do
		local r = K.hireStatRange[s]
		out[s] = rng:int(r.min, r.max)
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
-- ユニークなら専用ギフトを必ず持たせる（雇用・初回踏破・受け取り箱のどれで加入しても：D-165）
function Hiring.newAdventurer(uid: string, candidate: any, stats: Types.StatBlock, now: number, master: any): any
	local adv = {
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
	ExclusiveGift.grant(adv, master)
	return adv
end

return Hiring
