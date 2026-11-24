--!strict
-- S-31b+e 結果（開封結果の表とまとめを1枚に：D-223 ①）。
--   - 強くなった人のカード（バストアップ＋名前＋品＋比べる値の行）だけを見せる。装備済みは ✓、まだなら Equip（茶）。
--     入りきらない分は「▲ +N」の札（品の一覧・絞り込みは倉庫 S-50 へ）。
--   - 下の1行：ゴールド・自動売却の数・倉庫に入った数（倉庫で止まったときは警告の色）。
--   - 右下：Sell（茶。今の装備より弱いものを売る：D-167・D-207）と、続けて開ける金（同じ山の残り。All なら全部の山）。

local ChestCommon = require("./ChestCommon")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Game = require("@game/ReplicatedStorage/Core/Game")
local HubState = require("../../hub/HubState")
local Nav = require("../../ui/Nav")
local Root = require("../../ui/Root")
local Screen = require("../Screen")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local master = require("../../Master")

local C = Tokens.color
local I = ChestCommon.icon
local new = Create.new
local CHILDREN = Create.Children

local CARDS = 2 -- 1枚に並べるカードの数（D-223 ①の見本）

local function build(params: any?, api: Nav.Api): Nav.Built
	local batch: ChestCommon.Batch = (params :: any).batch
	local band = Root.bandBottom()
	local frame = Screen.scene("ChestResults")
	Screen.closeTopRight(frame, api.close)
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local busy = false

	local render: () -> ()
	render = function()
		body:ClearAllChildren()
		local view = Session.view
		if view == nil then
			return
		end
		local panel, content = Components.panel({
			size = UDim2.new(1, -80, 0, 408),
			position = UDim2.fromOffset(40, band + 44),
		})
		panel.Name = "Upgrades"
		panel.Parent = body
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = content,
		})
		local shown = 0
		for i, u in batch.plan do
			if i > CARDS then
				break
			end
			local adv = view.adventurers[u.advUid]
			local item = view.equipment[u.itemUid]
			if adv and item then
				shown += 1
				local card: Frame = new("Frame", {
					Name = "Card" .. i,
					LayoutOrder = i,
					Size = UDim2.new(0, 478, 1, 0),
					BackgroundColor3 = C.ch75,
					[CHILDREN] = {
						Components.corner(8),
						Components.padding(8, 8, 8, 8),
						new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
					},
					Parent = content,
				})
				local top: Frame = new("Frame", {
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 228),
					BackgroundColor3 = C.ch68,
					[CHILDREN] = { Components.corner(6), Components.padding(8, 8, 8, 8) },
					Parent = card,
				})
				local bust = ChestCommon.bust(Vector2.new(184, 212))
				bust.Parent = top
				local info: Frame = new("Frame", {
					Position = UDim2.fromOffset(198, 0),
					Size = UDim2.new(1, -198, 1, 0),
					BackgroundTransparency = 1,
					[CHILDREN] = {
						new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
					},
					Parent = top,
				})
				local name = Components.text({
					text = adv.name,
					size = 30,
					color = C.inkDark,
					font = Tokens.font.display,
					xAlign = Enum.TextXAlignment.Left,
				})
				name.LayoutOrder = 1
				name.Parent = info
				local itemLine = Components.text({
					text = ChestCommon.rarityShape(item.rarity) .. " " .. ChestCommon.itemName(item),
					size = 21,
					color = C.inkMid,
					font = Tokens.font.bodyStrong,
					xAlign = Enum.TextXAlignment.Left,
				})
				itemLine.AutomaticSize = Enum.AutomaticSize.Y
				itemLine.Size = UDim2.fromScale(1, 0)
				itemLine.TextWrapped = true
				itemLine.LayoutOrder = 2
				itemLine.Parent = info
				local equipped = item.equippedBy == adv.uid
				if equipped then
					local mark: Frame = new("Frame", {
						Name = "Equipped",
						LayoutOrder = 3,
						Size = UDim2.fromOffset(52, 52),
						BackgroundColor3 = C.okGreen,
						[CHILDREN] = { Components.corner(26), Components.stroke(C.ch13, 3) },
						Parent = info,
					})
					local ok =
						Components.text({ text = "✓", size = 30, color = C.inkDark, font = Tokens.font.number })
					ok.AutomaticSize = Enum.AutomaticSize.None
					ok.Size = UDim2.fromScale(1, 1)
					ok.Parent = mark
				else
					local canEquip = not ChestCommon.isBusy(view, adv.uid)
					local equip = Components.button({
						kind = if canEquip then "brown" else "disabled",
						width = 96,
						height = 66,
						icon = I.equip,
						name = "Equip",
						onClick = function()
							if busy then
								return
							end
							busy = true
							Session.sendAndWait({ type = "Equip", adventurerUid = adv.uid, equipmentUid = item.uid })
							busy = false
							render()
						end,
					})
					equip.LayoutOrder = 3
					equip.Parent = info
				end
				local row = ChestCommon.compareRow(u.slot, u.value, u.current)
				row.LayoutOrder = 2
				row.Parent = card
			end
		end
		-- 入りきらない強化の数（倉庫へ）
		local more = batch.upgradeItems - shown
		if more > 0 then
			local tile: Frame = new("Frame", {
				Name = "More",
				LayoutOrder = 10,
				Size = UDim2.new(1, -(shown * (478 + 12)), 1, 0),
				BackgroundColor3 = C.ch75,
				[CHILDREN] = {
					Components.corner(8),
					Components.stroke(C.ch45, 2),
					new("UIListLayout", {
						Padding = UDim.new(0, 12),
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				},
				Parent = content,
			})
			local up =
				Components.text({ text = Components.icon.up, size = 30, color = C.up, font = Tokens.font.number })
			up.LayoutOrder = 1
			up.Parent = tile
			local n = Components.text({ text = "+" .. more, size = 40, color = C.inkDark, font = Tokens.font.display })
			n.LayoutOrder = 2
			n.Parent = tile
			local w = Components.text({ text = I.warehouse, size = 30, color = C.inkMid, font = Tokens.font.number })
			w.LayoutOrder = 3
			w.Parent = tile
		end

		-- 強くなった人がいなければ面を出さず、下の1行を真ん中に大きく出す（主役を1つに：D-218 ②）
		local empty = shown == 0 and more <= 0
		if empty then
			panel:Destroy()
		end
		-- 下の1行：ゴールド・自動売却・倉庫
		local line: Frame = new("Frame", {
			Name = "Summary",
			Position = if empty then UDim2.new(0.5, 0, 0, band + 260) else UDim2.fromOffset(40, band + 524),
			AnchorPoint = if empty then Vector2.new(0.5, 0.5) else Vector2.zero,
			Size = UDim2.fromOffset(0, 52),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			ZIndex = 8,
			[CHILDREN] = {
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 12),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = body,
		})
		if empty then
			new("UIScale", { Scale = 1.5, Parent = line })
		end
		local gold = Components.chip(I.gold, "+" .. HubState.formatNumber(batch.gold))
		gold.LayoutOrder = 1
		gold.Parent = line
		if batch.autoSold > 0 then
			local sold = Components.chip(I.recycle, HubState.formatNumber(batch.autoSold), C.bronzeHi)
			sold.LayoutOrder = 2
			sold.Parent = line
		end
		local stopped = batch.stoppedBy == "WAREHOUSE_FULL"
		local ware = Components.chip(
			if stopped then I.warn else I.warehouse,
			"+" .. HubState.formatNumber(#batch.itemUids),
			if stopped then C.warnDark else C.bronzeHi
		)
		ware.LayoutOrder = 3
		if stopped then
			Components.stroke(C.warnDark, 2).Parent = ware
		end
		ware.Parent = line

		-- 右下：Sell（茶）と続けて開ける（金）
		local actions = Screen.actionRow(body)
		local preview = Game.query.bulkSellPreview(view, batch.itemUids, master)
		if preview.count > 0 then
			local sell = Components.button({
				kind = "brown",
				width = 240,
				height = 66,
				icon = I.recycle,
				label = "Sell",
				cost = HubState.formatNumber(preview.gold),
				name = "Sell",
				glyph = "X",
				onClick = function()
					if busy then
						return
					end
					busy = true
					Session.sendAndWait({ type = "BulkSell", equipmentUids = preview.equipmentUids })
					busy = false
					render()
				end,
			})
			sell.LayoutOrder = 1
			sell.Parent = actions
		end
		local piles: { string }
		local label: string? = nil
		local icon: string
		if batch.all then
			piles = ChestCommon.allPiles(view)
			icon = I.all
		else
			local key = batch.piles[1]
			local left = ChestCommon.pileCount(view, key)
			piles = if left > 0 then { key } else {}
			icon = ChestCommon.pileInfo(key).icon
			label = if left > 0 then "×" .. math.min(left, master.K.chestBatchOpen) else nil
		end
		local canOpen = #piles > 0 and not ChestCommon.warehouseBlocked(view)
		local again = Components.button({
			kind = if canOpen then "gold" else "disabled",
			width = 320,
			icon = icon,
			label = label,
			name = "Again",
			glyph = "A",
			onClick = function()
				if busy then
					return
				end
				busy = true
				local next = ChestCommon.open(piles, batch.all)
				busy = false
				if next then
					api.replace("ChestOpening", { batch = next })
				else
					render()
				end
			end,
		})
		again.LayoutOrder = 2
		again.Parent = actions
	end

	render()
	return { frame = frame, scrim = 1 }
end

Nav.register("ChestResults", build)

return {}
