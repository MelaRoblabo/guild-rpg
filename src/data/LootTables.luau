--!strict
-- 宝箱の中身の抽選（ゲーム仕様書06章 §3、Q-011、Q-020）。数値は仮
-- 1箱＝装備 1〜2 個 ＋（売却用アイテム または ゴールド）
-- レア以上（rank>=3）の箱は、Constants.potionChanceRarePlus でポーションが1個追加される（D-058）

return {
	chest = {
		equipmentCountWeights = {
			{ id = "1", count = 1, weight = 0.5 },
			{ id = "2", count = 2, weight = 0.5 },
		},
		extraWeights = {
			{ id = "sellable", weight = 0.5 },
			{ id = "gold", weight = 0.5 },
		},
		-- ゴールド = floor(ダンジョンの戦闘ゴールド × goldMult × sellRarityMult[ランク])
		goldMult = 3,
		-- ポーションが出る最低ランク
		potionMinRank = 3,
	},
	-- 初めて開ける宝箱に必ず入れる「パーティの誰かが強くなる」装備（D-246 ①）。
	-- 自動売却はしない。アイテムレベルはその宝箱のダンジョン。基本は、付けられて今の装備より強くなるものから選ぶ
	firstChest = {
		slot = "weapon", -- 武器（攻撃力の伸びが一番見えやすい）
		rarity = 2, -- アンコモン
		grade = 1, -- +1
	},
}
