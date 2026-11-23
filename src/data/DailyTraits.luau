--!strict
-- 日替わりの特性（D-156、docs/system/04_master_data.md §7）
-- effect: chestMult（宝箱の数 × value） / expMult（経験値 × value） /
--         atkPctPhysical・atkPctMagic（攻撃区分が合う者の攻撃力 × (1 + value)） / travelMult（片道秒 × value）
-- 良い効果だけを置く。レアリティを上げる特性は置かない（D-156）
-- 効果は個体補正・経験値補正の上限の外で掛ける（D-173）。どの日にどれが当たるかは 06章 §16
-- 値は D-156 の例をそのまま置いた仮の値（M7b-6 で決める）

return {
	{ id = "dt_chest", effect = "chestMult", value = 1.5 }, -- 仮（M7b-6）
	{ id = "dt_exp", effect = "expMult", value = 2 }, -- 仮（M7b-6）
	{ id = "dt_atk_physical", effect = "atkPctPhysical", value = 0.20 }, -- 仮（M7b-6）
	{ id = "dt_atk_magic", effect = "atkPctMagic", value = 0.20 }, -- 仮（M7b-6）
	{ id = "dt_travel", effect = "travelMult", value = 0.70 }, -- 仮（M7b-6）
}
