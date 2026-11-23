--!strict
-- ログインボーナスのカレンダー（D-155, D-169、docs/system/04_master_data.md §10、06章 §20）
-- ログインした日数で進む7日一巡（途切れても戻らない）。
-- days：1〜6日目の報酬（rewards の形は Quests と同じ。ゴールドは goldMult：D-190）。量は M7b-6 の自動プレイで入手先の配分（D-160）に合わせた（docs/reports/M7b6_balance.md）
-- 7日目：Uniques の acquire = "login" のユニークを loginOrder の順に1周に1人。
--   ログイン用のユニークがいない・その周のユニークを持っている（受け取り箱に届いている）・一巡した後は fallback
-- ログイン用のユニークの中身（誰か）は未決（Q-025）。Uniques に acquire = "login" の行はまだ置かない

local LOGIN_CHEST = "special:login"

return {
	days = {
		{ goldMult = 120, items = { itm_slot_ticket = 5 } }, -- 1日目（M7b-6）
		{ goldMult = 40, chests = { { pileKey = LOGIN_CHEST, count = 500 } }, items = { itm_slot_ticket = 5 } }, -- 2日目
		{ items = { itm_slot_ticket = 20 } }, -- 3日目
		{ goldMult = 240, items = { itm_slot_ticket = 5 } }, -- 4日目
		{
			goldMult = 50,
			items = { itm_slot_ticket = 5, itm_potion_appearance_change = 1, itm_potion_appearance_keep = 1 },
		}, -- 5日目（ポーションは量を優先：D-201）
		{ goldMult = 60, chests = { { pileKey = LOGIN_CHEST, count = 800 } }, items = { itm_slot_ticket = 10 } }, -- 6日目
	},
	-- 7日目のユニークがいない・持っている・一巡した後：レアな宝箱＋チケット（D-155）。量は M7b-6
	fallback = {
		chests = { { pileKey = LOGIN_CHEST, rank = 3, count = 50 } },
		items = { itm_slot_ticket = 20 },
	},
}
