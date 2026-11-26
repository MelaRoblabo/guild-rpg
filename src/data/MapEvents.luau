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
	-- 地図の草地に散らした14か所（D-276。毎回この中から等確率で1つ）。並び順が EventPlace01〜14
	places = {
		{ id = "mev_place_1", distance = 4.1 }, -- 北の草地（約65スタッド）
		{ id = "mev_place_2", distance = 3.7 }, -- 北西の草地（雪山の東）
		{ id = "mev_place_3", distance = 3.6 }, -- 北東の草地（森の西）
		{ id = "mev_place_4", distance = 1.6 }, -- 荒れ地と高台の間
		{ id = "mev_place_5", distance = 4.8 }, -- 東の海辺の草地
		{ id = "mev_place_6", distance = 3.7 }, -- 森と湖の間
		{ id = "mev_place_7", distance = 1.9 }, -- 南の畑
		{ id = "mev_place_8", distance = 2.1 }, -- 荒れ野と沼の間
		{ id = "mev_place_9", distance = 4.0 }, -- 西の海辺の草地
		{ id = "mev_place_10", distance = 5.0 }, -- 南の海辺の草地
		{ id = "mev_place_11", distance = 4.6 }, -- 南西の草地
		{ id = "mev_place_12", distance = 3.7 }, -- 草原と峡谷の間
		{ id = "mev_place_13", distance = 2.0 }, -- 川沿い（高台の南）
		{ id = "mev_place_14", distance = 3.6 }, -- 湖と峡谷の間
	},
}
