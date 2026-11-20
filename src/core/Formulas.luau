--!strict
-- 計算式（docs/system/06_formulas.md）
-- 他のモジュールは式をここから使う。数値は master.K（Constants）から取る。

local Types = require("./Types")

local Formulas = {}

-- 探索に持ち込むメンバーの実効値（07章 §1 MemberSnapshot）
export type MemberSnapshot = {
	uid: string,
	slot: number, -- 隊列 1〜4（D-035）
	jobId: string,
	attackType: string, -- physical / magic（D-037）
	heals: boolean,
	maxHp: number,
	atk: number, -- 攻撃力（D-047：ダンジョン補正なし）
	pdef: number,
	mdef: number,
	agi: number,
	dex: number,
	mag: number,
	tagAtkRates: { [string]: number }, -- 種族タグごとの攻撃力上昇率（退魔の才・退魔の）
	tagGiftIds: { [string]: { string } }, -- 種族タグに効くギフト（発動演出用）
	healRate: number, -- 回復量の上昇率（癒しの：D-060）
	lucky: boolean,
	trapDexMult: number, -- 罠師の勘
	travel: { { terrainTag: string, value: number, giftId: string } }, -- 道案内
	expRate: number, -- 大食らい＋装備の経験値補正（D-082。上限 expBonusCap）
	giftIds: { string },
}

-- 装備個体（03章 EquipmentItem のうち性能に関わる部分）
export type EquipmentInstance = {
	baseId: string,
	itemLevel: number, -- アイテムレベル＝入手したダンジョンの tier（D-069）
	rarity: number,
	grade: number,
	modifierId: string?,
	modifierValue: number?,
}

-- メンバーの定義（M2 では Adventurer から作る）
export type MemberDef = {
	uid: string,
	slot: number,
	jobId: string,
	baseStats: Types.StatBlock,
	giftIds: { string },
	equipment: { weapon: EquipmentInstance?, armor: EquipmentInstance?, sub: EquipmentInstance? },
}

-- 06章 §2：装備性能の倍率（Q-020 仮）
-- 性能 = 基本値 × レアリティ係数 × (1 + 0.1×グレード) × equipTierMult^(アイテムレベル−1)（Q-020, D-069）
function Formulas.equipMult(rarity: number, grade: number, itemLevel: number, K: any): number
	return K.equipRarityMult[rarity] * (1 + K.equipGradeCoef * grade) * K.equipTierMult ^ (itemLevel - 1)
end

-- D-082：装備の経験値補正 = expPct × レアリティ係数 × (1 + 0.1×グレード)。アイテムレベルでは伸びない
function Formulas.equipExpPct(inst: any, master: any): number
	local base = master.equipmentBases[inst.baseId]
	if not base or not base.expPct then
		return 0
	end
	local K = master.K
	return base.expPct * K.equipRarityMult[inst.rarity] * (1 + K.equipGradeCoef * inst.grade)
end

