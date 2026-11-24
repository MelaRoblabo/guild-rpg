--!strict
-- 装備の選択（S-42、D-130・D-231 ⑭・D-232 ⑥）。純粋な関数（Lune でテストする）。
--   - 候補は倉庫の品だけ（他の人が付けている品は出さない）。その人が付けられる、その枠の品。
--   - 武器・防具は一括売却の比べる値の差の大きい順。
--   - 補助は種類ごとの値の差（盾＝防御、指輪＝能力、護符＝XP の倍率）。並びは今と同じ種類→指輪→護符、種類の中は差の大きい順。
--   - 付け替えたときの値の変化（攻撃・防御・能力・最大HP・XP）を、変わる値だけ返す（右の面）。
--   - core の関数は呼び出し側から deps で受け取る（Roblox と Lune で require の道が違うため）。

export type Deps = {
	value: (item: any, master: any) -> number?, -- Formulas.bulkSellValue
	canEquip: (jobId: string, baseId: string, master: any) -> boolean, -- Inventory.canEquip
	equipMult: (rarity: number, grade: number, itemLevel: number, K: any) -> number, -- Formulas.equipMult
	expPct: (item: any, master: any) -> number, -- Formulas.equipExpPct
	memberDef: (state: any, adv: any, slot: number) -> any, -- Party.memberDef
	snapshot: (def: any, master: any) -> any, -- Formulas.memberSnapshot
}

export type Candidate = { uid: string, kind: string, delta: number, ratio: number? }

local EquipChoice = {}

-- 補助の種類：shield／ring／amulet（武器・防具は枠の名前）
function EquipChoice.kindOf(item: any, master: any): string
	local base = master.equipmentBases[item.baseId]
	if base == nil then
		return "?"
	end
	if base.slot ~= "sub" then
		return base.slot
	end
	if base.expPct then
		return "amulet"
	elseif base.stats then
		return "ring"
	end
	return "shield"
end

local function shieldDef(item: any?, master: any, deps: Deps): number
	if item == nil then
		return 0
	end
	local base = master.equipmentBases[item.baseId]
	local m = deps.equipMult(item.rarity, item.grade, item.itemLevel or 1, master.K)
	return math.floor((base.pdef or 0) * m) + math.floor((base.mdef or 0) * m)
end

local function ringStat(item: any?, stat: string, master: any, deps: Deps): number
	if item == nil then
		return 0
	end
	local base = master.equipmentBases[item.baseId]
	local v = base.stats and base.stats[stat]
	if v == nil then
		return 0
	end
	return math.floor(v * deps.equipMult(item.rarity, item.grade, item.itemLevel or 1, master.K))
end

-- 品1つの差（補助は種類ごとの値。護符は ratio＝倍率も）
function EquipChoice.delta(item: any, current: any?, master: any, deps: Deps): (number, number?)
	local kind = EquipChoice.kindOf(item, master)
	if kind == "shield" then
		return shieldDef(item, master, deps) - shieldDef(current, master, deps), nil
	elseif kind == "ring" then
		local base = master.equipmentBases[item.baseId]
		local stat = next(base.stats)
		return ringStat(item, stat, master, deps) - ringStat(current, stat, master, deps), nil
	elseif kind == "amulet" then
		local now = 1 + (if current then deps.expPct(current, master) else 0)
		local new = 1 + deps.expPct(item, master)
		return new - now, new / now
	end
	local cv = if current then deps.value(current, master) or 0 else 0
	return (deps.value(item, master) or 0) - cv, nil
end

local SUB_ORDER = { ring = 2, amulet = 3, shield = 4 }

-- 候補（倉庫の品）を並べる
function EquipChoice.candidates(state: any, adv: any, slot: string, master: any, deps: Deps): { Candidate }
	local curUid = adv.equipment and adv.equipment[slot]
	local current = if curUid then state.equipment[curUid] else nil
	local curKind = if current then EquipChoice.kindOf(current, master) else nil
	local out: { Candidate } = {}
	for uid, item in state.equipment do
		local base = master.equipmentBases[item.baseId]
		if item.equippedBy == nil and base and base.slot == slot and deps.canEquip(adv.jobId, item.baseId, master) then
			local d, ratio = EquipChoice.delta(item, current, master, deps)
			table.insert(out, { uid = uid, kind = EquipChoice.kindOf(item, master), delta = d, ratio = ratio })
		end
	end
	local function rank(c: Candidate): number
		if slot ~= "sub" then
			return 0
		end
		if c.kind == curKind then
			return 1
		end
		return SUB_ORDER[c.kind] or 9
	end
	table.sort(out, function(a, b)
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		if a.delta ~= b.delta then
			return a.delta > b.delta
		end
		return a.uid < b.uid
	end)
	return out
end

-- 付け替えたとき（itemUid＝nil は外す）の値の変化。変わる値だけ { key, before, after }
EquipChoice.KEYS = { "atk", "pdef", "mdef", "maxHp", "mag", "agi", "dex", "expRate" }

function EquipChoice.compare(state: any, adv: any, slot: string, itemUid: string?, master: any, deps: Deps): { any }
	local def = deps.memberDef(state, adv, 1)
	local before = deps.snapshot(def, master)
	local eq = table.clone(def.equipment)
	if itemUid then
		local e = state.equipment[itemUid]
		eq[slot] = {
			baseId = e.baseId,
			rarity = e.rarity,
			grade = e.grade,
			itemLevel = e.itemLevel,
			modifierId = e.modifierId,
			modifierValue = e.modifierValue,
		}
	else
		eq[slot] = nil
	end
	local d2 = table.clone(def)
	d2.equipment = eq
	local after = deps.snapshot(d2, master)
	local out = {}
	for _, k in EquipChoice.KEYS do
		if before[k] ~= after[k] then
			table.insert(out, { key = k, before = before[k], after = after[k] })
		end
	end
	return out
end

return EquipChoice
