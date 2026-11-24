--!strict
-- ユニークキャラ（ゲーム仕様書02章 §2、D-055、企画書§16.7 仮採用）
-- 名前・見た目・職業・ステータス・ギフトが固定。面接の引き直しはない（固定値）
-- acquire: "visitor"＝雇用候補に「特別な訪問者」として出る（Constants.specialVisitorChance）
--          "firstClear:<dungeonId>"＝そのダンジョンの初回踏破報酬（M5 で実装）
-- jobChange: "line"＝同じ系統内のみ転職可 / "none"＝転職不可（固有職業）
-- 試作用の3体（仮）

return {
	{
		id = "uni_garrett",
		name = "Old Garrett",
		gender = "m",
		appearanceId = "uni_garrett",
		jobId = "job_warrior",
		baseStats = { str = 22, mag = 6, agi = 14, dex = 14, hp = 70 },
		giftIds = { "gift_sturdy" },
		acquire = "visitor",
		jobChange = "line",
	},
	{
		id = "uni_lyra",
		name = "Stargazer Lyra",
		gender = "f",
		appearanceId = "uni_lyra",
		jobId = "job_mage",
		baseStats = { str = 6, mag = 24, agi = 16, dex = 16, hp = 50 },
		giftIds = { "gift_lucky" },
		acquire = "visitor",
		jobChange = "line",
	},
	{
		id = "uni_bran",
		name = "Silver Bran",
		gender = "m",
		appearanceId = "uni_bran",
		jobId = "job_knight",
		baseStats = { str = 24, mag = 6, agi = 12, dex = 12, hp = 74 },
		giftIds = { "gift_exorcist" },
		acquire = "firstClear:dng_castle",
		jobChange = "none",
	},
}