-- 06章 §1：実効ステータスと探索用の実効値を作る
function Formulas.memberSnapshot(def: MemberDef, master: any): MemberSnapshot
	local K = master.K
	local job = master.jobs[def.jobId]
	assert(job, `未知の職業: {def.jobId}`)

	local flat = { str = 0, mag = 0, agi = 0, dex = 0, hp = 0 }
	local rates = { str = 0, mag = 0, agi = 0, dex = 0, hp = 0 }
	local tagRates: { [string]: number } = {}
	local healRate = 0
	local weaponAtk, pdef, mdef = 0, 0, 0
	local equipExp = 0

	for _, slot in { "weapon", "armor", "sub" } do
		local inst = (def.equipment :: any)[slot]
		if inst then
			local base = master.equipmentBases[inst.baseId]
			assert(base, `未知の装備: {inst.baseId}`)
			local mult = Formulas.equipMult(inst.rarity, inst.grade, inst.itemLevel or 1, K)
			equipExp += Formulas.equipExpPct(inst, master)
			if slot == "weapon" then
				weaponAtk += math.floor((base.atk or 0) * mult)
			end
			pdef += math.floor((base.pdef or 0) * mult)
			mdef += math.floor((base.mdef or 0) * mult)
			if base.stats then
				for k, v in base.stats do
					flat[k] += math.floor(v * mult)
				end
			end
			if inst.modifierId then
				local mod = master.modifiers[inst.modifierId]
				assert(mod, `未知の修飾語: {inst.modifierId}`)
				local value = inst.modifierValue or 0
				local e = mod.effect
				if e.kind == "flatStat" then
					flat[e.stat] += value
				elseif e.kind == "atkVsTagPct" then
					tagRates[e.tag] = (tagRates[e.tag] or 0) + value
				elseif e.kind == "healPct" then
					healRate += value
				end
			end
		end
	end

	local lucky, trapDexMult, expRate = false, 1, 0
	local tagGiftIds: { [string]: { string } } = {}
	local travel = {}
	for _, giftId in def.giftIds do
		local gift = master.gifts[giftId]
		assert(gift, `未知のギフト: {giftId}`)
		local e = gift.effect
		if e.kind == "statPct" then
			rates[e.stat] += e.value
		elseif e.kind == "atkVsTagPct" then
			tagRates[e.tag] = (tagRates[e.tag] or 0) + e.value
			tagGiftIds[e.tag] = tagGiftIds[e.tag] or {}
			table.insert(tagGiftIds[e.tag], giftId)
		elseif e.kind == "lucky" then
			lucky = true
		elseif e.kind == "trapDexMult" then
			trapDexMult = math.max(trapDexMult, e.value)
		elseif e.kind == "travelMult" then
			table.insert(travel, { terrainTag = e.terrainTag, value = e.value, giftId = giftId })
		elseif e.kind == "expPct" then
			expRate += e.value
		end
	end

	expRate = math.min(expRate + equipExp, K.expBonusCap) -- D-082

	-- 個体補正は1性能あたり personalBonusCap まで（D-033）
	local cap = K.personalBonusCap
	for k, v in rates do
		rates[k] = math.min(v, cap)
	end
	for k, v in tagRates do
		tagRates[k] = math.min(v, cap)
	end
	healRate = math.min(healRate, cap)

	local eff = {}
	for _, k in Types.STAT_KEYS do
		eff[k] = math.floor((def.baseStats[k] + flat[k]) * (1 + rates[k]))
	end

	local attackStat = if job.attackType == "physical" then eff.str else eff.mag -- D-037
	return {
		uid = def.uid,
		slot = def.slot,
		jobId = def.jobId,
		attackType = job.attackType,
		heals = job.heals,
		maxHp = math.max(1, eff.hp),
		atk = attackStat + weaponAtk,
		pdef = pdef,
		mdef = mdef,
		agi = eff.agi,
		dex = eff.dex,
		mag = eff.mag,
		tagAtkRates = tagRates,
		tagGiftIds = tagGiftIds,
		healRate = healRate,
		lucky = lucky,
		trapDexMult = trapDexMult,
		travel = travel,
		expRate = expRate,
		giftIds = table.clone(def.giftIds),
	}
end

-- 06章 §3：戦闘
function Formulas.attackAgainst(snap: MemberSnapshot, raceTag: string): number
	return math.floor(snap.atk * (1 + (snap.tagAtkRates[raceTag] or 0)))
end

-- D-068：ダメージ = 攻撃力² ÷ (攻撃力 + 防御)。防御が攻撃力と同じなら半分。最低1
function Formulas.damage(atk: number, def: number, _K: any): number
	if atk <= 0 then
		return 1
	end
	return math.max(math.floor(atk * atk / (atk + math.max(def, 0))), 1)
end

function Formulas.critRate(dex: number, K: any): number
	return math.min(dex / (dex + K.critCoef), K.critCap) -- D-010
end

function Formulas.critDamage(dmg: number, K: any): number
	return math.floor(dmg * K.critMult)
end

-- n 番目の戦闘のモンスター（D-003）
function Formulas.monsterScale(battleIndex: number, K: any): number
	return 1 + K.monsterScalePerBattle * (battleIndex - 1)
end

