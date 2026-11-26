--!strict
-- マップの配置（D-212・D-257：世界の大きさとダンジョンの位置はワールドマップの絵に合わせて決めた）。
-- ワールドマップの絵に描かれた場所に合わせる。純粋な関数（Lune でテストする）。

local MapLayout = {}

export type Point = { x: number, y: number }

-- ワールドマップの絵（1024×720 を5枚つなぐ。15章 §9）に合わせた位置（基準の単位。2026-11-25、D-212・D-214 ⑪）。
-- ダンジョンの丸は、絵に描かれたその場所の足もとに置き、絵を隠さない（上の帯にかからない高さ）
local GUILD: Point = { x = 150, y = 300 } -- 左端の草原、道の始まり
local DUNGEONS: { Point } = {
	{ x = 418, y = 215 }, -- 1 古い墓地：丘の上の霊廟の下
	{ x = 880, y = 545 }, -- 2 罠の遺跡：密林の石のアーチの前
	{ x = 1133, y = 335 }, -- 3 封印の塔：塔の丘のふもと。右上の Friends にかからない高さ（D-269 ②）
	{ x = 1435, y = 490 }, -- 4 騎士の古城：城の下の崖
	{ x = 1777, y = 255 }, -- 5 水没神殿：湖に沈んだ円堂の手前
	{ x = 2093, y = 430 }, -- 6 霧の大森林
	{ x = 2301, y = 230 }, -- 7 地下大迷宮：崖の洞窟の入口
	{ x = 2644, y = 610 }, -- 8 呪われた修道院：廃墟の前の道
	{ x = 2910, y = 205 }, -- 9 鋼鉄の要塞：歯車の工場の足もと
	{ x = 3243, y = 615 }, -- 10 竜の巣：竜の骨の火山のふもと
	{ x = 3539, y = 205 }, -- 11 魔界の門：角の門の足もと
	{ x = 3920, y = 520 }, -- 12 天空の玉座：雲に浮かぶ円形の広場
}
local MARGIN_RIGHT = 360
local STEP_X = 300 -- 表にない13番目以降のダンジョンを右へ並べる間（ダンジョンを足したとき用）

function MapLayout.guild(): Point
	return GUILD
end

-- index 番目（1〜）のダンジョンの位置
function MapLayout.dungeon(index: number): Point
	local p = DUNGEONS[index]
	if p then
		return p
	end
	local last = DUNGEONS[#DUNGEONS]
	return { x = last.x + STEP_X * (index - #DUNGEONS), y = DUNGEONS[((index - 1) % #DUNGEONS) + 1].y }
end

-- マップイベントの場所（D-152・D-215 ③）。MapEvents.places の順。絵の開けた所で、ダンジョンの丸と重ならない
local EVENT_PLACES: { Point } = {
	{ x = 655, y = 605 }, -- 密林の道
	{ x = 1150, y = 470 }, -- 塔の下の畑（III を下げた分だけ下へ：D-269 ②）
	{ x = 1600, y = 560 }, -- 古城の先の森
	{ x = 2770, y = 340 }, -- 要塞の手前の野原（上の帯より下：D-251）
}

function MapLayout.eventPlace(index: number): Point
	return EVENT_PLACES[((index - 1) % #EVENT_PLACES) + 1]
end

-- マップ全体の幅（基準の単位）。画面より広くスクロールする（D-212）。絵があるときは画面で絵の幅まで広げる
function MapLayout.width(dungeonCount: number): number
	return MapLayout.dungeon(dungeonCount).x + MARGIN_RIGHT
end

-- 馬車の位置：ギルド（along = 0）とダンジョン（along = 1）のあいだ
function MapLayout.wagon(dungeonIndex: number?, along: number): Point
	if dungeonIndex == nil then
		return GUILD
	end
	local d = MapLayout.dungeon(dungeonIndex)
	local a = math.clamp(along, 0, 1)
	return { x = GUILD.x + (d.x - GUILD.x) * a, y = GUILD.y + (d.y - GUILD.y) * a }
end

-- カメラを x に寄せたときのスクロール位置（はみ出さないよう端で止める）
function MapLayout.cameraX(targetX: number, viewWidth: number, mapWidth: number): number
	return math.clamp(targetX - viewWidth / 2, 0, math.max(0, mapWidth - viewWidth))
end

return MapLayout
