--!strict
-- クエストのお題（D-153, D-179、docs/system/04_master_data.md §9、06章 §15）
-- 各行：id, period（daily / weekly）, kind, amountPerParty, rewards
-- kind：expeditions（オンライン中の出発）/ chestsOpened（宝箱を開けた数）/ hires（雇用）/
--       trainings（トレーニングの回数）/ clears（踏破）/ rebirths（転生。weekly のみ）
-- 量 = amountPerParty × 解放済みのパーティ数（06章 §15）
-- rewards：{ goldMult?, items? = { [itemId] = 数 }, chests? = { { pileKey, count, rank? } } }（rank を省くと SpecialChests の表で抽選）
--   goldMult：ゴールドの係数。ゴールド = floor(踏破した一番深いダンジョンの rewardGoldBase × goldMult)（D-190、06章 §22）。
--             受け取り箱へ入れたときの踏破で決める。固定額のゴールドは置かない
-- 報酬は達成したときに受け取り箱へ入る（D-164）。全部達成のボーナスは Constants.questDailyBonus / questWeeklyBonus
-- お題の候補・量は仮（M7b-6）。報酬の量は M7b-6 の自動プレイで入手先の配分（D-160）に合わせた（docs/reports/M7b6_balance.md）
--   どのお題も同じ報酬（期間ごと）。チケット・ゴールド・宝箱の割合（D-160, D-200）に合わせた。
--   指南書・手鏡・ロケットはデイリーのお題ごとにロケット1つ、ウィークリーのお題ごとに手鏡とロケット1つずつ（D-293・D-298：クエストから1日約4個。MB-5）

local QUEST_CHEST = "special:quest"

-- デイリーのお題1つの報酬（M7b-6。ロケットは MB-5）
local DAILY_REWARDS = {
	goldMult = 30,
	chests = { { pileKey = QUEST_CHEST, count = 60 } },
	items = { itm_slot_ticket = 6, itm_potion_appearance_keep = 1 },
}
-- ウィークリーのお題1つの報酬（M7b-6。手鏡・ロケットは MB-5）
local WEEKLY_REWARDS = {
	goldMult = 120,
	chests = { { pileKey = QUEST_CHEST, count = 350 } },
	items = { itm_slot_ticket = 18, itm_potion_appearance_change = 1, itm_potion_appearance_keep = 1 },
}

return {
	-- デイリー（お題・量は仮。M7b-6）
	{
		id = "qst_daily_expeditions",
		period = "daily",
		kind = "expeditions",
		nameEn = "Send expeditions", -- D-233 ①
		amountPerParty = 10,
		rewards = DAILY_REWARDS,
	},
	{
		id = "qst_daily_chests",
		period = "daily",
		kind = "chestsOpened",
		nameEn = "Open chests", -- D-233 ①
		amountPerParty = 10,
		rewards = DAILY_REWARDS,
	},
	{
		id = "qst_daily_hires",
		period = "daily",
		kind = "hires",
		nameEn = "Hire adventurers", -- D-233 ①
		amountPerParty = 1,
		rewards = DAILY_REWARDS,
	},
	{
		id = "qst_daily_trainings",
		period = "daily",
		kind = "trainings",
		nameEn = "Train adventurers", -- D-233 ①
		amountPerParty = 5,
		rewards = DAILY_REWARDS,
	},
	{
		id = "qst_daily_clears",
		period = "daily",
		kind = "clears",
		nameEn = "Clear dungeons", -- D-233 ①
		amountPerParty = 5,
		rewards = DAILY_REWARDS,
	},
	-- ウィークリー（お題・量は仮。M7b-6）
	{
		id = "qst_weekly_expeditions",
		period = "weekly",
		kind = "expeditions",
		nameEn = "Send expeditions", -- D-233 ①
		amountPerParty = 50,
		rewards = WEEKLY_REWARDS,
	},
	{
		id = "qst_weekly_chests",
		period = "weekly",
		kind = "chestsOpened",
		nameEn = "Open chests", -- D-233 ①
		amountPerParty = 50,
		rewards = WEEKLY_REWARDS,
	},
	{
		id = "qst_weekly_hires",
		period = "weekly",
		kind = "hires",
		nameEn = "Hire adventurers", -- D-233 ①
		amountPerParty = 3,
		rewards = WEEKLY_REWARDS,
	},
	{
		id = "qst_weekly_trainings",
		period = "weekly",
		kind = "trainings",
		nameEn = "Train adventurers", -- D-233 ①
		amountPerParty = 25,
		rewards = WEEKLY_REWARDS,
	},
	{
		id = "qst_weekly_clears",
		period = "weekly",
		kind = "clears",
		nameEn = "Clear dungeons", -- D-233 ①
		amountPerParty = 25,
		rewards = WEEKLY_REWARDS,
	},
	{
		id = "qst_weekly_rebirths",
		period = "weekly",
		kind = "rebirths",
		nameEn = "Rebirth", -- D-233 ①
		amountPerParty = 1,
		rewards = WEEKLY_REWARDS,
	},
}