function Formulas.monsterStats(dungeon: any, battleIndex: number, K: any)
	local s = Formulas.monsterScale(battleIndex, K)
	return {
		scale = s,
		hp = math.max(1, math.floor(dungeon.base.hp * s)),
		atk = math.floor(dungeon.base.atk * s),
		pdef = math.floor(dungeon.base.pdef * s),
		mdef = math.floor(dungeon.base.mdef * s),
		exp = math.floor(dungeon.battleReward.exp * s),
		gold = math.floor(dungeon.battleReward.gold * s),
	}
end

-- 06章 §4：支援系の回復量（D-034, D-060）
function Formulas.healAmount(snap: MemberSnapshot, K: any): number
	return math.floor(snap.mag * K.healCoef * (1 + snap.healRate))
end

-- 06章 §5：罠と泉（D-017, D-018）
function Formulas.trapEvadeRate(dexSum: number, trapLevel: number, K: any): number
	local denom = dexSum + trapLevel * K.trapK
	if denom <= 0 then
		return 0
	end
	return dexSum / denom
end

-- 罠のダメージ = 最大HP × 罠ダメージ率（ダンジョンごとに上書き可。D-067）
function Formulas.trapDamage(maxHp: number, dungeon: any, K: any): number
	return math.floor(maxHp * (dungeon.trapDamageRate or K.trapDamageRate))
end

function Formulas.fountainHeal(maxHp: number, K: any): number
	return math.floor(maxHp * K.fountainHealRate)
end

-- 06章 §5：宝箱ランク（D-015）
function Formulas.chestRank(minRank: number, offset: number): number
	return math.min(minRank + offset, 5)
end

-- 06章 §6：幸運（D-019, Q-004）
function Formulas.luckyChance(holders: number, K: any): number
	return math.min(holders * K.luckyChancePerHolder, K.luckyChanceCap)
end

-- 06章 §7：片道秒（D-021, Q-004）。道案内は最も効果の大きい1つだけ
function Formulas.travelSeconds(snaps: { MemberSnapshot }, dungeon: any, K: any): (number, string?)
	local n = #snaps
	local sumAgi = 0
	for _, s in snaps do
		sumAgi += s.agi
	end
	local avgAgi = if n > 0 then sumAgi / n else 0
	local mult, giftId = 1, nil
	local terrain = {}
	for _, t in dungeon.terrainTags do
		terrain[t] = true
	end
	for _, s in snaps do
		for _, tr in s.travel do
			if terrain[tr.terrainTag] and tr.value < mult then
				mult, giftId = tr.value, tr.giftId
			end
		end
	end
	-- D-069：基準俊敏より速ければ短く、遅ければ長く（上下限あり）
	local speed = if avgAgi > 0
		then math.clamp(dungeon.refAgi / avgAgi, K.travelSpeedMin, K.travelSpeedMax)
		else K.travelSpeedMax
	local seconds = dungeon.distance * K.travelSecondsPerDistance * speed * mult
	return math.ceil(seconds), giftId
end

-- 06章 §8：必要経験値（Lv → Lv+1）
-- D-071：転生回数ごとの倍率を掛ける
function Formulas.expToNext(level: number, K: any, rebirthCount: number?): number
	local mult = K.expCycleMult[math.min((rebirthCount or 0) + 1, #K.expCycleMult)]
	return math.floor(K.expBase * level ^ K.expExponent * mult)
end

-- D-072：転生スロットの加算分の上限と抽選（newRebirthCount は転生後の回数 1〜）
function Formulas.rebirthBonusMax(prevStat: number, K: any): number
	return math.floor(prevStat * K.rebirthBonusMaxRate)
end

function Formulas.rebirthBonusSkew(newRebirthCount: number, K: any): number
	return K.rebirthBonusSkewBase + K.rebirthBonusSkewPerRebirth * (newRebirthCount - 1)
end

function Formulas.rollRebirthBonus(prevStat: number, newRebirthCount: number, rng: any, K: any): number
	local max = Formulas.rebirthBonusMax(prevStat, K)
	return math.floor(max * rng:float() ^ Formulas.rebirthBonusSkew(newRebirthCount, K))
end

return Formulas
