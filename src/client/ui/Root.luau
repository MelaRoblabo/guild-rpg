--!strict
-- 画面の土台（D-210・D-219・D-221、Guild UI roblox.md）。
--   - ScreenGui は端末の欠け（切り欠き・ホームバー）を避ける（ScreenInsets = DeviceSafeInsets）。
--   - 中に基準の単位（1280×720 基準）の Canvas を置き、UIScale で縮める（Layout.compute）。
--   - 横長・縦長の余りは Canvas の幅・高さに回す。部品は Canvas の辺に止める（面は引き伸ばさない）。
--   - Roblox の上の帯（TopbarInset）を基準の単位に直して topBand に持つ。ここより上に押せるものを置かない。

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local Create = require("./Create")
local Layout = require("./Layout")
local Signal = require("./Signal")
local Tokens = require("./Tokens")

local Root = {}

Root.changed = Signal.new() :: Signal.Signal<Layout.Frame>

local gui: ScreenGui = Create.new("ScreenGui", {
	Name = "GuildUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
	DisplayOrder = 10,
})

local uiScale: UIScale = Create.new("UIScale", {})

local canvas: Frame = Create.new("Frame", {
	Name = "Canvas",
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(Tokens.base.width, Tokens.base.height),
	[Create.Children] = { uiScale },
	Parent = gui,
})

Root.gui = gui
Root.canvas = canvas
Root.frame = Layout.compute(
	Tokens.base.width,
	Tokens.base.height,
	{ top = 0, bottom = 0, left = 0, right = 0 },
	0,
	Tokens.base.topBand
)

local function relayout()
	local size = gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local topbar = GuiService.TopbarInset.Height
	local frame =
		Layout.compute(size.X, size.Y, { top = 0, bottom = 0, left = 0, right = 0 }, topbar, Tokens.base.topBand)
	Root.frame = frame
	uiScale.Scale = frame.scale
	canvas.Size = UDim2.fromOffset(frame.width, frame.height)
	Root.changed:fire(frame)
end

gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(relayout)

function Root.mount()
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	task.defer(relayout)
end

-- Roblox の帯の下端（基準の単位）。押せるものはここより下に置く（D-219）
function Root.bandBottom(): number
	return Root.frame.topBand
end

return Root
