--!strict
-- 旅の商人の品の差（D-204・D-218・D-231 ⑭）。純粋な関数（Lune でテストする）。
--   品ごとに、付けられる冒険者のうち一番強くなる差（武器・防具は一括売却の比べる値、補助は種類ごとの値。護符は倍率）。
--   誰も強くならなければ nil（カードに▲を出さない）。

local EquipChoice = require("../adventurers/EquipChoice")

local MerchantView = {}

export type Best = { delta: number, ratio: number? }

function MerchantView.best(state: any, item: any, master: any, deps: EquipChoice.Deps): Best?
	local base = master.equipmentBases[item.baseId]
	if base == nil then
		return nil
	end
	local best: Best? = nil
	for _, adv in state.adventurers do
		if deps.canEquip(adv.jobId, item.baseId, master) then
			local curUid = adv.equipment and adv.equipment[base.slot]
			local cur = if curUid then state.equipment[curUid] else nil
			-- 補助は同じ種類の品を付けている人とだけ比べる（指輪どうし・護符どうし・盾どうし）
			local comparable = base.slot ~= "sub"
				or cur == nil
				or EquipChoice.kindOf(cur, master) == EquipChoice.kindOf(item, master)
			if comparable then
				local d, ratio = EquipChoice.delta(item, cur, master, deps)
				local score = ratio or d
				if d > 0 and (best == nil or score > ((best :: Best).ratio or (best :: Best).delta)) then
					best = { delta = d, ratio = ratio }
				end
			end
		end
	end
	return best
end

return MerchantView
