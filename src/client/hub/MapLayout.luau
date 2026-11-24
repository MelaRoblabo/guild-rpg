--!strict
-- マップの仮の配置（D-212・D-214 ⑪：世界の大きさとダンジョンの位置はマップの絵を作るときに決める）。
-- 絵ができるまでは、ギルドを左に置き、ダンジョンを順番に右へ並べる。純粋な関数（Lune でテストする）。

local MapLayout = {}

export type Point = { x: number, y: number }

local GUILD: Point = { x = 260, y = 420 }
local STEP_X = 300 -- ダンジョンどうしの横の間（66px の押せる範囲が重ならない。11章 S-10）
local ROWS_Y = { 300, 520, 360, 560, 280, 480 } -- 縦はばらけさせる（仮）
local MARGIN_RIGHT = 360

function MapLayout.guild(): Point
	return GUILD
end

-- index 番目（1〜）のダンジョンの位置
function MapLayout.dungeon(index: number): Point
	return { x = GUILD.x + STEP_X * index, y = ROWS_Y[((index - 1) % #ROWS_Y) + 1] }
end

-- マップ全体の幅（基準の単位）。画面より広くスクロールする（D-212）
function MapLayout.width(dungeonCount: number): number
	return GUILD.x + STEP_X * dungeonCount + MARGIN_RIGHT
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
