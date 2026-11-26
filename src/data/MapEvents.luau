--!strict
-- マップイベント（D-152、docs/system/04_master_data.md §12、06章 §12）
-- kinds：種類（割合は Constants.mapEventKindWeights）。kind は処理の種類
-- places：出る場所の一覧。どこに出るかは時間帯ごとに全員共通で抽選する（calendarSeed）
--   マップ上の位置は Studio の EventPlace01〜（並び順）。distance はギルドの街からの距離（D-274：商人への片道秒 =
--   ceil(distance × travelSecondsPerDistance)）。3D の地図の距離（スタッド）÷ 16 を目安にした（ダンジョン01：約24スタッド ≒ 1.5）

return {
	kinds = {
		{ id = "mev_rare_dungeon", kind = "rareDungeon" }, -- レアダンジョン（DispatchEvent）
		{ id = "mev_raid", kind = "raid" }, -- レイドボス（DispatchEvent。まず自分専用）
		{ id = "mev_merchant", kind = "merchant" }, -- 旅の商人（BuyFromMerchant）
	},
	places = {
		{ id = "mev_place_1", distance = 3.4 }, -- 約55スタッド
		{ id = "mev_place_2", distance = 3.3 }, -- 約53スタッド
		{ id = "mev_place_3", distance = 2.1 }, -- 約34スタッド
		{ id = "mev_place_4", distance = 5.2 }, -- 約83スタッド
	},
}
