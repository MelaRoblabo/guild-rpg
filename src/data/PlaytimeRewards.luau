--!strict
-- プレイ時間の段階（D-154、docs/system/04_master_data.md §10、06章 §20）
-- 今日のオンラインの合計（日の区切りで 0 に戻す。1日 Constants.playtimeDailyCapSeconds まで）が minutes に届いたら、
-- その段階の報酬を受け取り箱へ入れる。宝箱は特別な宝箱 special:playtime（D-171）
-- 各行：minutes（昇順）, rewards（形は Quests と同じ。ゴールドは goldMult：D-190）。報酬の量は M7b-6 で配分（D-160, D-200：プレイ時間の列はゴールド10・宝箱5・チケット5%）に寄せた。
-- ゴールドはコアで配分の約10%（D-205：D-154 の「数%」より D-160 を優先。1段あたりオンライン1時間の直接のゴールドの約10%）

local PLAYTIME_CHEST = "special:playtime"

return {
	{ minutes = 5, rewards = { goldMult = 16 } }, -- M7b-6
	{ minutes = 10, rewards = { goldMult = 16, chests = { { pileKey = PLAYTIME_CHEST, count = 30 } } } },
	{ minutes = 20, rewards = { goldMult = 20 } },
	{
		minutes = 30,
		rewards = {
			goldMult = 20,
			chests = { { pileKey = PLAYTIME_CHEST, count = 40 } },
			items = { itm_slot_ticket = 1 },
		},
	},
	{ minutes = 45, rewards = { goldMult = 20 } },
	{
		minutes = 60,
		rewards = {
			goldMult = 20,
			chests = { { pileKey = PLAYTIME_CHEST, count = 60 } },
			items = { itm_slot_ticket = 1 },
		},
	},
	{ minutes = 90, rewards = { goldMult = 24 } },
	{
		minutes = 120,
		rewards = {
			goldMult = 24,
			chests = { { pileKey = PLAYTIME_CHEST, count = 80 } },
			items = { itm_slot_ticket = 2 },
		},
	},
}
