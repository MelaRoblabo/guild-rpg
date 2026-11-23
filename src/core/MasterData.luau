--!strict
-- マスターデータの検証と読み込み（docs/system/04_master_data.md §2）
-- 1つでも error があれば load は失敗する（起動しない）。

local Types = require("./Types")

type Issue = Types.ValidationIssue

local MasterData = {}

local EPS = 1e-9

-- 検証の補助 -------------------------------------------------------------

local Checker = {}
Checker.__index = Checker

type Checker = typeof(setmetatable({} :: { issues: { Issue } }, Checker))

local function newChecker(): Checker
	return setmetatable({ issues = {} }, Checker)
end

function Checker.error(self: Checker, path: string, message: string)
	table.insert(self.issues, { level = "error", path = path, message = message })
end

function Checker.warn(self: Checker, path: string, message: string)
	table.insert(self.issues, { level = "warning", path = path, message = message })
end

function Checker.number(self: Checker, path: string, v: any, min: number?, max: number?): boolean
	if type(v) ~= "number" or v ~= v then
		self:error(path, "数値が必要")
		return false
	end
	if min ~= nil and v < min then
		self:error(path, `{min} 以上が必要（値: {v}）`)
		return false
	end
	if max ~= nil and v > max then
		self:error(path, `{max} 以下が必要（値: {v}）`)
		return false
	end
	return true
end

function Checker.integer(self: Checker, path: string, v: any, min: number?, max: number?): boolean
	if not self:number(path, v, min, max) then
		return false
	end
	if math.floor(v) ~= v then
		self:error(path, `整数が必要（値: {v}）`)
		return false
	end
	return true
end

function Checker.probability(self: Checker, path: string, v: any): boolean
	return self:number(path, v, 0, 1)
end

function Checker.array(self: Checker, path: string, v: any, length: number?): boolean
	if type(v) ~= "table" then
		self:error(path, "配列が必要")
		return false
	end
	local n = #v
	for k in v do
		if type(k) ~= "number" or k < 1 or k > n or math.floor(k) ~= k then
			self:error(
				path,
				"配列（1始まりの連番キー）が必要。確率・重みの表に辞書は使わない"
			)
			return false
		end
	end
	if length ~= nil and n ~= length then
		self:error(path, `要素数 {length} が必要（値: {n}）`)
		return false
	end
	return true
end

-- 重み表：各要素の weightKey が 0 以上、合計 > 0。sumToOne なら合計 1
function Checker.weights(self: Checker, path: string, v: any, weightKey: string?, sumToOne: boolean?): boolean
	if not self:array(path, v) then
		return false
	end
	if #v == 0 then
		self:error(path, "空の表")
		return false
	end
	local total = 0
	local ok = true
	for i, e in v do
		local w = if weightKey then (if type(e) == "table" then e[weightKey] else nil) else e
		if not self:number(`{path}[{i}]{if weightKey then "." .. weightKey else ""}`, w, 0) then
			ok = false
		else
			total += w
		end
	end
	if not ok then
		return false
	end
	if total <= 0 then
		self:error(path, "重みの合計が 0")
		return false
	end
	if sumToOne and math.abs(total - 1) > EPS then
		self:error(path, `確率の合計が 1 ではない（合計: {total}）`)
		return false
	end
	return true
end

