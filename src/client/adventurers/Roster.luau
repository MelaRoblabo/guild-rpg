--!strict
-- 冒険者の一覧と詳細（S-40・S-41、D-117・D-119・§5.1）。純粋な関数（Lune でテストする）。
--   - 職業系統のタブ（全員・戦士系・探索系・魔法系・支援系）と状態（全員・待機・探索中・パーティなし）で絞る。
--   - 並べ替え：level（Lv→転生回数）・attack（攻撃力）・maxHp・hired（雇用順）・rebirths（転生回数→Lv）。desc＝高い順（新しい順）。
--   - 倉庫にもっと良い装備があるか（武器・防具：一括売却の比べる値。補助は比べない：D-167・§5.1）。
--   - core の関数は呼び出し側から deps で受け取る（Roblox と Lune で require の道が違うため）。

export type Deps = {
	snapshot: (state: any, uid: string, master: any) -> any, -- Game.query.snapshot
	busy: (state: any, uid: string) -> boolean, -- Party.isAdventurerBusy
	find: (state: any, uid: string) -> (number?, number?), -- Party.find
	value: (item: any, master: any) -> number?, -- Formulas.bulkSellValue
	canEquip: (jobId: string, baseId: string, master: any) -> boolean, -- Inventory.canEquip
}

local Roster = {}

Roster.LINES = { "all", "warrior", "scout", "mage", "support" }
Roster.STATES = { "all", "wait", "exploring", "none" }

-- 状態：exploring（探索・帰還中）／wait（パーティにいて待機）／none（パーティなし）
function Roster.stateOf(state: any, uid: string, deps: Deps): string
	if deps.busy(state, uid) then
		return "exploring"
	end
	local p = deps.find(state, uid)
	return if p then "wait" else "none"
end

local function keys(state: any, adv: any, sort: string, master: any, deps: Deps): { number }
	if sort == "attack" or sort == "maxHp" then
		local snap = deps.snapshot(state, adv.uid, master)
		return { if sort == "attack" then snap.atk else snap.maxHp, adv.level }
	elseif sort == "hired" then
		return { adv.hiredAt or 0 }
	elseif sort == "rebirths" then
		return { adv.rebirthCount or 0, adv.level }
	end
	return { adv.level, adv.rebirthCount or 0 }
end

-- 絞って並べた冒険者の uid の列
function Roster.list(state: any, line: string, stateFilter: string, prefs: any, master: any, deps: Deps): { string }
	local rows = {}
	for uid, adv in state.adventurers do
		local job = master.jobs[adv.jobId]
		local okLine = line == "all" or (job ~= nil and job.line == line)
		local okState = stateFilter == "all" or Roster.stateOf(state, uid, deps) == stateFilter
		if okLine and okState then
			table.insert(rows, { uid = uid, adv = adv, k = keys(state, adv, prefs.advSort, master, deps) })
		end
	end
	local desc = prefs.advDesc ~= false
	table.sort(rows, function(a, b)
		for i = 1, math.max(#a.k, #b.k) do
			local x, y = a.k[i] or 0, b.k[i] or 0
			if x ~= y then
				if desc then
					return x > y
				end
				return x < y
			end
		end
		local ha, hb = a.adv.hiredAt or 0, b.adv.hiredAt or 0
		if ha ~= hb then
			return ha < hb
		end
		return a.uid < b.uid
	end)
	local out = {}
	for _, r in rows do
		table.insert(out, r.uid)
	end
	return out
end

-- 倉庫に、その枠の今の装備より比べる値の高い品があるか（武器・防具だけ）
function Roster.betterGear(state: any, adv: any, slot: string, master: any, deps: Deps): boolean
	if slot == "sub" then
		return false
	end
	local curUid = adv.equipment and adv.equipment[slot]
	local cur = if curUid then state.equipment[curUid] else nil
	local cv = if cur then deps.value(cur, master) or 0 else 0
	for _, item in state.equipment do
		local base = master.equipmentBases[item.baseId]
		if item.equippedBy == nil and base and base.slot == slot and deps.canEquip(adv.jobId, item.baseId, master) then
			if (deps.value(item, master) or 0) > cv then
				return true
			end
		end
	end
	return false
end

-- どれかの枠にもっと良い装備があるか（一覧の緑の ▲）
function Roster.anyBetterGear(state: any, adv: any, master: any, deps: Deps): boolean
	return Roster.betterGear(state, adv, "weapon", master, deps) or Roster.betterGear(state, adv, "armor", master, deps)
end

-- 能力の棒の右端（仮。Q1：雇用の最高値＋(成長＋1)×(上限Lv−1)）
function Roster.statMax(adv: any, key: string, master: any): number
	local job = master.jobs[adv.jobId]
	local hire = master.K.hireStatRange[key]
	local growth = if job and job.growth then job.growth[key] or 0 else 0
	return hire.max + (growth + 1) * math.max(0, (adv.levelCap or 1) - 1)
end

return Roster
