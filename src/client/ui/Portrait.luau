--!strict
-- 冒険者のバストアップ（D-042・15章 §2）。見た目のIDからマスターデータの imageId を引き、枠いっぱいに入れる。
-- 画像がまだない見た目（ユニークなど）は何もしないので、呼び出し側の仮の印がそのまま残る。

local Create = require("./Create")
local master = require("../Master")

local Portrait = {}

function Portrait.image(appearanceId: string?): string?
	if appearanceId == nil then
		return nil
	end
	local a = master.appearances[appearanceId]
	if a then
		return a.imageId
	end
	-- ユニークは見た目の表になく、Images.uniques にある（D-055）
	local images = master.images
	return if images and images.uniques then images.uniques[appearanceId] else nil
end

-- frame に画像を入れる。入れたら true（呼び出し側は仮の印を隠す）。
-- dim：戦闘不能など、暗く見せるとき
function Portrait.fill(frame: GuiObject, appearanceId: string?, dim: boolean?): boolean
	local img = Portrait.image(appearanceId)
	if img == nil then
		return false
	end
	local old = frame:FindFirstChild("Bust")
	if old then
		old:Destroy()
	end
	local bust: ImageLabel = Create.new("ImageLabel", {
		Name = "Bust",
		Image = img,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Fit,
		ImageTransparency = if dim then 0.5 else 0,
		ZIndex = frame.ZIndex + 1,
		Parent = frame,
	})
	-- 枠の角の丸みを画像にも付ける（丸い枠からはみ出さないように）
	local corner = frame:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = bust
	end
	return true
end

return Portrait