-- id の重複がなく、接頭辞が正しい
function Checker.uniqueIds(self: Checker, path: string, rows: any, prefix: string?): { [string]: boolean }
	local seen: { [string]: boolean } = {}
	if not self:array(path, rows) then
		return seen
	end
	for i, row in rows do
		local id = if type(row) == "table" then row.id else nil
		if type(id) ~= "string" or id == "" then
			self:error(`{path}[{i}].id`, "文字列の id が必要")
		elseif seen[id] then
			self:error(`{path}[{i}].id`, `id が重複: {id}`)
		else
			if prefix and string.sub(id, 1, #prefix) ~= prefix then
				self:error(`{path}[{i}].id`, `id は "{prefix}" で始める（値: {id}）`)
			end
			seen[id] = true
		end
	end
	return seen
end

function Checker.ref(self: Checker, path: string, id: any, known: { [string]: boolean })
	if type(id) ~= "string" or not known[id] then
		self:error(path, `存在しない id を参照: {tostring(id)}`)
	end
end

function Checker.range(self: Checker, path: string, v: any): boolean
	if type(v) ~= "table" then
		self:error(path, "{ min, max } が必要")
		return false
	end
	local ok = self:number(path .. ".min", v.min) and self:number(path .. ".max", v.max)
	if ok and v.min > v.max then
		self:error(path, `min > max（{v.min} > {v.max}）`)
		return false
	end
	return ok
end

-- 各データの検証 ----------------------------------------------------------

-- 紹介の進み具合の条件の種類（D-192, D-195。Friend.referralProgressReached が判定する）
local REFERRAL_PROGRESS_KINDS = { rebirthsTotal = true }

local function validateConstants(c: Checker, k: any, nRarity: number)
	local p = "Constants"
	if type(k) ~= "table" then
		c:error(p, "テーブルが必要")
		return
	end

	-- 戦闘
	if c:array(p .. ".hitWeights", k.hitWeights, 4) then
		c:weights(p .. ".hitWeights", k.hitWeights, nil, true)
	end
	c:number(p .. ".critCoef", k.critCoef, 0)
	c:probability(p .. ".critCap", k.critCap)
	c:number(p .. ".critMult", k.critMult, 1)
	c:integer(p .. ".maxTurns", k.maxTurns, 1)
	c:number(p .. ".monsterScalePerBattle", k.monsterScalePerBattle, 0)

	-- イベント
	c:weights(p .. ".eventWeights", k.eventWeights, "weight", true)
	c:probability(p .. ".fountainHealRate", k.fountainHealRate)
	c:integer(p .. ".chestBatchOpen", k.chestBatchOpen, 1) -- D-089
	if c:range(p .. ".chestEffectRate", k.chestEffectRate) then -- D-090
		c:probability(p .. ".chestEffectRate.min", k.chestEffectRate.min)
		c:probability(p .. ".chestEffectRate.max", k.chestEffectRate.max)
	end
	c:number(p .. ".trapK", k.trapK, 0)
	c:probability(p .. ".trapDamageRate", k.trapDamageRate)

	-- 支援・幸運
	c:probability(p .. ".healThreshold", k.healThreshold)
	c:number(p .. ".healCoef", k.healCoef, 0)
	c:probability(p .. ".luckyChancePerHolder", k.luckyChancePerHolder)
	c:probability(p .. ".luckyChanceCap", k.luckyChanceCap)

	-- 移動・再生
	c:number(p .. ".travelSecondsPerDistance", k.travelSecondsPerDistance, 0)
	c:number(p .. ".travelSpeedMin", k.travelSpeedMin, 0)
	c:number(p .. ".travelSpeedMax", k.travelSpeedMax, 0)
	c:number(p .. ".replaySecondsPerTurn", k.replaySecondsPerTurn, 0)
	c:number(p .. ".replaySecondsPerEvent", k.replaySecondsPerEvent, 0)

	c:number(p .. ".personalBonusCap", k.personalBonusCap, 0)

	-- 成長
	c:integer(p .. ".growthVariance", k.growthVariance, 0)
	c:number(p .. ".expBase", k.expBase, 1)
	c:number(p .. ".expExponent", k.expExponent, 0)
	if c:array(p .. ".expCycleMult", k.expCycleMult) then
		for i, v in k.expCycleMult do
			c:number(`{p}.expCycleMult[{i}]`, v, 0.0001)
		end
		if
			type(k.levelCapInitial) == "number"
			and type(k.levelCapPerRebirth) == "number"
			and type(k.levelCapMax) == "number"
			and k.levelCapPerRebirth > 0
		then
			local cycles = math.ceil((k.levelCapMax - k.levelCapInitial) / k.levelCapPerRebirth) + 1
			if #k.expCycleMult < cycles then
				c:error(p .. ".expCycleMult", `転生の周回数（{cycles}）分の倍率が必要`)
			end
		end
	end
	c:integer(p .. ".levelCapInitial", k.levelCapInitial, 1)
	c:integer(p .. ".levelCapPerRebirth", k.levelCapPerRebirth, 0)
	c:integer(p .. ".levelCapMax", k.levelCapMax, 1)
	if
		type(k.levelCapInitial) == "number"
		and type(k.levelCapMax) == "number"
		and k.levelCapInitial > k.levelCapMax
	then
		c:error(p .. ".levelCapInitial", "levelCapMax 以下が必要")
	end
	c:number(p .. ".rebirthExpBonusPerCount", k.rebirthExpBonusPerCount, 0)

	-- 転生
	c:integer(p .. ".giftMax", k.giftMax, 1)
	if c:array(p .. ".rebirthGiftAddAt", k.rebirthGiftAddAt) then
		local prev = 0
		for i, v in k.rebirthGiftAddAt do
			if c:integer(`{p}.rebirthGiftAddAt[{i}]`, v, 1) and v <= prev then
				c:error(`{p}.rebirthGiftAddAt[{i}]`, "昇順が必要")
			end
			prev = if type(v) == "number" then v else prev
		end
		if type(k.giftMax) == "number" and 1 + #k.rebirthGiftAddAt > k.giftMax then
			c:error(p .. ".rebirthGiftAddAt", "初期1つ＋追加回数が giftMax を超える")
		end
	end
	c:probability(p .. ".rebirthBonusMaxRate", k.rebirthBonusMaxRate)
	c:number(p .. ".rebirthBonusSkewBase", k.rebirthBonusSkewBase, 0)
	c:number(p .. ".rebirthBonusSkewPerRebirth", k.rebirthBonusSkewPerRebirth, 0)
	c:integer(p .. ".rebirthFreeRerolls", k.rebirthFreeRerolls, 0)
	-- 転生費用（D-080）：転生できる回数ぶん必要
	if
		type(k.levelCapMax) == "number"
		and type(k.levelCapInitial) == "number"
		and type(k.levelCapPerRebirth) == "number"
	then
		local n = (k.levelCapMax - k.levelCapInitial) // k.levelCapPerRebirth
		if c:array(p .. ".rebirthCost", k.rebirthCost, n) then
			for i, v in k.rebirthCost do
				c:integer(`{p}.rebirthCost[{i}]`, v, 0)
			end
		end
	end
	c:number(p .. ".expBonusCap", k.expBonusCap, 0)

	-- トレーニング（D-076, D-077）
	c:number(p .. ".trainGoldCoef", k.trainGoldCoef, 0)
	c:number(p .. ".trainGoldExponent", k.trainGoldExponent, 0)
	if c:array(p .. ".trainingFacility", k.trainingFacility) then
		local prev = 0
		for i, f in k.trainingFacility do
			local q = `{p}.trainingFacility[{i}]`
			if c:integer(q .. ".levelCap", f.levelCap, 1) and f.levelCap <= prev then
				c:error(q .. ".levelCap", "昇順が必要")
			end
			prev = if type(f.levelCap) == "number" then f.levelCap else prev
			c:integer(q .. ".expPerSession", f.expPerSession, 1)
		end
	end

	-- 雇用
	c:integer(p .. ".hireCost", k.hireCost, 0)
	for _, s in Types.STAT_KEYS do
		local r = if type(k.hireStatRange) == "table" then k.hireStatRange[s] else nil
		c:range(`{p}.hireStatRange.{s}`, r) -- D-081：ギルドレベルでは変わらない
	end
	c:integer(p .. ".hireFreeRerolls", k.hireFreeRerolls, 0)
	c:probability(p .. ".specialVisitorChance", k.specialVisitorChance)
	c:probability(p .. ".weeklyVisitorChance", k.weeklyVisitorChance) -- D-158, D-170

	-- フレンドボタン・紹介（D-157）
	c:integer(p .. ".friendRewardIntervalSeconds", k.friendRewardIntervalSeconds, 1)
	c:integer(p .. ".friendRewardMaxFriends", k.friendRewardMaxFriends, 1)
	c:number(p .. ".friendRewardGoldMult", k.friendRewardGoldMult, 0) -- D-190
	c:number(p .. ".friendRewardBonusPerFriend", k.friendRewardBonusPerFriend, 0)
	c:integer(p .. ".friendRewardDailyCap", k.friendRewardDailyCap, 1)
	c:integer(p .. ".referralWeeklyCap", k.referralWeeklyCap, 1)
	-- 招待された人の進み具合の条件（D-192）
	local rpc = k.referralProgressCondition
	if type(rpc) ~= "table" then
		c:error(p .. ".referralProgressCondition", "テーブルが必要")
	else
		if not REFERRAL_PROGRESS_KINDS[rpc.kind] then
			c:error(p .. ".referralProgressCondition.kind", `知らない条件: {tostring(rpc.kind)}`)
		end
		c:integer(p .. ".referralProgressCondition.count", rpc.count, 1)
	end
	-- ゲーム外の通知（D-196）
	c:integer(p .. ".notifyLoginHistoryCount", k.notifyLoginHistoryCount, 1)

	-- 見た目
	c:weights(p .. ".appearanceGenderWeights", k.appearanceGenderWeights, "weight", true)
	c:weights(p .. ".appearanceLooksWeights", k.appearanceLooksWeights, "weight", true)

	-- 宝箱の中身・売却
	if c:weights(p .. ".gradeWeights", k.gradeWeights, "weight", true) then
		for i, e in k.gradeWeights do
			c:integer(`{p}.gradeWeights[{i}].grade`, e.grade, 0, 3)
		end
	end
	c:probability(p .. ".modifierChance", k.modifierChance)
	c:probability(p .. ".potionChanceRarePlus", k.potionChanceRarePlus)
	c:weights(p .. ".potionKindWeights", k.potionKindWeights, "weight", true)
	c:weights(p .. ".itemEventWeights", k.itemEventWeights, "weight", true)
	for _, key in { "sellRarityMult", "equipRarityMult" } do
		if c:array(`{p}.{key}`, k[key], nRarity) then -- レアリティの数だけ（D-085）
			for i, v in k[key] do
				c:number(`{p}.{key}[{i}]`, v, 0)
			end
		end
	end
	c:number(p .. ".sellGradeCoef", k.sellGradeCoef, 0)
	c:number(p .. ".equipGradeCoef", k.equipGradeCoef, 0)
	c:number(p .. ".equipTierMult", k.equipTierMult, 1)

	-- 留守番・休息ボーナス（D-161）
	c:number(p .. ".offlineTimeMult", k.offlineTimeMult, 1)
	c:integer(p .. ".offlineMaxSeconds", k.offlineMaxSeconds, 1)
	c:number(p .. ".restBonusRate", k.restBonusRate, 0)
	c:integer(p .. ".restBonusMaxSeconds", k.restBonusMaxSeconds, 0)
	c:number(p .. ".restBonusExpMult", k.restBonusExpMult, 1)

	-- 日替わりの特性（D-156）
	if c:array(p .. ".dailyTraitBands", k.dailyTraitBands) then
		for i, b in k.dailyTraitBands do
			local q = `{p}.dailyTraitBands[{i}]`
			if c:range(q, b) then
				c:integer(q .. ".min", b.min, 1)
				c:integer(q .. ".max", b.max, 1)
			end
		end
	end
	c:integer(p .. ".calendarSeed", k.calendarSeed)

	-- 特別な宝箱・クエスト・プレイ時間（D-153, D-154, D-171）
	if c:range(p .. ".rareDungeonEffectRate", k.rareDungeonEffectRate) then
		c:probability(p .. ".rareDungeonEffectRate.min", k.rareDungeonEffectRate.min)
		c:probability(p .. ".rareDungeonEffectRate.max", k.rareDungeonEffectRate.max)
	end
	-- マップイベント・レアダンジョン・レイド・旅の商人（D-152, D-179）
	c:integer(p .. ".mapEventIntervalSeconds", k.mapEventIntervalSeconds, 1)
	c:integer(p .. ".mapEventNoticeSeconds", k.mapEventNoticeSeconds, 0)
	c:integer(p .. ".mapEventWindowSeconds", k.mapEventWindowSeconds, 1)
	c:weights(p .. ".mapEventKindWeights", k.mapEventKindWeights, "weight")
	c:number(p .. ".rareDungeonChestMult", k.rareDungeonChestMult, 1)
	c:number(p .. ".raidHpMult", k.raidHpMult, 0)
	if c:range(p .. ".raidHpSpread", k.raidHpSpread) then
		c:number(p .. ".raidHpSpread.min", k.raidHpSpread.min, 0)
	end
	c:number(p .. ".raidDamagePerAtk", k.raidDamagePerAtk, 0)
	c:integer(p .. ".raidTravelSeconds", k.raidTravelSeconds, 0)
	if
		type(k.mapEventWindowSeconds) == "number"
		and type(k.mapEventIntervalSeconds) == "number"
		and type(k.mapEventNoticeSeconds) == "number"
		and type(k.raidTravelSeconds) == "number"
	then
		if k.mapEventWindowSeconds + k.mapEventNoticeSeconds > k.mapEventIntervalSeconds then
			c:error(p .. ".mapEventWindowSeconds", "出ている3分間と予告が次の時間帯に重なる")
		end
		-- レイドのダメージが次の時間帯までに入り終わるように（レイドの状態は今の時間帯の分だけ持つ：03章）
		if k.mapEventWindowSeconds + k.raidTravelSeconds > k.mapEventIntervalSeconds then
			c:error(
				p .. ".raidTravelSeconds",
				"最後に出発したパーティの到着が次の時間帯に重なる"
			)
		end
	end
	if c:range(p .. ".merchantItemCount", k.merchantItemCount) then
		c:integer(p .. ".merchantItemCount.min", k.merchantItemCount.min, 1)
		c:integer(p .. ".merchantItemCount.max", k.merchantItemCount.max, 1)
	end
	c:number(p .. ".merchantPriceMult", k.merchantPriceMult, 0)
	c:number(p .. ".merchantGradeCoef", k.merchantGradeCoef, 0)
	c:number(p .. ".merchantModifierCoef", k.merchantModifierCoef, 0)

	c:integer(p .. ".questDailyCount", k.questDailyCount, 1)
	c:integer(p .. ".questWeeklyCount", k.questWeeklyCount, 1)
	c:integer(p .. ".playtimeDailyCapSeconds", k.playtimeDailyCapSeconds, 1)

	-- ギルド
	c:integer(p .. ".guildExpPerFloor", k.guildExpPerFloor, 0)
	c:integer(p .. ".guildExpClearBonus", k.guildExpClearBonus, 0)
	c:integer(p .. ".guildExpFirstClear", k.guildExpFirstClear, 0)
end

local STAT_SET = { str = true, mag = true, agi = true, dex = true, hp = true }
local SLOTS = { weapon = true, armor = true, sub = true }
local ATTACK_TYPES = { physical = true, magic = true }
local JOB_LINES = { warrior = true, scout = true, mage = true, support = true }
-- 専用ギフトのパーティ全体の効果の種類（D-174。決定の例の範囲：移動が少し速い・宝箱が少し増える）
local PARTY_EFFECT_KINDS = { travelMult = true, chestMult = true }

local function idSet(rows: any): { [string]: boolean }
	local s = {}
	if type(rows) == "table" then
		for _, r in rows do
			if type(r) == "table" and type(r.id) == "string" then
				s[r.id] = true
			end
		end
	end
	return s
end

-- 専用ギフト（exclusive = true）の id の集合（D-165）
local function exclusiveGiftSet(d: any): { [string]: boolean }
	local s = {}
	if type(d.Gifts) == "table" then
		for _, g in d.Gifts do
			if type(g) == "table" and type(g.id) == "string" and g.exclusive == true then
				s[g.id] = true
			end
		end
	end
	return s
end

local function oneOf(c: Checker, path: string, v: any, set: { [string]: boolean })
	if type(v) ~= "string" or not set[v] then
		c:error(path, `許可されていない値: {tostring(v)}`)
	end
end

local function weightedRefs(c: Checker, path: string, list: any, known: { [string]: boolean })
	if c:weights(path, list, "weight") then
		for i, e in list do
			c:ref(`{path}[{i}].id`, e.id, known)
		end
	end
end

local function rarityCount(d: any): number
	return if type(d.Rarities) == "table" then #d.Rarities else 0
end

-- 演出が入る割合（minRarity 以上が出る割合）が lo〜hi に収まるか（D-090, D-166, D-171）
local function checkEffectRate(c: Checker, path: string, weights: any, minRarity: number, lo: number, hi: number)
	local sum, tail = 0, 0
	for r, w in weights do
		if type(w) == "number" then
			sum += w
			if r >= minRarity then
				tail += w
			end
		end
	end
	if sum <= 0 then
		return
	end
	local rate = tail / sum
	if rate < lo - 1e-9 or rate > hi + 1e-9 then
		c:error(
			path,
			string.format("演出が入る割合 %.1f%% が基準 %.0f〜%.0f%% の外", rate * 100, lo * 100, hi * 100)
		)
	end
end

local function validateContent(c: Checker, d: any)
	-- レアリティ
	c:uniqueIds("Rarities", d.Rarities, "rar_")
	if c:array("Rarities", d.Rarities) then
		for i, r in d.Rarities do
			if r.rank ~= i then
				c:error(`Rarities[{i}].rank`, "rank は 1 からの連番")
			end
		end
	end

	-- 職業
	c:uniqueIds("Jobs", d.Jobs, "job_")
	if type(d.Jobs) == "table" then
		for i, j in d.Jobs do
			local p = `Jobs[{i}]`
			oneOf(c, p .. ".line", j.line, JOB_LINES)
			oneOf(c, p .. ".attackType", j.attackType, ATTACK_TYPES)
			oneOf(c, p .. ".outfitClass", j.outfitClass, { phy = true, mag = true })
			for _, s in Types.STAT_KEYS do
				c:integer(`{p}.growth.{s}`, if type(j.growth) == "table" then j.growth[s] else nil, 0)
			end
			c:array(p .. ".equipKinds", j.equipKinds)
		end
	end

	-- ギフト
	local giftKinds =
		{ statPct = true, lucky = true, atkVsTagPct = true, travelMult = true, trapDexMult = true, expPct = true }
	c:uniqueIds("Gifts", d.Gifts, "gift_")
	if type(d.Gifts) == "table" then
		local general = 0
		for i, g in d.Gifts do
			local p = `Gifts[{i}]`
			-- 専用ギフト（D-165）：一般の抽選に出さないので weight は要らない
			if g.exclusive ~= nil and type(g.exclusive) ~= "boolean" then
				c:error(p .. ".exclusive", "真偽値が必要")
			end
			local exclusive = g.exclusive == true
			if exclusive then
				if g.weight ~= nil then
					c:number(p .. ".weight", g.weight, 0)
				end
			else
				general += 1
				c:number(p .. ".weight", g.weight, 0)
			end
			-- パーティ全体の効果は専用ギフトだけ（D-174）
			local pe = g.partyEffect
			if pe ~= nil then
				if not exclusive then
					c:error(
						p .. ".partyEffect",
						"partyEffect は専用ギフト（exclusive = true）だけが持てる（D-174）"
					)
				elseif type(pe) ~= "table" then
					c:error(p .. ".partyEffect", "テーブルが必要")
				else
					oneOf(c, p .. ".partyEffect.kind", pe.kind, PARTY_EFFECT_KINDS)
					if pe.kind == "travelMult" then
						if c:number(p .. ".partyEffect.value", pe.value, 0, 1) and pe.value <= 0 then
							c:error(p .. ".partyEffect.value", "0 より大きい値が必要")
						end
					elseif pe.kind == "chestMult" then
						c:number(p .. ".partyEffect.value", pe.value, 1)
					end
				end
			end
			local e = g.effect
			-- 専用ギフトはパーティ全体の効果だけでもよい（effect を省ける）
			local effectOptional = exclusive and pe ~= nil
			if type(e) ~= "table" then
				if not (e == nil and effectOptional) then
					c:error(p .. ".effect", "effect が必要")
				end
			else
				oneOf(c, p .. ".effect.kind", e.kind, giftKinds)
				if e.kind == "statPct" then
					oneOf(c, p .. ".effect.stat", e.stat, STAT_SET)
				end
				if e.kind ~= "lucky" then
					c:number(p .. ".effect.value", e.value, 0)
				end
			end
		end
		if general == 0 then
			c:error("Gifts", "一般の抽選に出るギフト（exclusive でないもの）が1つ以上必要")
		end
	end

	-- 修飾語
	c:uniqueIds("Modifiers", d.Modifiers, "mod_")
	if type(d.Modifiers) == "table" then
		for i, m in d.Modifiers do
			local p = `Modifiers[{i}]`
			if type(m.effect) ~= "table" then
				c:error(p .. ".effect", "effect が必要")
			else
				oneOf(c, p .. ".effect.kind", m.effect.kind, { flatStat = true, atkVsTagPct = true, healPct = true })
				if m.effect.kind == "flatStat" then
					oneOf(c, p .. ".effect.stat", m.effect.stat, STAT_SET)
				end
			end
			c:range(p .. ".range", m.range)
		end
	end

	-- 基本アイテム
	local equipIds = c:uniqueIds("EquipmentBases", d.EquipmentBases, "eq_")
	local _ = equipIds
	if type(d.EquipmentBases) == "table" then
		for i, e in d.EquipmentBases do
			local p = `EquipmentBases[{i}]`
			oneOf(c, p .. ".slot", e.slot, SLOTS)
			c:integer(p .. ".minRarity", e.minRarity, 1, rarityCount(d))
			c:integer(p .. ".sellPrice", e.sellPrice, 0)
			for _, key in { "atk", "pdef", "mdef" } do
				if e[key] ~= nil then
					c:number(`{p}.{key}`, e[key], 0)
				end
			end
			if e.expPct ~= nil then
				c:number(p .. ".expPct", e.expPct, 0) -- D-082
			end
			if e.stats ~= nil then
				for k, v in e.stats do
					oneOf(c, `{p}.stats`, k, STAT_SET)
					c:number(`{p}.stats.{k}`, v)
				end
			end
		end
	end

	-- アイテム
	local jobIds = idSet(d.Jobs)
	local itemIds = c:uniqueIds("Items", d.Items, "itm_")
	if type(d.Items) == "table" then
		for i, it in d.Items do
			local p = `Items[{i}]`
			oneOf(c, p .. ".kind", it.kind, {
				ticket = true,
				potion_appearance_change = true,
				potion_appearance_keep = true,
				potion_job = true,
				sellable = true,
			})
			if it.kind == "potion_job" then
				c:ref(p .. ".jobId", it.jobId, jobIds)
			end
			c:integer(p .. ".sellPrice", it.sellPrice, 0)
		end
	end

	-- モンスター
	local monsterIds = c:uniqueIds("Monsters", d.Monsters, "mon_")
	if type(d.Monsters) == "table" then
		for i, m in d.Monsters do
			oneOf(c, `Monsters[{i}].attackType`, m.attackType, ATTACK_TYPES)
			if type(m.raceTag) ~= "string" then
				c:error(`Monsters[{i}].raceTag`, "文字列が必要")
			end
		end
	end

	-- ダンジョン
	local dungeonIds = c:uniqueIds("Dungeons", d.Dungeons, "dng_")
	local modIds = idSet(d.Modifiers)
	if type(d.Dungeons) == "table" then
		for i, g in d.Dungeons do
			local p = `Dungeons[{i}]`
			if c:integer(p .. ".floors", g.floors, 1) and g.floors % 2 == 0 then
				c:error(p .. ".floors", "フロア数は奇数（最終フロアはボス戦：D-001）")
			end
			c:number(p .. ".distance", g.distance, 0)
			c:array(p .. ".terrainTags", g.terrainTags)
			for _, key in { "hp", "atk", "pdef", "mdef" } do
				c:number(
					`{p}.base.{key}`,
					if type(g.base) == "table" then g.base[key] else nil,
					if key == "hp" then 1 else 0
				)
			end
			weightedRefs(c, p .. ".monsters", g.monsters, monsterIds)
			weightedRefs(c, p .. ".bosses", g.bosses, monsterIds)
			c:integer(p .. ".trapLevel", g.trapLevel, 1)
			if g.trapDamageRate ~= nil then
				c:probability(p .. ".trapDamageRate", g.trapDamageRate)
			end
			c:number(p .. ".refAgi", g.refAgi, 1)
			c:integer(p .. ".tier", g.tier, 1)
			c:integer(p .. ".chestEffectMinRarity", g.chestEffectMinRarity, 1, rarityCount(d)) -- D-089
			-- 宝箱のレアリティの出現率（D-085）。長さはレアリティの数以下（足りない上位は0）、合計は正
			if c:array(p .. ".chestRarityWeights", g.chestRarityWeights) then
				if #g.chestRarityWeights > rarityCount(d) then
					c:error(p .. ".chestRarityWeights", `レアリティの数（{rarityCount(d)}）以下が必要`)
				end
				local sum = 0
				for r, w in g.chestRarityWeights do
					if c:number(`{p}.chestRarityWeights[{r}]`, w, 0) then
						sum += w
					end
				end
				if sum <= 0 then
					c:error(p .. ".chestRarityWeights", "合計が0より大きいことが必要")
				elseif
					type(g.chestEffectMinRarity) == "number"
					and type(d.Constants) == "table"
					and type(d.Constants.chestEffectRate) == "table"
				then
					-- 開封演出が入る割合を基準の範囲に収める（D-090）
					local tail = 0
					for r, w in g.chestRarityWeights do
						if r >= g.chestEffectMinRarity and type(w) == "number" then
							tail += w
						end
					end
					local rate = tail / sum
					local band = d.Constants.chestEffectRate
					if rate < band.min - 1e-9 or rate > band.max + 1e-9 then
						c:error(
							p .. ".chestEffectMinRarity",
							string.format(
								"演出が入る割合 %.1f%% が基準 %.0f〜%.0f%% の外",
								rate * 100,
								band.min * 100,
								band.max * 100
							)
						)
					end
				end
			end
			-- レアダンジョンの山の演出ライン（D-171, D-185）。全ダンジョン必須（D-188 で表を作り直し、
			-- 普通の演出率 10〜15% とレアダンジョン用の 20〜30% の両方の線が引けるようにした）。その割合を rareDungeonEffectRate に収める
			do
				local q = p .. ".rareChestEffectMinRarity"
				if
					c:integer(q, g.rareChestEffectMinRarity, 1, rarityCount(d))
					and type(g.chestRarityWeights) == "table"
					and type(d.Constants) == "table"
					and type(d.Constants.rareDungeonEffectRate) == "table"
				then
					checkEffectRate(
						c,
						q,
						g.chestRarityWeights,
						g.rareChestEffectMinRarity,
						d.Constants.rareDungeonEffectRate.min,
						d.Constants.rareDungeonEffectRate.max
					)
				end
			end
			-- 報酬のゴールドの基準額（D-190, D-198）：ダンジョンごとに1つ（ひな形から calibrate が写す）
			c:integer(p .. ".rewardGoldBase", g.rewardGoldBase, 0)
			if g.dispatchFee ~= nil then
				c:error(p .. ".dispatchFee", "派遣費は廃止（D-163）")
			end
			c:integer(p .. ".battleReward.exp", if type(g.battleReward) == "table" then g.battleReward.exp else nil, 0)
			c:integer(
				p .. ".battleReward.gold",
				if type(g.battleReward) == "table" then g.battleReward.gold else nil,
				0
			)
			weightedRefs(c, p .. ".sellableItems", g.sellableItems, itemIds)
			if c:array(p .. ".jobPotionTargets", g.jobPotionTargets) then
				for k, j in g.jobPotionTargets do
					c:ref(`{p}.jobPotionTargets[{k}]`, j, jobIds)
				end
			end
			if c:array(p .. ".modifierPool", g.modifierPool) then
				for k, m in g.modifierPool do
					c:ref(`{p}.modifierPool[{k}]`, m, modIds)
				end
			end
			if g.unlockAfterClear ~= nil then
				c:ref(p .. ".unlockAfterClear", g.unlockAfterClear, dungeonIds)
			end
		end
	end
end

local function validateLootAndStarter(c: Checker, d: any)
	local L = if type(d.LootTables) == "table" then d.LootTables.chest else nil
	if type(L) ~= "table" then
		c:error("LootTables.chest", "テーブルが必要")
	else
		if c:weights("LootTables.chest.equipmentCountWeights", L.equipmentCountWeights, "weight", true) then
			for i, e in L.equipmentCountWeights do
				c:integer(`LootTables.chest.equipmentCountWeights[{i}].count`, e.count, 0)
			end
		end
		c:weights("LootTables.chest.extraWeights", L.extraWeights, "weight", true)
		c:number("LootTables.chest.goldMult", L.goldMult, 0)
		c:integer("LootTables.chest.potionMinRank", L.potionMinRank, 1, rarityCount(d))
	end

	local S = d.StarterSet
	if type(S) ~= "table" then
		c:error("StarterSet", "テーブルが必要")
		return
	end
	c:integer("StarterSet.gold", S.gold, 0)
	for _, key in { "partySlots", "candidateSlots", "rosterSize", "warehouseSize", "trainingLevel" } do
		c:integer(`StarterSet.expansions.{key}`, if type(S.expansions) == "table" then S.expansions[key] else nil, 1)
	end
	-- 自動売却の初期値（D-167）
	local A = S.autoSell
	if type(A) ~= "table" then
		c:error("StarterSet.autoSell", "テーブルが必要")
	else
		for _, key in { "enabled", "keepModified" } do
			if type(A[key]) ~= "boolean" then
				c:error(`StarterSet.autoSell.{key}`, "真偽値が必要")
			end
		end
		c:integer("StarterSet.autoSell.maxRarity", A.maxRarity, 1, rarityCount(d))
	end
	local jobIds, giftIds, equipIds = idSet(d.Jobs), idSet(d.Gifts), idSet(d.EquipmentBases)
	if c:array("StarterSet.adventurers", S.adventurers) then
		for i, a in S.adventurers do
			local p = `StarterSet.adventurers[{i}]`
			c:ref(p .. ".jobId", a.jobId, jobIds)
			for _, s in Types.STAT_KEYS do
				c:integer(`{p}.baseStats.{s}`, if type(a.baseStats) == "table" then a.baseStats[s] else nil, 0)
			end
			for k, g in a.giftIds or {} do
				c:ref(`{p}.giftIds[{k}]`, g, giftIds)
				if exclusiveGiftSet(d)[g] then
					c:error(`{p}.giftIds[{k}]`, `専用ギフトは一般の冒険者に付けない: {g}`)
				end
			end
			for slot, e in a.equipment or {} do
				c:ref(`{p}.equipment.{slot}`, e, equipIds)
			end
		end
	end
end

local function validateHiringData(c: Checker, d: any)
	-- 職業の雇用重み
	if type(d.Jobs) == "table" then
		local total = 0
		for i, j in d.Jobs do
			if c:number(`Jobs[{i}].hireWeight`, j.hireWeight, 0) then
				total += j.hireWeight
			end
		end
		if total <= 0 then
			c:error("Jobs", "hireWeight の合計が 0（雇用候補が作れない）")
		end
	end

	-- 見た目（D-042：16カテゴリ × 15種）
	local appearanceIds = c:uniqueIds("Appearances", d.Appearances, "chr_")
	local counts: { [string]: number } = {}
	if type(d.Appearances) == "table" then
		for i, a in d.Appearances do
			local p = `Appearances[{i}]`
			oneOf(c, p .. ".gender", a.gender, { m = true, f = true })
			oneOf(c, p .. ".looks", a.looks, { bea = true, nor = true, ugl = true, dem = true })
			oneOf(c, p .. ".outfitClass", a.outfitClass, { phy = true, mag = true })
			if a.looks == "dem" then
				oneOf(
					c,
					p .. ".race",
					a.race,
					{ elf = true, beastkin = true, dwarf = true, halforc = true, halfgoblin = true }
				)
			end
			local key = `{a.gender}_{a.looks}_{a.outfitClass}`
			counts[key] = (counts[key] or 0) + 1
		end
		for _, g in { "m", "f" } do
			for _, l in { "bea", "nor", "ugl", "dem" } do
				for _, o in { "phy", "mag" } do
					local n = counts[`{g}_{l}_{o}`] or 0
					if n < 2 then
						c:error(
							"Appearances",
							`カテゴリ {g}_{l}_{o} が {n} 種（直前と同じ見た目を除外するため2種以上必要）`
						)
					elseif n ~= 15 then
						c:warn("Appearances", `カテゴリ {g}_{l}_{o} が {n} 種（仕様は15種：D-042）`)
					end
				end
			end
		end
	end
	local _ = appearanceIds

	-- 名前（D-054）
	for _, key in { "m", "f", "dem" } do
		local list = if type(d.Names) == "table" then d.Names[key] else nil
		if c:array(`Names.{key}`, list) and #list == 0 then
			c:error(`Names.{key}`, "空のリスト")
		end
	end

	-- ユニーク（D-055）
	local jobIds, giftIds = idSet(d.Jobs), idSet(d.Gifts)
	c:uniqueIds("Uniques", d.Uniques, "uni_")
	local loginOrders: { [number]: boolean } = {}
	local exclusiveIds = exclusiveGiftSet(d)
	local exclusiveOwner: { [string]: string } = {}
	if type(d.Uniques) == "table" then
		for i, u in d.Uniques do
			local p = `Uniques[{i}]`
			c:ref(p .. ".jobId", u.jobId, jobIds)
			oneOf(c, p .. ".gender", u.gender, { m = true, f = true })
			for _, s in Types.STAT_KEYS do
				c:integer(`{p}.baseStats.{s}`, if type(u.baseStats) == "table" then u.baseStats[s] else nil, 0)
			end
			for k, g in u.giftIds or {} do
				c:ref(`{p}.giftIds[{k}]`, g, giftIds)
				if exclusiveIds[g] then
					c:error(`{p}.giftIds[{k}]`, `専用ギフトは exclusiveGiftId に書く: {g}`)
				end
			end
			-- 専用ギフト（D-165）：持ち主のユニークは1人だけ。ギフトの枠（giftMax）に数える
			if u.exclusiveGiftId ~= nil then
				c:ref(p .. ".exclusiveGiftId", u.exclusiveGiftId, giftIds)
				if giftIds[u.exclusiveGiftId] and not exclusiveIds[u.exclusiveGiftId] then
					c:error(p .. ".exclusiveGiftId", `exclusive = true のギフトが必要: {u.exclusiveGiftId}`)
				elseif exclusiveOwner[u.exclusiveGiftId] then
					c:error(
						p .. ".exclusiveGiftId",
						`専用ギフトを2人のユニークが参照: {u.exclusiveGiftId}（{exclusiveOwner[u.exclusiveGiftId]} と {tostring(
							u.id
						)}）`
					)
				else
					exclusiveOwner[u.exclusiveGiftId] = tostring(u.id)
				end
				local giftMax = if type(d.Constants) == "table" then d.Constants.giftMax else nil
				if type(giftMax) == "number" and #(u.giftIds or {}) + 1 > giftMax then
					c:error(
						p .. ".exclusiveGiftId",
						`giftIds と専用ギフトの合計が giftMax（{giftMax}）を超える`
					)
				end
			end
			oneOf(c, p .. ".jobChange", u.jobChange, { line = true, none = true })
			-- 入手経路は visitor・firstClear:<dungeonId>・login の3つだけ（D-155, D-169）
			if type(u.acquire) ~= "string" then
				c:error(p .. ".acquire", "文字列が必要")
			elseif string.sub(u.acquire, 1, 11) == "firstClear:" then
				c:ref(p .. ".acquire", string.sub(u.acquire, 12), idSet(d.Dungeons))
			elseif u.acquire == "login" then
				-- ログインボーナス7日目のユニーク（D-155）。配る順 loginOrder は重ならない
				if c:integer(p .. ".loginOrder", u.loginOrder, 1) then
					if loginOrders[u.loginOrder] then
						c:error(p .. ".loginOrder", `loginOrder が重複: {u.loginOrder}`)
					end
					loginOrders[u.loginOrder] = true
				end
			elseif u.acquire ~= "visitor" then
				c:error(p .. ".acquire", `許可されていない値: {u.acquire}`)
			end
		end
	end
	for id in exclusiveIds do
		if not exclusiveOwner[id] then
			c:warn("Gifts", `持ち主のユニークがいない専用ギフト: {id}`)
		end
	end
end

local function validateGuildLevels(c: Checker, d: any)
	local G = d.GuildLevels
	if type(G) ~= "table" then
		c:error("GuildLevels", "テーブルが必要")
		return
	end
	c:integer("GuildLevels.maxLevel", G.maxLevel, 1)
	local itemIds = idSet(d.Items)
	if c:array("GuildLevels.levels", G.levels, G.maxLevel) then
		for i, row in G.levels do
			local p = `GuildLevels.levels[{i}]`
			if row.level ~= i then
				c:error(p .. ".level", "level は 1 からの連番")
			end
			c:integer(p .. ".expToNext", row.expToNext, if i < G.maxLevel then 1 else 0)
			for itemId, n in row.rewards or {} do
				c:ref(p .. ".rewards", itemId, itemIds)
				c:integer(`{p}.rewards.{itemId}`, n, 1)
			end
		end
	end
end

local function validateExpansions(c: Checker, d: any)
	c:uniqueIds("Expansions", d.Expansions, "exp_")
	if type(d.Expansions) ~= "table" then
		return
	end
	for i, e in d.Expansions do
		local p = `Expansions[{i}]`
		oneOf(c, p .. ".kind", e.kind, {
			partySlots = true,
			candidateSlots = true,
			rosterSize = true,
			warehouseSize = true,
			trainingLevel = true,
		})
		local maxValue = if e.kind == "unlockRank"
			then (if type(d.Rarities) == "table" then rarityCount(d) else 0)
			elseif
				e.kind == "trainingLevel"
				and type(d.Constants) == "table"
				and type(d.Constants.trainingFacility) == "table"
			then #d.Constants.trainingFacility
			else nil
		if c:array(p .. ".steps", e.steps) then
			local prev = -math.huge
			for k, s in e.steps do
				local q = `{p}.steps[{k}]`
				if c:integer(q .. ".value", s.value, 1) and s.value <= prev then
					c:error(q .. ".value", "昇順が必要")
				end
				prev = if type(s.value) == "number" then s.value else prev
				if maxValue and type(s.value) == "number" and s.value > maxValue then
					c:error(q .. ".value", `{maxValue} 以下が必要`)
				end
				c:integer(q .. ".guildLevel", s.guildLevel, 1)
				c:integer(q .. ".gold", s.gold, 0)
				if s.requiresClear ~= nil then
					c:ref(q .. ".requiresClear", s.requiresClear, idSet(d.Dungeons))
				end
			end
		end
	end
end

-- id → 行 の索引を作る
-- 日替わりの特性（D-156、04章 §7）
local DAILY_TRAIT_EFFECTS = {
	chestMult = true,
	expMult = true,
	atkPctPhysical = true,
	atkPctMagic = true,
	travelMult = true,
}

local function validateDailyTraits(c: Checker, d: any)
	local rows = d.DailyTraits
	if not c:array("DailyTraits", rows) then
		return
	end
	if #rows == 0 then
		c:error("DailyTraits", "1行以上が必要")
	end
	c:uniqueIds("DailyTraits", rows, "dt_")
	for i, r in rows do
		local p = `DailyTraits[{i}]`
		oneOf(c, p .. ".effect", r.effect, DAILY_TRAIT_EFFECTS)
		if r.effect == "chestMult" or r.effect == "expMult" then
			c:number(p .. ".value", r.value, 1) -- 良い効果だけ（D-156）
		elseif r.effect == "travelMult" then
			c:number(p .. ".value", r.value, 0, 1)
		else
			c:number(p .. ".value", r.value, 0)
		end
	end
	-- どの帯にも当たるダンジョンがあること（06章 §16）
	local K = d.Constants
	if type(K) == "table" and type(K.dailyTraitBands) == "table" and type(d.Dungeons) == "table" then
		for i, b in K.dailyTraitBands do
			local found = false
			for _, dg in d.Dungeons do
				if type(b) == "table" and type(dg.tier) == "number" and dg.tier >= b.min and dg.tier <= b.max then
					found = true
				end
			end
			if not found then
				c:error(`Constants.dailyTraitBands[{i}]`, "その帯の難度のダンジョンがない")
			end
		end
	end
end

-- 特別な宝箱（D-166, D-171、04章 §11）
local RARE_PILE = "special:rare"

local function validateSpecialChests(c: Checker, d: any)
	local rows = d.SpecialChests
	if not c:array("SpecialChests", rows) then
		return
	end
	c:uniqueIds("SpecialChests", rows, "spc_")
	local piles: { [string]: boolean } = {}
	local nRarity = rarityCount(d)
	for i, r in rows do
		local p = `SpecialChests[{i}]`
		if type(r.pileKey) ~= "string" or string.sub(r.pileKey, 1, 8) ~= "special:" then
			c:error(p .. ".pileKey", "special: で始まる宝箱の山の鍵が必要")
		elseif piles[r.pileKey] then
			c:error(p .. ".pileKey", `pileKey が重複: {r.pileKey}`)
		else
			piles[r.pileKey] = true
		end
		if r.pileKey == RARE_PILE then
			-- レアダンジョンは相当するダンジョンの表を使う（行に表を持たない：D-171）
			if r.rarityWeights ~= nil then
				c:error(
					p .. ".rarityWeights",
					"レアダンジョンの行は表を持たない（相当するダンジョンの表を使う）"
				)
			end
		else
			local okWeights = false
			if c:array(p .. ".rarityWeights", r.rarityWeights) then
				if #r.rarityWeights > nRarity then
					c:error(p .. ".rarityWeights", `レアリティの数（{nRarity}）以下が必要`)
				end
				local sum = 0
				for k, w in r.rarityWeights do
					if c:number(`{p}.rarityWeights[{k}]`, w, 0) then
						sum += w
					end
				end
				if sum <= 0 then
					c:error(p .. ".rarityWeights", "合計が0より大きいことが必要")
				else
					okWeights = true
				end
			end
			local okLine = c:integer(p .. ".effectMinRarity", r.effectMinRarity, 1, nRarity)
			local okLo = c:probability(p .. ".effectRateMin", r.effectRateMin)
			local okHi = c:probability(p .. ".effectRateMax", r.effectRateMax)
			if okLo and okHi and r.effectRateMin > r.effectRateMax then
				c:error(p, "effectRateMin > effectRateMax")
			elseif okWeights and okLine and okLo and okHi then
				-- 行ごとの基準で演出率を検査する（D-090 の 10〜15% は普通のダンジョンだけ：D-166）
				checkEffectRate(
					c,
					p .. ".effectMinRarity",
					r.rarityWeights,
					r.effectMinRarity,
					r.effectRateMin,
					r.effectRateMax
				)
			end
		end
	end
end

-- 報酬の形（クエスト・ログインボーナス・プレイ時間で共通。受け取り箱に入る：D-164）
--   { goldMult?, items? = { [itemId] = 数 }, chests? = { { pileKey, count, rank? } } }
-- ゴールドは固定額を置かず、係数 goldMult を基準のダンジョンの rewardGoldBase に掛ける（D-190, D-198、06章 §22）
-- 宝箱の山は表を持つ特別な宝箱（D-171）。rank を省けばその表で抽選する
local function validateRewards(c: Checker, path: string, r: any, d: any)
	if type(r) ~= "table" then
		c:error(path, "報酬のテーブルが必要")
		return
	end
	for k in r do
		if k ~= "goldMult" and k ~= "items" and k ~= "chests" then
			c:error(path, `知らない報酬の種類: {tostring(k)}`)
		end
	end
	if r.goldMult ~= nil then
		c:number(path .. ".goldMult", r.goldMult, 0)
	end
	if r.items ~= nil then
		if type(r.items) ~= "table" then
			c:error(path .. ".items", "テーブルが必要")
		else
			local known = idSet(d.Items)
			for itemId, n in r.items do
				c:ref(path .. ".items", itemId, known)
				for _, it in d.Items or {} do
					if it.id == itemId and it.kind == "sellable" then
						c:error(path .. ".items", `売却用アイテムは報酬にしない: {itemId}`)
					end
				end
				c:integer(`{path}.items.{itemId}`, n, 1)
			end
		end
	end
	if r.chests ~= nil and c:array(path .. ".chests", r.chests) then
		local piles: { [string]: boolean } = {}
		for _, row in d.SpecialChests or {} do
			if row.pileKey ~= RARE_PILE and row.rarityWeights ~= nil then
				piles[row.pileKey] = true
			end
		end
		for i, ch in r.chests do
			local q = `{path}.chests[{i}]`
			if type(ch) ~= "table" then
				c:error(q, "テーブルが必要")
			else
				if type(ch.pileKey) ~= "string" or not piles[ch.pileKey] then
					c:error(
						q .. ".pileKey",
						`表を持つ特別な宝箱の山が必要（値: {tostring(ch.pileKey)}）`
					)
				end
				c:integer(q .. ".count", ch.count, 1)
				if ch.rank ~= nil then
					c:integer(q .. ".rank", ch.rank, 1, rarityCount(d))
				end
			end
		end
	end
end

local QUEST_KINDS = {
	expeditions = true,
	chestsOpened = true,
	hires = true,
	trainings = true,
	clears = true,
	rebirths = true,
}

-- クエスト・ログインボーナス・プレイ時間（D-153, D-154, D-155）
local function validateRewardSources(c: Checker, d: any)
	local K = if type(d.Constants) == "table" then d.Constants else {}
	-- 報酬のゴールドの基準（D-190）はダンジョンごとの rewardGoldBase に移した（D-198。検査はダンジョンの検証で行う）
	if K.rewardGoldBase ~= nil then
		c:error("Constants.rewardGoldBase", "Dungeons の rewardGoldBase に移した（D-198）")
	end
	local rows = d.Quests
	if c:array("Quests", rows) then
		c:uniqueIds("Quests", rows, "qst_")
		local counts = { daily = 0, weekly = 0 }
		for i, q in rows do
			local p = `Quests[{i}]`
			oneOf(c, p .. ".period", q.period, { daily = true, weekly = true })
			oneOf(c, p .. ".kind", q.kind, QUEST_KINDS)
			if q.kind == "rebirths" and q.period ~= "weekly" then
				c:error(p .. ".kind", "転生のお題はウィークリーだけ（D-153）")
			end
			c:integer(p .. ".amountPerParty", q.amountPerParty, 1)
			validateRewards(c, p .. ".rewards", q.rewards, d)
			if counts[q.period] then
				counts[q.period] += 1
			end
		end
		if type(K.questDailyCount) == "number" and counts.daily < K.questDailyCount then
			c:error("Quests", `デイリーの候補が questDailyCount（{K.questDailyCount}）より少ない`)
		end
		if type(K.questWeeklyCount) == "number" and counts.weekly < K.questWeeklyCount then
			c:error(
				"Quests",
				`ウィークリーの候補が questWeeklyCount（{K.questWeeklyCount}）より少ない`
			)
		end
	end
	validateRewards(c, "Constants.questDailyBonus", K.questDailyBonus, d)
	validateRewards(c, "Constants.questWeeklyBonus", K.questWeeklyBonus, d)

	-- 紹介の報酬（D-157, D-180）：招待された側・招待した側
	if type(K.referralRewards) ~= "table" then
		c:error("Constants.referralRewards", "テーブルが必要")
	else
		for _, role in { "invitee", "inviter" } do
			validateRewards(c, `Constants.referralRewards.{role}`, K.referralRewards[role], d)
		end
	end

	-- ログインボーナス：1〜6日目と fallback（7日目はユニーク）
	local L = d.LoginBonus
	if type(L) ~= "table" then
		c:error("LoginBonus", "テーブルが必要")
	else
		if c:array("LoginBonus.days", L.days, 6) then
			for i, r in L.days do
				validateRewards(c, `LoginBonus.days[{i}]`, r, d)
			end
		end
		validateRewards(c, "LoginBonus.fallback", L.fallback, d)
	end

	-- プレイ時間：段階は昇順、1日の上限まで
	local P = d.PlaytimeRewards
	if c:array("PlaytimeRewards", P) then
		if #P == 0 then
			c:error("PlaytimeRewards", "1行以上が必要")
		end
		local prev = 0
		for i, row in P do
			local p = `PlaytimeRewards[{i}]`
			if c:integer(p .. ".minutes", row.minutes, 1) then
				if row.minutes <= prev then
					c:error(p .. ".minutes", "昇順が必要")
				end
				if type(K.playtimeDailyCapSeconds) == "number" and row.minutes * 60 > K.playtimeDailyCapSeconds then
					c:error(p .. ".minutes", "playtimeDailyCapSeconds を超える段階は届かない")
				end
				prev = row.minutes
			end
			validateRewards(c, p .. ".rewards", row.rewards, d)
		end
	end
end

-- マップイベント（D-152、04章 §12）：種類と出る場所。割合（mapEventKindWeights）は種類を指す
local MAP_EVENT_KINDS = { rareDungeon = true, raid = true, merchant = true }

local function validateMapEvents(c: Checker, d: any)
	local M = d.MapEvents
	if type(M) ~= "table" then
		c:error("MapEvents", "テーブルが必要")
		return
	end
	local ids = c:uniqueIds("MapEvents.kinds", M.kinds, "mev_")
	if type(M.kinds) == "table" then
		local seenKind: { [string]: boolean } = {}
		for i, r in M.kinds do
			local p = `MapEvents.kinds[{i}].kind`
			oneOf(c, p, r.kind, MAP_EVENT_KINDS)
			if type(r.kind) == "string" then
				if seenKind[r.kind] then
					c:error(p, `kind が重複: {r.kind}`)
				end
				seenKind[r.kind] = true
			end
		end
	end
	local placeIds = c:uniqueIds("MapEvents.places", M.places, "mev_")
	if type(M.places) == "table" and #M.places == 0 then
		c:error("MapEvents.places", "1行以上が必要")
	end
	for id in placeIds do
		if ids[id] then
			c:error("MapEvents.places", `種類と同じ id: {id}`)
		end
	end
	local K = d.Constants
	if type(K) == "table" and type(K.mapEventKindWeights) == "table" then
		for i, e in K.mapEventKindWeights do
			c:ref(`Constants.mapEventKindWeights[{i}].id`, if type(e) == "table" then e.id else nil, ids)
		end
	end
end

local function byId(rows: any): { [string]: any }
	local m = {}
	if type(rows) == "table" then
		for _, r in rows do
			m[r.id] = r
		end
	end
	return m
end

-- 公開 API ----------------------------------------------------------------

-- data（src/data の束）を検証し、問題の一覧を返す
function MasterData.validate(data: any): { Issue }
	local c = newChecker()
	if type(data) ~= "table" then
		c:error("(root)", "テーブルが必要")
		return c.issues
	end
	validateConstants(c, data.Constants, if type(data.Rarities) == "table" then #data.Rarities else 0)
	validateContent(c, data)
	validateLootAndStarter(c, data)
	validateHiringData(c, data)
	validateGuildLevels(c, data)
	validateExpansions(c, data)
	validateDailyTraits(c, data)
	validateSpecialChests(c, data)
	validateRewardSources(c, data)
	validateMapEvents(c, data)
	return c.issues
end

function MasterData.formatIssues(issues: { Issue }): string
	local lines = {}
	for _, i in issues do
		table.insert(lines, `[{i.level}] {i.path}: {i.message}`)
	end
	return table.concat(lines, "\n")
end

-- 検証して、error があれば失敗させる（起動しない）
function MasterData.load(data: any): any
	local issues = MasterData.validate(data)
	local errors = {}
	for _, i in issues do
		if i.level == "error" then
			table.insert(errors, i)
		end
	end
	if #errors > 0 then
		error("マスターデータの検証に失敗しました:\n" .. MasterData.formatIssues(errors), 2)
	end
	-- 宝箱のレアリティの抽選表（D-085）：0の行を除いた { rank, weight } の配列
	for _, dg in data.Dungeons do
		local t = {}
		for rank, w in dg.chestRarityWeights do
			if w > 0 then
				table.insert(t, { rank = rank, weight = w })
			end
		end
		dg.chestRarityTable = t
	end
	-- 特別な宝箱（D-166）：pileKey → 行。表を持つ行には 0 を除いた { rank, weight } を付ける
	local specialChests = {}
	for _, row in data.SpecialChests do
		if row.rarityWeights then
			local t = {}
			for rank, w in row.rarityWeights do
				if w > 0 then
					table.insert(t, { rank = rank, weight = w })
				end
			end
			row.rarityTable = t
		end
		specialChests[row.pileKey] = row
	end
	-- ログインボーナス7日目のユニーク（D-155）：loginOrder の順
	local loginUniques = {}
	for _, u in data.Uniques do
		if u.acquire == "login" then
			table.insert(loginUniques, u)
		end
	end
	table.sort(loginUniques, function(a, b)
		return a.loginOrder < b.loginOrder
	end)
	-- 一般の抽選に出るギフト（D-165）と、今週の訪問者・特別な訪問者の候補（acquire = "visitor"。データの並び順：D-158）
	local generalGifts = {}
	for _, g in data.Gifts do
		if g.exclusive ~= true then
			table.insert(generalGifts, g)
		end
	end
	local visitorUniques = {}
	for _, u in data.Uniques do
		if u.acquire == "visitor" then
			table.insert(visitorUniques, u)
		end
	end
	-- core が使う形にまとめる（読み取り専用）
	return table.freeze({
		rarityCount = #data.Rarities,
		raw = data,
		K = data.Constants,
		rarities = data.Rarities,
		jobs = byId(data.Jobs),
		gifts = byId(data.Gifts),
		giftList = generalGifts, -- 一般の抽選（雇用の初期ギフト・転生で増えるギフト）に出るギフト。専用ギフトは除く（D-165）
		modifiers = byId(data.Modifiers),
		equipmentBases = byId(data.EquipmentBases),
		items = byId(data.Items),
		monsters = byId(data.Monsters),
		dungeons = byId(data.Dungeons),
		dungeonList = data.Dungeons,
		appearances = byId(data.Appearances),
		uniques = byId(data.Uniques),
		expansions = byId(data.Expansions),
		dailyTraits = byId(data.DailyTraits),
		dailyTraitList = data.DailyTraits,
		specialChests = specialChests,
		quests = byId(data.Quests),
		questList = data.Quests,
		loginBonus = data.LoginBonus,
		loginUniques = loginUniques,
		visitorUniques = visitorUniques,
		playtimeRewards = data.PlaytimeRewards,
		mapEventKinds = byId(data.MapEvents.kinds),
		mapEventPlaces = data.MapEvents.places,
	})
end

-- テスト用に検証の補助を公開する
MasterData._newChecker = newChecker

return MasterData
