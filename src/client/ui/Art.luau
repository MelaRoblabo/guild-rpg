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

-- 宝箱（レアリティの rank。open＝開いた箱）
function Art.chest(rank: number?, open: boolean?): string?
	local c = if rank and images.chests then images.chests[rank] else nil
	if c == nil then
		return nil
	end
	return if open then c.open else c.closed
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
