--!strict
-- S-60 ショップ（M8 は入口だけ。D-107・D-213 ②・D-231 ②⑥、10章 §1・§2）。メイン画面のゴールドを触ると開く。
--   - 左に暗い木の品の行、右に羊皮紙の要約、右下の金＝Robux で買う。購入処理は M9 なので、今は押せない色。
--   - 品は 10章 §1 で「販売する」と決まったものだけ：ゴールド・ステータススロットチケット・見た目変更ポーション（×1・×3）。
--     量・価格はまだ決まっていない（M9）ので出さない（数字を手で置かない）。
--   - 抽選に使う有料アイテムは確率を出す（10章 §2・D-231 ②）。見た目変更ポーションはサイコロのボタンで確率の表
--     （Constants.appearanceLooksWeights）。チケットの表の中身は未決（Q10）なのでまだ出さない。

local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Nav = require("../../ui/Nav")
local Root = require("../../ui/Root")
local Screen = require("../Screen")
local Tokens = require("../../ui/Tokens")
local Words = require("../../ui/Words")
local WarehouseCommon = require("../warehouse/WarehouseCommon")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local SUMMARY_W = 320
local LOOK_WORD = { bea = "★", nor = "●", ugl = "◆", dem = "♣" } -- 美形・普通・ブサイク・亜人（仮の記号）

local function build(_params: any?, api: Nav.Api): Nav.Built
	local band = Root.bandBottom()
	local frame = Screen.scene("Shop")
	Screen.closeTopRight(frame, api.close)
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local items = {
		{ id = "gold", icon = Components.icon.coin, qty = nil, odds = false },
		{ id = "ticket", icon = Components.icon.ticket, qty = nil, odds = false },
		{ id = "look1", icon = "@look_change", qty = 1, odds = true },
		{ id = "look3", icon = "@look_change", qty = 3, odds = true },
	}
	local pick = "look1"
	local showOdds = false
	local render: () -> ()

	render = function()
		body:ClearAllChildren()
		local left, list = Components.panel({
			size = UDim2.new(1, -(40 + 24 + SUMMARY_W + 40), 0, 402),
			position = UDim2.fromOffset(40, band + 98),
			dark = true,
		})
		left.Name = "Items"
		left.Parent = body
		new("UIListLayout", {
			Padding = UDim.new(0, 10),
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = list,
		})
		local cur = items[1]
		for i, it in items do
			local sel = it.id == pick
			if sel then
				cur = it
			end
			local b: TextButton = new("TextButton", {
				Name = "Item_" .. it.id,
				LayoutOrder = i,
				Text = "",
				AutoButtonColor = false,
				Size = UDim2.new(1, 0, 0, 72),
				BackgroundColor3 = if sel then C.ch28 else C.ch17,
				[CHILDREN] = {
					Components.corner(8),
					Components.stroke(if sel then C.selAmber else C.ch17, 3),
					Components.padding(0, 12, 0, 12),
					new("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 18),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				},
				Parent = list,
			})
			b.Activated:Connect(function()
				pick = it.id
				showOdds = false
				render()
			end)
			local ic = Components.text({ text = it.icon, size = 30, color = C.bronzeHi, font = Tokens.font.number })
			ic.LayoutOrder = 1
			ic.Parent = b
			if it.qty then
				local q =
					Components.text({ text = "×" .. it.qty, size = 25, color = C.inkLight, font = Tokens.font.number })
				q.LayoutOrder = 2
				q.Parent = b
			end
		end
		local right, sum = Components.panel({
			size = UDim2.fromOffset(SUMMARY_W, 388),
			position = UDim2.new(1, -40, 0, band + 98),
			anchor = Vector2.new(1, 0),
		})
		right.Name = "Summary"
		right.Parent = body
		new("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = sum,
		})
		if showOdds and cur.odds then
			-- 確率の表（D-231 ②：% は有料アイテムの確率の表だけ）
			for i, w in master.K.appearanceLooksWeights do
				local line = WarehouseCommon.pill(
					LOOK_WORD[w.id] or w.id,
					string.format("%d%%", math.floor(w.weight * 100 + 0.5)),
					25
				)
				line.LayoutOrder = i
				line.Parent = sum
			end
		else
			local big = Components.text({ text = cur.icon, size = 64, color = C.inkDark, font = Tokens.font.number })
			big.LayoutOrder = 1
			big.Parent = sum
			if cur.qty then
				local q = WarehouseCommon.pill("", "×" .. cur.qty, 30)
				q.LayoutOrder = 2
				q.Parent = sum
			end
		end
		local actions = Screen.actionRow(body)
		if cur.odds then
			local dice = Components.button({
				kind = "brown",
				width = 150,
				height = 66,
				icon = "@look_change",
				label = Words.odds,
				name = "Odds",
				glyph = "Y",
				onClick = function()
					showOdds = not showOdds
					render()
				end,
			})
			dice.LayoutOrder = 1
			dice.Parent = actions
		end
		-- 購入は M9。今は押せない色
		local buy = Components.button({
			kind = "disabled",
			width = 320,
			icon = "R$",
			label = Words.buy,
			name = "Buy",
			glyph = "A",
		})
		buy.LayoutOrder = 2
		buy.Parent = actions
	end

	render()
	return { frame = frame, scrim = 1 }
end

Nav.register("Shop", build)

return {}
