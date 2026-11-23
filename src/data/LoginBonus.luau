--!strict
-- ログインボーナスのカレンダー（D-155, D-169、docs/system/04_master_data.md §10、06章 §20）
-- ログインした日数で進む7日一巡（途切れても戻らない）。
-- days：1〜6日目の報酬（rewards の形は Quests と同じ。ゴールドは goldMult：D-190）。量はすべて仮（M7b-6）
-- 7日目：Uniques の acquire = "login" のユニークを loginOrder の順に1周に1人。
--   ログイン用のユニークがいない・その周のユニークを持っている（受け取り箱に届いている）・一巡した後は fallback
-- ログイン用のユニークの中身（誰か）は未決（Q-025）。Uniques に acquire = "login" の行はまだ置かない

local LOGIN_CHEST = "special:login"

return {
	days = {
		{ goldMult = 3 }, -- 1日目（仮。M7b-6）
		{ chests = { { pileKey = LOGIN_CHEST, count = 1 } } }, -- 2日目（仮）
		{ items = { itm_slot_ticket = 1 } }, -- 3日目（仮）
		{ goldMult = 6 }, -- 4日目（仮）
		{ items = { itm_potion_appearance_change = 1 } }, -- 5日目（仮）
		{ chests = { { pileKey = LOGIN_CHEST, count = 2 } } }, -- 6日目（仮）
	},
	-- 7日目のユニークがいない・持っている・一巡した後：レアな宝箱＋チケット（D-155）。量は仮（M7b-6）
	fallback = {
		chests = { { pileKey = LOGIN_CHEST, rank = 3, count = 1 } },
		items = { itm_slot_ticket = 1 },
	},
}
