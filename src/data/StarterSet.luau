--!strict
-- 初期状態（Q-020 仮。D-097：初期の4人は4項目合計約80＝雇用の平均並み）
-- 4職業1人ずつ、Lv1、コモン+0（アイテムレベル1）の装備。古い墓地を確実に踏破できること（01章：最初の宝箱1分以内）
-- 見た目ID・名前は仮（見た目データは M3 で用意する）

return {
	gold = 500,
	expansions = {
		partySlots = 1,
		candidateSlots = 3,
		rosterSize = 8,
		warehouseSize = 300,
		trainingLevel = 1, -- D-077
	},
	adventurers = {
		{
			name = "アルド",
			gender = "m",
			appearanceId = "chr_m_nor_phy_01",
			jobId = "job_warrior",
			baseStats = { str = 28, mag = 8, agi = 22, dex = 22, hp = 60 },
			giftIds = { "gift_sturdy" },
			equipment = { weapon = "eq_wpn_sword", armor = "eq_arm_chainmail", sub = "eq_sub_buckler" },
		},
		{
			name = "リン",
			gender = "f",
			appearanceId = "chr_f_nor_phy_01",
			jobId = "job_thief",
			baseStats = { str = 20, mag = 8, agi = 26, dex = 26, hp = 50 },
			giftIds = { "gift_trapsense" },
			equipment = { weapon = "eq_wpn_dagger", armor = "eq_arm_leather", sub = "eq_sub_ring_wind" },
		},
		{
			name = "セオ",
			gender = "m",
			appearanceId = "chr_m_nor_mag_01",
			jobId = "job_mage",
			baseStats = { str = 8, mag = 30, agi = 22, dex = 20, hp = 46 },
			giftIds = { "gift_swift" },
			equipment = { weapon = "eq_wpn_staff", armor = "eq_arm_robe", sub = "eq_sub_ring_wisdom" },
		},
		{
			name = "ミラ",
			gender = "f",
			appearanceId = "chr_f_nor_mag_01",
			jobId = "job_priest",
			baseStats = { str = 10, mag = 28, agi = 20, dex = 22, hp = 52 },
			giftIds = { "gift_lucky" },
			equipment = { weapon = "eq_wpn_mace", armor = "eq_arm_vestment", sub = "eq_sub_ring_wisdom" },
		},
	},
}
