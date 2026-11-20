--!strict
-- 装備の修飾語（ゲーム仕様書04章 §5、06章、D-060）
-- effect.kind:
--   flatStat      stat に値を足す（装備のステータス補正）
--   atkVsTagPct   tag を持つモンスターへの攻撃力を割合で上げる（個体補正）
--   healPct       回復量を割合で上げる（個体補正）
-- range: 付与時に抽選する値の範囲（仮）。flatStat は整数、Pct は小数

return {
	{
		id = "mod_trapward",
		name = "罠よけの",
		effect = { kind = "flatStat", stat = "dex" },
		range = { min = 2, max = 6 },
	},
	{
		id = "mod_swift",
		name = "俊足の",
		effect = { kind = "flatStat", stat = "agi" },
		range = { min = 2, max = 6 },
	},
	{
		id = "mod_exorcism",
		name = "退魔の",
		effect = { kind = "atkVsTagPct", tag = "undead" },
		range = { min = 0.05, max = 0.15 },
	},
	{ id = "mod_healing", name = "癒しの", effect = { kind = "healPct" }, range = { min = 0.05, max = 0.15 } },
}
