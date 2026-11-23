--!strict
-- プレイ時間の段階（D-154、docs/system/04_master_data.md §10、06章 §20）
-- 今日のオンラインの合計（日の区切りで 0 に戻す。1日 Constants.playtimeDailyCapSeconds まで）が minutes に届いたら、
-- その段階の報酬を受け取り箱へ入れる。宝箱は特別な宝箱 special:playtime（D-171）
-- 各行：minutes（昇順）, rewards（形は Quests と同じ）。報酬の量はすべて仮（M7b-6）

local PLAYTIME_CHEST = "special:playtime"

return {
	{ minutes = 5, rewards = { gold = 100 } }, -- 仮（M7b-6）
	{ minutes = 10, rewards = { chests = { { pileKey = PLAYTIME_CHEST, count = 1 } } } }, -- 仮
	{ minutes = 20, rewards = { gold = 200 } }, -- 仮
	{ minutes = 30, rewards = { chests = { { pileKey = PLAYTIME_CHEST, count = 1 } } } }, -- 仮
	{ minutes = 45, rewards = { gold = 300 } }, -- 仮
	{ minutes = 60, rewards = { chests = { { pileKey = PLAYTIME_CHEST, count = 2 } } } }, -- 仮
	{ minutes = 90, rewards = { gold = 500 } }, -- 仮
	{ minutes = 120, rewards = { chests = { { pileKey = PLAYTIME_CHEST, count = 2 } }, gold = 500 } }, -- 仮
}
