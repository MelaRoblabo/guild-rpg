--!strict
-- プレイ時間の段階（D-154、docs/system/04_master_data.md §10、06章 §20）
-- 今日のオンラインの合計（日の区切りで 0 に戻す。1日 Constants.playtimeDailyCapSeconds まで）が minutes に届いたら、
-- その段階の報酬を受け取り箱へ入れる。宝箱は特別な宝箱 special:playtime（D-171）
-- 各行：minutes（昇順）, rewards（形は Quests と同じ。ゴールドは goldMult：D-190）。報酬の量は M7b-6 で配分（D-160, D-200：プレイ時間の列はゴールド10・宝箱5・チケット5%）に寄せた。
-- ゴールドは1段あたりオンライン1時間の直接のゴールドの約5%（D-154 の「数%」の上の方）にとどめた（docs/reports/M7b6_balance.md）

local PLAYTIME_CHEST = "special:playtime"

return {
	{ minutes = 5, rewards = { goldMult = 8 } }, -- M7b-6
	{ minutes = 10, rewards = { goldMult = 8, chests = { { pileKey = PLAYTIME_CHEST, count = 30 } } } },
	{ minutes = 20, rewards = { goldMult = 10 } },
	{
		minutes = 30,
		rewards = {
			goldMult = 10,
			chests = { { pileKey = PLAYTIME_CHEST, count = 40 } },
			items = { itm_slot_ticket = 1 },
		},
	},
	{ minutes = 45, rewards = { goldMult = 10 } },
	{
		minutes = 60,
		rewards = {
			goldMult = 10,
			chests = { { pileKey = PLAYTIME_CHEST, count = 60 } },
			items = { itm_slot_ticket = 1 },
		},
	},
	{ minutes = 90, rewards = { goldMult = 12 } },
	{
		minutes = 120,
		rewards = {
			goldMult = 12,
			chests = { { pileKey = PLAYTIME_CHEST, count = 80 } },
			items = { itm_slot_ticket = 2 },
		},
	},
}
