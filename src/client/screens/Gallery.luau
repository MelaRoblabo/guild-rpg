--!strict
-- 部品の見本の画面（M8-1 の確かめ用。D-227 ⑤）。ゲームの画面ではない。
-- 雇用の引き直し（S-21d）の形で、羊皮紙の面・題の札・能力の行・ボタン4種・右上の ×・札・吹き出しを並べる。

local Components = require("../ui/Components")
local Create = require("../ui/Create")
local Nav = require("../ui/Nav")
local Root = require("../ui/Root")
local Tokens = require("../ui/Tokens")

local C = Tokens.color
local I = Components.icon
local new = Create.new
local CHILDREN = Create.Children

local function build(_params: any?, api: Nav.Api): Nav.Built
	local band = Root.bandBottom()
	local frame: Frame = new("Frame", {
		Name = "Gallery",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})

	-- 肖像の枠（仮：バストアップの代わりに木の額だけ）
	local portrait, portraitContent = Components.panel({
		size = UDim2.fromOffset(460, 486),
		position = UDim2.fromOffset(40, band + 16),
		dark = true,
	})
	portrait.Parent = frame
	local placeholder = Components.text({ text = "Bust-up (placeholder)", size = 21, color = C.inkLight })
	placeholder.AutomaticSize = Enum.AutomaticSize.None
	placeholder.Size = UDim2.fromScale(1, 1)
	placeholder.Parent = portraitContent

	-- 能力の面（題の札つき）
	local panel, content = Components.panel({
		size = UDim2.fromOffset(700, 448),
		position = UDim2.new(1, -40, 0, band + 44),
		anchor = Vector2.new(1, 0),
		title = "Mira",
	})
	panel.Parent = frame
	new("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = content,
	})
	local rows = {
		{ stat = "str", label = "STR", value = 9, prev = 12, min = 1, max = 40 },
		{ stat = "mag", label = "MAG", value = 37, prev = 31, min = 1, max = 40, big = true, marks = 3 },
		{ stat = "agi", label = "AGI", value = 28, prev = 30, min = 1, max = 40, marks = 1 },
		{ stat = "dex", label = "DEX", value = 31, prev = 24, min = 1, max = 40 },
		{ stat = "hp", label = "HP", value = 64, prev = 58, min = 20, max = 80, big = true },
	}
	for i, r in rows do
		local row = Components.statRow(r :: any)
		row.LayoutOrder = i
		row.Parent = content
	end
	local cancel =
		Components.button({ kind = "brown", width = 220, height = 66, icon = I.undo, label = "Cancel", glyph = "Y" })
	cancel.LayoutOrder = 10
	cancel.Parent = content

	-- 右上の ×（面の右上の角）
	local close = Components.closeButton(api.close)
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(1, -40 - 12, 0, band + 44 + 12)
	close.Parent = frame

	-- 右下：Choose（水色）と Reroll（金）を同じ大きさで並べる（D-220）
	local row: Frame = new("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -40, 1, -24),
		Size = UDim2.fromOffset(0, 85),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		[CHILDREN] = {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				Padding = UDim.new(0, 16),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = frame,
	})
	local disabled = Components.button({ kind = "disabled", width = 120, height = 66, icon = I.bell })
	disabled.LayoutOrder = 1
	disabled.Parent = row
	local choose = Components.button({ kind = "blue", width = 300, icon = I.check, label = "Choose", glyph = "A" })
	choose.LayoutOrder = 2
	choose.Parent = row
	local reroll =
		Components.button({ kind = "gold", width = 300, icon = I.reroll, label = "Reroll", cost = "×2", glyph = "X" })
	reroll.LayoutOrder = 3
	reroll.Parent = row

	-- 左下：一時的な札と吹き出し（見本）
	local chip = Components.chip(I.coin, "123,456")
	chip.Position = UDim2.new(0, 40, 1, -24 - 52)
	chip.Parent = frame
	local bubble = Components.speechBubble("Hire a new adventurer?", 360)
	bubble.Position = UDim2.new(0, 520, 1, -24 - 160)
	bubble.Parent = frame

	return { frame = frame }
end

Nav.register("Gallery", build)

return {}
