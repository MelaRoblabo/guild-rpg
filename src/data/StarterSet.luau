--!strict
-- 初期状態（Q-020 仮）
-- 4職業1人ずつ、Lv1、コモン+0（アイテムレベル1）の装備。古い墓地を確実に踏破できること（01章：最初の宝箱1分以内）
-- 見た目ID・名前は仮（見た目データは M3 で用意する）

return {
	gold = 500,
	expansions = { partySlots = 1, candidateSlots = 3, rosterSize = 8, warehouseSize = 300 },
	adventurers = {
		{
			name = "アルド",
			gender = "m",
			appearanceId = "chr_m_nor_phy_01",
			jobId = "job_warrior",
			baseStats = { str = 14, mag = 6, agi = 12, dex = 10, hp = 52 },
			giftIds = { "gift_sturdy" },
			equipment = { weapon = "eq_wpn_sword", armor = "eq_arm_chainmail", sub = "eq_sub_buckler" },
		},
		{
			name = "リン",
			gender = "f",
			appearanceId = "chr_f_nor_phy_01",
			jobId = "job_thief",
			baseStats = { str = 12, mag = 6, agi = 15, dex = 15, hp = 44 },
			giftIds = { "gift_trapsense" },
			equipment = { weapon = "eq_wpn_dagger", armor = "eq_arm_leather", sub = "eq_sub_ring_wind" },
		},
		{
			name = "セオ",
			gender = "m",
			appearanceId = "chr_m_nor_mag_01",
			jobId = "job_mage",
			baseStats = { str = 6, mag = 15, agi = 12, dex = 11, hp = 40 },
			giftIds = { "gift_swift" },
			equipment = { weapon = "eq_wpn_staff", armor = "eq_arm_robe", sub = "eq_sub_ring_wisdom" },
		},
		{
			name = "ミラ",
			gender = "f",
			appearanceId = "chr_f_nor_mag_01",
			jobId = "job_priest",
			baseStats = { str = 8, mag = 14, agi = 11, dex = 10, hp = 46 },
			giftIds = { "gift_lucky" },
			equipment = { weapon = "eq_wpn_mace", armor = "eq_arm_vestment", sub = "eq_sub_ring_wisdom" },
		},
	},
}
