--!strict
-- メイン画面のマップに出す、同じサーバーの他のプレイヤーの馬車（D-027・D-108・D-127・D-151・D-213 ⑮）。
--   - 全員分を薄く、自分の馬車より小さく・少し下にずらして出す（自分の馬車とダンジョンが前：タップの優先は
--     ダンジョン＞自分の馬車＞他人の馬車）。番号は出さず、プレイヤーのアバターの顔を小さく載せる。
--   - 重なる他人の馬車は「＋N」にまとめる（D-127）。触ると S-14（まとめなら最初の馬車、面の上で切り替え）。
--   - 設定の「他プレイヤーの馬車」がオフなら出さない（D-117・S-61）。

local Players = game:GetService("Players")

local Game = require("@game/ReplicatedStorage/Core/Game")
local Components = require("../ui/Components")
local Create = require("../ui/Create")
local HubState = require("./HubState")
local MapLayout = require("./MapLayout")
local Nav = require("../ui/Nav")
local OtherCarts = require("../world/OtherCarts")
local Session = require("../Session")
local Tokens = require("../ui/Tokens")
local master = require("../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local SIZE = 44 -- 自分の馬車（66×50）より小さく
local OFFSET_Y = 60 -- 自分の馬車と重ならないよう、線の少し下に出す
local CLUSTER_RADIUS = 36

local WorldCarts = {}

local layer: Frame? = nil
local pool: { TextButton } = {}
local thumbs: { [number]: string } = {}

local function thumbOf(userId: number): string
	local t = thumbs[userId]
	if t then
		return t
	end
	thumbs[userId] = ""
	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)
		if ok then
			thumbs[userId] = url
		end
	end)
	return ""
end

local function cartAt(i: number): TextButton
	local b = pool[i]
	if b then
		return b
	end
	b = new("TextButton", {
		Name = "OtherCart" .. i,
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundColor3 = C.ch28,
		BackgroundTransparency = 0.35,
		ZIndex = 4,
		[CHILDREN] = { Components.corner(10), Components.stroke(C.ch05, 2, 0.4) },
		Parent = layer,
	})
	new("ImageLabel", {
		Name = "Face",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(SIZE - 10, SIZE - 10),
		BackgroundTransparency = 1,
		ImageTransparency = 0.3,
		ZIndex = 5,
		[CHILDREN] = { Components.corner((SIZE - 10) / 2) },
		Parent = b,
	})
	local more = Components.text({ text = "", size = 21, color = C.inkLight, font = Tokens.font.number, stroke = true })
	more.Name = "More"
	more.AnchorPoint = Vector2.new(0.5, 0)
	more.Position = UDim2.new(0.5, 0, 1, 2)
	more.ZIndex = 5
	more.Parent = b
	b.Activated:Connect(function()
		local keys = (b :: any):GetAttribute("Keys")
		if type(keys) == "string" and keys ~= "" then
			local list = {}
			for k in string.gmatch(keys, "[^;]+") do
				local u, p = string.match(k, "(%d+):(%d+)")
				table.insert(list, { userId = tonumber(u), partyIndex = tonumber(p) })
			end
			Nav.open("OtherParty", { list = list })
		end
	end)
	pool[i] = b
	return b
end

function WorldCarts.mount(mapContent: Frame)
	layer = new("Frame", {
		Name = "OtherCarts",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = mapContent,
	})
end

-- メイン画面の refreshMoving から呼ぶ
function WorldCarts.refresh(view: any)
	local l = layer
	if l == nil then
		return
	end
	local show = view ~= nil and Game.query.preferences(view, master).otherCarts
	l.Visible = show
	if not show then
		return
	end
	local now = Session.now()
	local points = {}
	local me = Players.LocalPlayer and Players.LocalPlayer.UserId
	for userId, info in Session.world do
		if userId ~= me then
			for _, p in info.parties or {} do
				local pos = OtherCarts.position(p, now)
				local index = HubState.dungeonIndex(p.dungeonId)
				if pos and index then
					local at = MapLayout.wagon(index, pos.along)
					table.insert(points, { x = at.x, y = at.y + OFFSET_Y, key = `{userId}:{p.index}` })
				end
			end
		end
	end
	local groups = OtherCarts.cluster(points, CLUSTER_RADIUS)
	for i, g in groups do
		local b = cartAt(i)
		b.Visible = true
		b.Position = UDim2.fromOffset(g.x, g.y)
		b:SetAttribute("Keys", table.concat(g.keys, ";"))
		local first = tonumber(string.match(g.keys[1], "^(%d+)")) or 0
		local face = b:FindFirstChild("Face") :: ImageLabel
		face.Image = thumbOf(first)
		local more = b:FindFirstChild("More") :: TextLabel
		more.Text = if #g.keys > 1 then "+" .. (#g.keys - 1) else ""
	end
	for i = #groups + 1, #pool do
		pool[i].Visible = false
	end
end

return WorldCarts
