--!strict
-- 自動プレイの「1日の流れ」の設定（docs/system/09_cli_sim_autoplay.md §3、D-161）
-- ゲームの数値ではなく、試し方の設定。ログインの回数・時刻は仮（M7b-6）。
--   at      ログインする時刻（その日の 0時からの時間。時刻は tzOffsetHours の地域の時計）
--   minutes そのログインで遊ぶ分数
-- 1日のオンラインの合計は D-161 の型（ライト約0.6・コア約2.5・ヘビー約6時間）に合わせる。

local Schedule = {}

-- 時計の地域（日本時間）。ゲームの日の区切りは UTC 0時＝日本の朝9時（06章 §11、D-168）
Schedule.tzOffsetHours = 9

-- 仮（M7b-6）。朝・昼・夜に分けて遊ぶ想定
Schedule.profiles = {
	light = { -- 合計 36分（約0.6時間）
		{ at = 8.0, minutes = 10 },
		{ at = 12.5, minutes = 10 },
		{ at = 21.0, minutes = 16 },
	},
	core = { -- 合計 150分（2.5時間）
		{ at = 7.5, minutes = 20 },
		{ at = 12.25, minutes = 25 },
		{ at = 19.0, minutes = 60 },
		{ at = 22.5, minutes = 45 },
	},
	heavy = { -- 合計 360分（6時間）
		{ at = 7.0, minutes = 30 },
		{ at = 12.0, minutes = 45 },
		{ at = 15.0, minutes = 60 },
		{ at = 19.0, minutes = 120 },
		{ at = 22.5, minutes = 105 },
	},
}

-- 友達がいる想定（ctx.friendCount。フレンドボタン：D-157）。初期値は「いない」。--friends で変える
Schedule.friendCount = 0

-- 方針の行動の設定（tools/autoplay/Policy.luau の Policy.configure に入れる）
Schedule.behavior = {
	mapEvents = true, -- マップイベント（レアダンジョン・レイド）に空いているパーティを向かわせる
	merchant = true, -- 旅の商人で、誰かの今の装備より良い品を買う
	merchantBudgetShare = 0.3, -- 商人に使うのは「転生の備え」を除いた所持金のこの割合まで
	bulkSell = true, -- 開封のあとに一括売却（D-167）
}

return Schedule
