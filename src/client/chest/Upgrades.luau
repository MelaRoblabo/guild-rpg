--!strict
-- 開封で出た装備で「誰が強くなるか」（S-31 の明かす画面と結果：D-130・D-223）。純粋な関数。
--   - 比べる値は一括売却と同じ（Formulas.bulkSellValue：武器は攻撃、防具は物理＋魔法の防御。補助は比べない）。
--   - 強くなる＝その品を付けられる冒険者で、同じ枠の今の装備より比べる値が高い（枠が空なら必ず強くなる）。
--   - ギルドにいない（冒険中の）人は勧めない。帰ってきてからのお楽しみにする（D-285 ①）。
--   - core の関数は呼び出し側から deps で受け取る（Roblox と Lune で require の道が違うため）。

export type Deps = {
	value: (item: any, master: any) -> number?, -- Formulas.bulkSellValue
	canEquip: (jobId: string, baseId: string, master: any) -> boolean, -- Inventory.canEquip
	busy: ((state: any, advUid: string) -> boolean)?, -- Party.isAdventurerBusy（ギルドにいない人は勧めない：D-285）
}

export type Upgrade = {
	itemUid: string,
	advUid: string,
	slot: string,
	value: number, -- 新しい品の比べる値
	current: number, -- 今の装備の比べる値（空なら 0）
	delta: number,
}

local Upgrades = {}

-- 1つの品で強くなる冒険者を、強くなる差の大きい順に
function Upgrades.forItem(state: any, itemUid: string, master: any, deps: Deps): { Upgrade }
	local out: { Upgrade } = {}
	local item = state.equipment[itemUid]
	if item == nil or item.equippedBy ~= nil then
		return out
	end
	local v = deps.value(item, master)
	local base = master.equipmentBases[item.baseId]
	if v == nil or base == nil then
		return out
	end
	for advUid, adv in state.adventurers do
		local away = deps.busy ~= nil and deps.busy(state, advUid)
		if not away and deps.canEquip(adv.jobId, item.baseId, master) then
			local curUid = adv.equipment and adv.equipment[base.slot]
			local cur = if curUid then state.equipment[curUid] else nil
			local cv = if cur then deps.value(cur, master) or 0 else 0
			if v > cv then
				table.insert(out, {
					itemUid = itemUid,
					advUid = advUid,
					slot = base.slot,
					value = v,
					current = cv,
					delta = v - cv,
				})
			end
		end
	end
	table.sort(out, function(a, b)
		if a.delta ~= b.delta then
			return a.delta > b.delta
		end
		return a.advUid < b.advUid
	end)
	return out
end

-- 品の束から、1人に1つ・1つの品は1人に割り当てた強化の一覧（差の大きい順）。
-- 結果の画面は先頭のカードを見せ、残りは数だけ出す（D-223 ①）
function Upgrades.plan(state: any, itemUids: { string }, master: any, deps: Deps): { Upgrade }
	local all: { Upgrade } = {}
	for _, uid in itemUids do
		for _, u in Upgrades.forItem(state, uid, master, deps) do
			table.insert(all, u)
		end
	end
	table.sort(all, function(a, b)
		if a.delta ~= b.delta then
			return a.delta > b.delta
		end
		if a.itemUid ~= b.itemUid then
			return a.itemUid < b.itemUid
		end
		return a.advUid < b.advUid
	end)
	local usedItem: { [string]: boolean } = {}
	local usedAdv: { [string]: boolean } = {}
	local out: { Upgrade } = {}
	for _, u in all do
		if not usedItem[u.itemUid] and not usedAdv[u.advUid] then
			usedItem[u.itemUid] = true
			usedAdv[u.advUid] = true
			table.insert(out, u)
		end
	end
	return out
end

return Upgrades
