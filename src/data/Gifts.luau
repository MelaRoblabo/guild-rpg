--!strict
-- ギフト（ゲーム仕様書04章 §4、D-023, D-033）
-- effect.kind:
--   statPct       stat を value の割合だけ上げる（個体補正。上限 personalBonusCap）
--   lucky         宝箱確保時の追加発見（発動率は Constants.luckyChancePerHolder）
--   atkVsTagPct   tag を持つモンスターへの攻撃力を value の割合だけ上げる（個体補正）
--   travelMult    terrainTag を持つダンジョンで片道時間に value を掛ける（パーティ内で重複しない）
--   trapDexMult   罠判定で本人の技巧を value 倍で数える
--   expPct        本人の獲得経験値を value の割合だけ増やす
-- weight: 抽選の重み（雇用・転生時のギフト抽選）

return {
	{ id = "gift_swift", name = "俊足", weight = 1, effect = { kind = "statPct", stat = "agi", value = 0.10 } },
	{ id = "gift_lucky", name = "幸運", weight = 1, effect = { kind = "lucky" } },
	{
		id = "gift_exorcist",
		name = "退魔の才",
		weight = 1,
		effect = { kind = "atkVsTagPct", tag = "undead", value = 0.10 },
	},
	{ id = "gift_sturdy", name = "頑健", weight = 1, effect = { kind = "statPct", stat = "hp", value = 0.10 } },
	{
		id = "gift_guide",
		name = "道案内",
		weight = 1,
		effect = { kind = "travelMult", terrainTag = "outdoor", value = 0.8 },
	},
	{ id = "gift_trapsense", name = "罠師の勘", weight = 1, effect = { kind = "trapDexMult", value = 2 } },
	{ id = "gift_glutton", name = "大食らい", weight = 1, effect = { kind = "expPct", value = 0.10 } },
}
