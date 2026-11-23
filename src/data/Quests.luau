--!strict
-- クエストのお題（D-153, D-179、docs/system/04_master_data.md §9、06章 §15）
-- 各行：id, period（daily / weekly）, kind, amountPerParty, rewards
-- kind：expeditions（オンライン中の出発）/ chestsOpened（宝箱を開けた数）/ hires（雇用）/
--       trainings（トレーニングの回数）/ clears（踏破）/ rebirths（転生。weekly のみ）
-- 量 = amountPerParty × 解放済みのパーティ数（06章 §15）
-- rewards：{ gold?, items? = { [itemId] = 数 }, chests? = { { pileKey, count, rank? } } }（rank を省くと SpecialChests の表で抽選）
-- 報酬は達成したときに受け取り箱へ入る（D-164）。全部達成のボーナスは Constants.questDailyBonus / questWeeklyBonus
-- お題の候補・量・報酬の量はすべて仮（M7b-6）

local QUEST_CHEST = "special:quest"

return {
	-- デイリー（仮。M7b-6）
	{
		id = "qst_daily_expeditions",
		period = "daily",
		kind = "expeditions",
		amountPerParty = 10,
		rewards = { gold = 500, chests = { { pileKey = QUEST_CHEST, count = 1 } } },
	},
	{
		id = "qst_daily_chests",
		period = "daily",
		kind = "chestsOpened",
		amountPerParty = 10,
		rewards = { gold = 500, chests = { { pileKey = QUEST_CHEST, count = 1 } } },
	},
	{
		id = "qst_daily_hires",
		period = "daily",
		kind = "hires",
		amountPerParty = 1,
		rewards = { items = { itm_slot_ticket = 1 } },
	},
	{
		id = "qst_daily_trainings",
		period = "daily",
		kind = "trainings",
		amountPerParty = 5,
		rewards = { items = { itm_slot_ticket = 1 } },
	},
	{
		id = "qst_daily_clears",
		period = "daily",
		kind = "clears",
		amountPerParty = 5,
		rewards = { gold = 500, chests = { { pileKey = QUEST_CHEST, count = 1 } } },
	},
	-- ウィークリー（仮。M7b-6）
	{
		id = "qst_weekly_expeditions",
		period = "weekly",
		kind = "expeditions",
		amountPerParty = 50,
		rewards = { gold = 3000, chests = { { pileKey = QUEST_CHEST, count = 3 } }, items = { itm_slot_ticket = 1 } },
	},
	{
		id = "qst_weekly_chests",
		period = "weekly",
		kind = "chestsOpened",
		amountPerParty = 50,
		rewards = { gold = 3000, chests = { { pileKey = QUEST_CHEST, count = 3 } }, items = { itm_slot_ticket = 1 } },
	},
	{
		id = "qst_weekly_hires",
		period = "weekly",
		kind = "hires",
		amountPerParty = 3,
		rewards = { items = { itm_slot_ticket = 2 } },
	},
	{
		id = "qst_weekly_trainings",
		period = "weekly",
		kind = "trainings",
		amountPerParty = 25,
		rewards = { items = { itm_slot_ticket = 2 } },
	},
	{
		id = "qst_weekly_clears",
		period = "weekly",
		kind = "clears",
		amountPerParty = 25,
		rewards = { gold = 3000, chests = { { pileKey = QUEST_CHEST, count = 3 } }, items = { itm_slot_ticket = 1 } },
	},
	{
		id = "qst_weekly_rebirths",
		period = "weekly",
		kind = "rebirths",
		amountPerParty = 1,
		rewards = { items = { itm_slot_ticket = 2, itm_potion_appearance_change = 1 } },
	},
}
