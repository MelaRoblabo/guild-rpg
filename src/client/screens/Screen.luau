--!strict
-- 画面いっぱいの画面で共有する骨組み（雇用・宝箱・転生）。
--   - 場面（仮の絵）、帯のすぐ下の右上の ×（D-222）、右下のボタンの並び（D-219 ③）。

local Components = require("../ui/Components")
local Create = require("../ui/Create")
local Root = require("../ui/Root")
local Tokens = require("../ui/Tokens")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local Screen = {}

-- 画面いっぱいの場面（仮の絵：ギルドの室内の暖かい暗がり）
function Screen.scene(name: string): Frame
	return new("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		[CHILDREN] = { Components.gradient(C.ch17, C.ch05) },
	})
end

-- 右上の ×（画面いっぱいの画面は帯のすぐ下の右上：D-222）
function Screen.closeTopRight(parent: Frame, onClick: () -> ()): TextButton
	local close = Components.closeButton(onClick)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -40, 0, Root.bandBottom() + 12)
	close.Parent = parent
	return close
end

-- 右下の並び（右から順に置く。LayoutOrder の大きいものほど右）
function Screen.actionRow(parent: Frame): Frame
	return new("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -40, 1, -24),
		Size = UDim2.fromOffset(0, 85),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		ZIndex = 20,
		[CHILDREN] = {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				Padding = UDim.new(0, 16),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = parent,
	})
end

return Screen
