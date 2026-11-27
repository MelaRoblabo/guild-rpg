--!strict
-- 絵のアセット（15章 §4）。装備・道具・宝箱・モンスター・ダンジョンの背景の画像を引き、枠に入れる。
-- 冒険者のバストアップは ui/Portrait。画像がないものは何もしないので、呼び出し側の仮の印が残る。

local EquipmentLook = require("@game/ReplicatedStorage/Core/EquipmentLook")
local Create = require("./Create")
local master = require("../Master")

local Art = {}

local images = master.images or {}

function Art.equip(item: any): string?
	if item == nil then
		return nil
	end
	return EquipmentLook.image(item, master)
end

function Art.item(itemId: string?): string?
	return if itemId and images.items then images.items[itemId] else nil
end

function Art.monster(monsterId: string?): string?
	return if monsterId and images.monsters then images.monsters[monsterId] else nil
end

function Art.background(dungeonId: string?): string?
	return if dungeonId and images.backgrounds then images.backgrounds[dungeonId] else nil
end

-- レアダンジョンの中の背景（D-304）
function Art.rareDungeonBackground(): string?
	return if images.eventBackgrounds then images.eventBackgrounds.rareDungeon else nil
end

function Art.gift(giftId: string?): string?
	return if giftId and images.gifts then images.gifts[giftId] else nil
end

function Art.npc(npcId: string): string?
	return if images.npcs then images.npcs[npcId] else nil
end

-- UIアイコン（白1色。色は ImageColor3 で塗る：D-149）。key は Images.ui のキー（例 "guild"）
function Art.ui(key: string): string?
	return if images.ui then images.ui[key] else nil
end

-- ワールドマップの絵（左から順の1024×720）とマップのギルド
function Art.mapTiles(): { string }
	return if images.map and images.map.tiles then images.map.tiles else {}
end

function Art.mapGuild(): string?
	return if images.map then images.map.guild else nil
end

-- 並べる枠（UIListLayout）の中に置く小さな絵（アイコン・メダル）。color を渡すと白1色の絵をその色で塗る
function Art.icon(image: string?, size: number, order: number?, color: Color3?, zIndex: number?): ImageLabel?
	if image == nil then
		return nil
	end
	return Create.new("ImageLabel", {
		Name = "Icon",
		Image = image,
		ImageColor3 = color or Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		ScaleType = Enum.ScaleType.Fit,
		LayoutOrder = order or 0,
		ZIndex = zIndex or 1,
	})
end

-- 宝箱（レアリティの rank。open＝開いた箱）
function Art.chest(rank: number?, open: boolean?): string?
	local c = if rank and images.chests then images.chests[rank] else nil
	if c == nil then
		return nil
	end
	return if open then c.open else c.closed
end

-- 開封の演出で使う宝箱の絵（閉じた・開いた）を先に読み込む（初めて使うときに間に合わず、何も映らないため：D-267）
function Art.preloadChests()
	local list = {}
	for _, c in (images.chests or {}) :: { any } do
		table.insert(list, c.closed)
		table.insert(list, c.open)
	end
	task.spawn(function()
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync(list)
		end)
	end)
end

export type PutOptions = {
	inset: number?, -- 枠の内側の余白（px）
	scaleType: Enum.ScaleType?, -- 既定は Fit（背景は Crop）
	zIndex: number?,
	transparency: number?,
}

-- frame に画像を入れる。入れたら作った ImageLabel を返す（呼び出し側は仮の印を隠す）
function Art.put(frame: GuiObject, image: string?, opts: PutOptions?): ImageLabel?
	if image == nil then
		return nil
	end
	local o: PutOptions = opts or {}
	local old = frame:FindFirstChild("Art")
	if old then
		old:Destroy()
	end
	local inset = o.inset or 0
	local img: ImageLabel = Create.new("ImageLabel", {
		Name = "Art",
		Image = image,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -inset * 2, 1, -inset * 2),
		ScaleType = o.scaleType or Enum.ScaleType.Fit,
		ImageTransparency = o.transparency or 0,
		ZIndex = o.zIndex or (frame.ZIndex + 1),
		Parent = frame,
	})
	local corner = frame:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = img
	end
	return img
end

return Art
