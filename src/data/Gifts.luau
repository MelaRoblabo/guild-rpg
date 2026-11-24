--!strict
-- ギフト（ゲーム仕様書04章 §4、D-023, D-033）。効果量は体感できる強さに引き上げ（D-070）
-- effect.kind:
--   statPct       stat を value の割合だけ上げる（個体補正。上限 personalBonusCap）
--   lucky         宝箱確保時の追加発見（発動率は Constants.luckyChancePerHolder）
--   atkVsTagPct   tag を持つモンスターへの攻撃力を value の割合だけ上げる（個体補正）
--   travelMult    terrainTag を持つダンジョンで片道時間に value を掛ける（パーティ内で重複しない）
--   trapDexMult   罠判定で本人の技巧を value 倍で数える
--   expPct        本人の獲得経験値を value の割合だけ増やす
-- weight: 抽選の重み（雇用・転生時のギフト抽選）

return {
	{
		id = "gift_swift",
		name = "俊足",
		nameEn = "Swift",
		weight = 1,
		effect = { kind = "statPct", stat = "agi", value = 0.25 },
	},
	{ id = "gift_lucky", name = "幸運", nameEn = "Lucky", weight = 1, effect = { kind = "lucky" } },
	{
		id = "gift_exorcist",
		name = "退魔の才",
		nameEn = "Exorcist",
		weight = 1,
		effect = { kind = "atkVsTagPct", tag = "undead", value = 0.30 },
	},
	{
		id = "gift_sturdy",
		name = "頑健",
		nameEn = "Sturdy",
		weight = 1,
		effect = { kind = "statPct", stat = "hp", value = 0.25 },
	},
	{
		id = "gift_guide",
		name = "道案内",
		nameEn = "Pathfinder",
		weight = 1,
		effect = { kind = "travelMult", terrainTag = "outdoor", value = 0.7 },
	},
	{
		id = "gift_trapsense",
		name = "罠師の勘",
		nameEn = "Trap Sense",
		weight = 1,
		effect = { kind = "trapDexMult", value = 3 },
	},
	{
		id = "gift_glutton",
		name = "大食らい",
		nameEn = "Glutton",
		weight = 1,
		effect = { kind = "expPct", value = 0.25 },
	},
}
