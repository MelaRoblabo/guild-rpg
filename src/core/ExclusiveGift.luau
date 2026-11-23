--!strict
-- 専用ギフト（D-165, D-174, D-177, D-185、docs/system/04_master_data.md §8、06_formulas.md §21）
-- ユニークだけが持つギフト。一般の抽選には出さない（master.giftList から除いてある）。最大4つの枠（giftMax）に数える。
--   ExclusiveGift.uniqueGiftIds  ユニークが加入するときのギフト（giftIds ＋ 専用ギフト）
--   ExclusiveGift.grant          冒険者に専用ギフトを足す（枠がいっぱいなら giftIds の先頭と入れ替える：D-177, D-185）
--   ExclusiveGift.partyEffects   パーティ全体の効果（同じ効果は重ねない：D-174）
-- 状態を持たない（関数の集合）。

local ExclusiveGift = {}

-- ユニークの行から、加入するときのギフトの並び（専用ギフトは最後）
function ExclusiveGift.uniqueGiftIds(u: any): { string }
	local out = table.clone(u.giftIds or {})
	if u.exclusiveGiftId and not table.find(out, u.exclusiveGiftId) then
		table.insert(out, u.exclusiveGiftId)
	end
	return out
end

-- 冒険者（ユニーク）に専用ギフトを足す。足したら true
-- ギフトの枠（giftMax）がいっぱいなら、一番古いギフト（giftIds の先頭）と入れ替える（D-177, D-185）
function ExclusiveGift.grant(adv: any, master: any): boolean
	if adv.uniqueId == nil then
		return false
	end
	local u = master.uniques[adv.uniqueId]
	if u == nil or u.exclusiveGiftId == nil then
		return false
	end
	local gifts = adv.giftIds
	if table.find(gifts, u.exclusiveGiftId) then
		return false
	end
	if #gifts >= master.K.giftMax and #gifts > 0 then
		gifts[1] = u.exclusiveGiftId
	else
		table.insert(gifts, u.exclusiveGiftId)
	end
	return true
end

export type PartyEffects = {
	travelMult: number, -- 片道秒に掛ける（1 なら効果なし）
	travelGiftId: string?,
	chestMult: number, -- 宝箱の数に掛ける（1 なら効果なし。端数は確率で切り上げ：D-173）
	chestGiftId: string?,
}

-- メンバー（MemberSnapshot の giftIds）から、パーティ全体の効果をまとめる
-- 同じ効果はパーティ内で重ねない（道案内と同じ：一番効果の大きい1つだけ。同じ大きさなら隊列の先の人）
function ExclusiveGift.partyEffects(members: { any }, master: any): PartyEffects
	local out: PartyEffects = { travelMult = 1, chestMult = 1 }
	for _, m in members do
		for _, giftId in m.giftIds do
			local g = master.gifts[giftId]
			local pe = if g and g.exclusive == true then g.partyEffect else nil
			if pe then
				if pe.kind == "travelMult" and pe.value < out.travelMult then
					out.travelMult, out.travelGiftId = pe.value, giftId
				elseif pe.kind == "chestMult" and pe.value > out.chestMult then
					out.chestMult, out.chestGiftId = pe.value, giftId
				end
			end
		end
	end
	return out
end

return ExclusiveGift
