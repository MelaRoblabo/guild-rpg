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

local function validateConstants(c: Checker, k: any)
	local p = "Constants"
	if type(k) ~= "table" then
		c:error(p, "テーブルが必要")
		return
	end

	-- 戦闘
	if c:array(p .. ".hitWeights", k.hitWeights, 4) then
		c:weights(p .. ".hitWeights", k.hitWeights, nil, true)
	end
	c:probability(p .. ".minDamageRate", k.minDamageRate)
	c:number(p .. ".critCoef", k.critCoef, 0)
	c:probability(p .. ".critCap", k.critCap)
	c:number(p .. ".critMult", k.critMult, 1)
	c:integer(p .. ".maxTurns", k.maxTurns, 1)
	c:number(p .. ".monsterScalePerBattle", k.monsterScalePerBattle, 0)

	-- イベント
	c:weights(p .. ".eventWeights", k.eventWeights, "weight", true)
	if c:weights(p .. ".chestRankOffsets", k.chestRankOffsets, "weight", true) then
		for i, e in k.chestRankOffsets do
			c:integer(`{p}.chestRankOffsets[{i}].offset`, e.offset, 0, 4)
		end
	end
	c:probability(p .. ".fountainHealRate", k.fountainHealRate)
	c:number(p .. ".trapK", k.trapK, 0)
	c:probability(p .. ".trapDamageRate", k.trapDamageRate)
	c:number(p .. ".trapLevelCoefStep", k.trapLevelCoefStep, 0)

	-- 支援・幸運
	c:probability(p .. ".healThreshold", k.healThreshold)
	c:number(p .. ".healCoef", k.healCoef, 0)
	c:probability(p .. ".luckyChancePerHolder", k.luckyChancePerHolder)
	c:probability(p .. ".luckyChanceCap", k.luckyChanceCap)

	-- 移動・再生
	c:number(p .. ".travelSecondsPerDistance", k.travelSecondsPerDistance, 0)
	c:number(p .. ".travelAgiDivisor", k.travelAgiDivisor, 1)
	c:number(p .. ".guideTravelMult", k.guideTravelMult, 0, 1)
	c:number(p .. ".replaySecondsPerTurn", k.replaySecondsPerTurn, 0)
	c:number(p .. ".replaySecondsPerEvent", k.replaySecondsPerEvent, 0)

	c:number(p .. ".personalBonusCap", k.personalBonusCap, 0)

	-- 成長
	c:integer(p .. ".growthVariance", k.growthVariance, 0)
	c:number(p .. ".expBase", k.expBase, 1)
	c:number(p .. ".expExponent", k.expExponent, 0)
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
	c:number(p .. ".gluttonExpBonus", k.gluttonExpBonus, 0)

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
	for _, s in Types.STAT_KEYS do
		c:range(
			`{p}.rebirthBonusRange.{s}`,
			if type(k.rebirthBonusRange) == "table" then k.rebirthBonusRange[s] else nil
		)
	end
	c:integer(p .. ".rebirthFreeRerolls", k.rebirthFreeRerolls, 0)

	-- 雇用
	c:integer(p .. ".hireCost", k.hireCost, 0)
	for _, s in Types.STAT_KEYS do
		local r = if type(k.hireStatRange) == "table" then k.hireStatRange[s] else nil
		if c:range(`{p}.hireStatRange.{s}`, r) then
			c:number(`{p}.hireStatRange.{s}.maxPerGuildLevel`, r.maxPerGuildLevel, 0)
		end
	end
	c:integer(p .. ".hireFreeRerolls", k.hireFreeRerolls, 0)
	c:probability(p .. ".specialVisitorChance", k.specialVisitorChance)

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
		if c:array(`{p}.{key}`, k[key], 5) then
			for i, v in k[key] do
				c:number(`{p}.{key}[{i}]`, v, 0)
			end
		end
	end
	c:number(p .. ".sellGradeCoef", k.sellGradeCoef, 0)
	c:number(p .. ".equipGradeCoef", k.equipGradeCoef, 0)
	c:integer(p .. ".chestStorageMax", k.chestStorageMax, 1)

	-- ギルド
	c:integer(p .. ".guildExpPerFloor", k.guildExpPerFloor, 0)
	c:integer(p .. ".guildExpClearBonus", k.guildExpClearBonus, 0)
	c:integer(p .. ".guildExpFirstClear", k.guildExpFirstClear, 0)
	c:integer(p .. ".guildLevelMax", k.guildLevelMax, 1)
end

-- 公開 API ----------------------------------------------------------------

-- data（src/data の束）を検証し、問題の一覧を返す
function MasterData.validate(data: any): { Issue }
	local c = newChecker()
	if type(data) ~= "table" then
		c:error("(root)", "テーブルが必要")
		return c.issues
	end
	validateConstants(c, data.Constants)
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
	return table.freeze(data)
end

-- テスト用に検証の補助を公開する
MasterData._newChecker = newChecker

return MasterData
