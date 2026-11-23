--!strict
-- マップイベント（D-152、docs/system/04_master_data.md §12、06章 §12）
-- kinds：種類（割合は Constants.mapEventKindWeights）。kind は処理の種類
-- places：出る場所の一覧。どこに出るかは時間帯ごとに全員共通で抽選する（calendarSeed）
--   場所の中身（マップ上の位置）は M8 のマップの設計で決める。今は id だけの仮の行

return {
	kinds = {
		{ id = "mev_rare_dungeon", kind = "rareDungeon" }, -- レアダンジョン（DispatchEvent）
		{ id = "mev_raid", kind = "raid" }, -- レイドボス（DispatchEvent。まず自分専用）
		{ id = "mev_merchant", kind = "merchant" }, -- 旅の商人（BuyFromMerchant）
	},
	places = { -- 仮（M8）
		{ id = "mev_place_1" },
		{ id = "mev_place_2" },
		{ id = "mev_place_3" },
		{ id = "mev_place_4" },
	},
}
