--!strict
-- アイテム（ゲーム仕様書06章 §5、D-058）
-- kind: ticket / potion_appearance_change / potion_appearance_keep / potion_job / sellable
-- 探索ログの報酬（アイテムイベント）が参照するため M1 で最小セットを用意する

return {
	{ id = "itm_slot_ticket", name = "ステータススロットチケット", kind = "ticket", sellPrice = 0 },
	{
		id = "itm_potion_appearance_change",
		name = "見た目変更ポーション",
		kind = "potion_appearance_change",
		sellPrice = 0,
	},
	{
		id = "itm_potion_appearance_keep",
		name = "見た目維持ポーション",
		kind = "potion_appearance_keep",
		sellPrice = 0,
	},
	{
		id = "itm_potion_job_warrior",
		name = "転職ポーション（戦士）",
		kind = "potion_job",
		jobId = "job_warrior",
		sellPrice = 0,
	},
	{
		id = "itm_potion_job_thief",
		name = "転職ポーション（盗賊）",
		kind = "potion_job",
		jobId = "job_thief",
		sellPrice = 0,
	},
	{
		id = "itm_potion_job_mage",
		name = "転職ポーション（魔法使い）",
		kind = "potion_job",
		jobId = "job_mage",
		sellPrice = 0,
	},
	{
		id = "itm_potion_job_priest",
		name = "転職ポーション（僧侶）",
		kind = "potion_job",
		jobId = "job_priest",
		sellPrice = 0,
	},
	{
		id = "itm_potion_job_knight",
		name = "転職ポーション（ナイト）",
		kind = "potion_job",
		jobId = "job_knight",
		sellPrice = 0,
	},
	{
		id = "itm_potion_job_ninja",
		name = "転職ポーション（忍者）",
		kind = "potion_job",
		jobId = "job_ninja",
		sellPrice = 0,
	},
	{
		id = "itm_potion_job_sage",
		name = "転職ポーション（賢者）",
		kind = "potion_job",
		jobId = "job_sage",
		sellPrice = 0,
	},
	{
		id = "itm_potion_job_bishop",
		name = "転職ポーション（司祭）",
		kind = "potion_job",
		jobId = "job_bishop",
		sellPrice = 0,
	},
	-- 売却用（仮）
	{ id = "itm_bone_fragment", name = "古びた骨片", kind = "sellable", sellPrice = 12 },
	{ id = "itm_old_gear", name = "古代の歯車", kind = "sellable", sellPrice = 18 },
	{ id = "itm_magic_shard", name = "魔力の欠片", kind = "sellable", sellPrice = 24 },
	{ id = "itm_knight_crest", name = "騎士の紋章", kind = "sellable", sellPrice = 32 },
}
