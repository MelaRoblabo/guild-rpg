--!strict
-- S-50 倉庫（D-119・D-120・D-167・D-207・D-217・D-218・D-231 ①⑮）。問い＝「どれを売る（守る）？」
--   - 上の並んだタブ＝武器・防具・補助・アイテム。左に格子（倉庫の品だけ。装備中は出さない）、右に幅320の要約、右下に Sell。
--   - マスを押すと選ぶ／外す（複数選べる）。要約は1つなら品の中身と保護のピン、複数なら重ねた絵と数。
--   - Sell＝右下の金（語あり＋合計額）。要約と合計額が確認を兼ねる（D-231 ①）。保護中の品は売らない。
--   - サブ（茶）＝条件で一括売却（D-120）：面でレアリティの上限を選び（前回の上限を保存：D-231 ⑮）、対象と合計を見て Sell。
--   - 並べ替えの面（D-119）：並べ方と向き。前回の並べ方はサーバーに保存（D-117、SetListPrefs）。
--   - 容量は止まりそうなときだけ右上に倉庫＋⚠＋棒の札（D-218 ⑥）。自動売却の設定 S-51 は右上の茶のボタンから。

local Game = require("@game/ReplicatedStorage/Core/Game")
local ChestCommon = require("../chest/ChestCommon")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Art = require("../../ui/Art")
local HubState = require("../../hub/HubState")
local Nav = require("../../ui/Nav")
local Root = require("../../ui/Root")
local Screen = require("../Screen")
local Session = require("../../Session")
local Stock = require("../../warehouse/Stock")
local Tokens = require("../../ui/Tokens")
local Words = require("../../ui/Words")
local WarehouseCommon = require("./WarehouseCommon")
local master = require("../../Master")

local C = Tokens.color
local I = WarehouseCommon.icon
local new = Create.new
local CHILDREN = Create.Children
local deps = WarehouseCommon.deps

local TABS = { "weapon", "armor", "sub", "items" }
local SUMMARY_W = 320

-- 格子の入れ物（スクロールできる）
local function grid(parent: Frame): ScrollingFrame
	return new("ScrollingFrame", {
		Name = "Grid",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.bronze,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 7,
		[CHILDREN] = {
			new("UIGridLayout", {
				CellSize = UDim2.fromOffset(106, 104),
				CellPadding = UDim2.fromOffset(12, 14),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Components.padding(16, 12, 16, 16),
		},
		Parent = parent,
	})
end

-- 重ねる面（羊皮紙。右上の ×）。後ろは暗幕
local function sheet(parent: Frame, name: string, size: UDim2, onClose: () -> ()): (Frame, Frame)
	local scrim: TextButton = new("TextButton", {
		Name = name .. "Scrim",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.scrim,
		BackgroundTransparency = Tokens.transparency.scrim,
		ZIndex = 30,
		Parent = parent,
	})
	local panel, content = Components.panel({
		size = size,
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
	})
	panel.Name = name
	panel.ZIndex = 31
	panel.Parent = scrim
	local close = Components.closeButton(onClose)
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(1, -18, 0, 18)
	close.ZIndex = 40
	close.Parent = panel
	return scrim, content
end

local function build(params: any?, api: Nav.Api): Nav.Built
	local band = Root.bandBottom()
	local frame = Screen.scene("Warehouse")
	Screen.closeTopRight(frame, api.close)

	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local tab = if params and table.find(TABS, (params :: any).tab) then (params :: any).tab else "weapon"
	local selected: { [string]: boolean } = {}
	local itemPick: string? = nil
	local overlay: "sort" | "bulk" | nil = nil
	local bulkMax: number? = nil -- 一括売却の面で選んでいる上限（開いたときは前回の上限）
	local busy = false
	local render: () -> ()

	local function send(cmd: any): any?
		busy = true
		local r = Session.sendAndWait(cmd)
		busy = false
		return r
	end

	local function sellUids(uids: { string })
		if busy or #uids == 0 then
			return
		end
		local r = send({ type = "Sell", equipmentUids = uids })
		if r and r.ok then
			selected = {}
			overlay = nil
		end
		render()
	end

	render = function()
		body:ClearAllChildren()
		local view = Session.view
		if view == nil then
			return
		end
		local prefs = Game.query.listPrefs(view, master)

		-- 選んだ品のうち、もう倉庫にないもの（売った・装備した）を外す
		for uid in selected do
			local it = view.equipment[uid]
			if it == nil or it.equippedBy ~= nil then
				selected[uid] = nil
			end
		end

		-- 上の並んだタブ（武器・防具・補助・アイテム）。選んだ方が琥珀
		local tabs: Frame = new("Frame", {
			Name = "Tabs",
			Position = UDim2.fromOffset(40, band + 12),
			Size = UDim2.fromOffset(0, 74),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.ch52,
			ZIndex = 10,
			[CHILDREN] = {
				Components.corner(37),
				Components.padding(4, 4, 4, 4),
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 4),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = body,
		})
		for i, id in TABS do
			local on = tab == id
			local b: TextButton = new("TextButton", {
				Name = "Tab_" .. id,
				LayoutOrder = i,
				Text = "", -- アイコン＋語（D-245・D-256）は下の setParts
				TextSize = 21,
				FontFace = Tokens.font.display,
				TextColor3 = if on then C.inkDark else C.inkLight,
				AutoButtonColor = false,
				Size = UDim2.fromOffset(Words.slotWidth[id], 66),
				BackgroundColor3 = if on then C.selAmber else C.ch28,
				ZIndex = 11,
				[CHILDREN] = { Components.corner(33) },
				Parent = tabs,
			})
			Components.setParts(b, { I[id], Words.slot[id] })
			b.Activated:Connect(function()
				if tab ~= id then
					tab = id
					selected = {}
					itemPick = nil
					render()
				end
			end)
		end
		local isGear = tab ~= "items"
		local tabsW = 0
		for _, id in TABS do
			tabsW += Words.slotWidth[id]
		end
		local tabsRight = 40 + 4 + tabsW + (#TABS - 1) * 4 + 4

		-- 並べ替えの面を開くボタン（今の並べ方の印と向き）
		local x = tabsRight + 28
		if isGear then
			local sortBtn = WarehouseCommon.tool(
				"Sort",
				{ Words.sort, WarehouseCommon.sortIcon[prefs.whSort], if prefs.whDesc then I.desc else I.asc },
				150,
				function()
					overlay = "sort"
					render()
				end
			)
			sortBtn.Position = UDim2.fromOffset(x, band + 16)
			sortBtn.Parent = body
			x += 150 + 16
		end
		-- 自動売却の設定（S-51）。オンなら緑の点
		local auto = WarehouseCommon.tool("AutoSell", { I.recycle, Words.autoSell }, 170, function()
			api.open("AutoSell")
		end)
		auto.Position = UDim2.fromOffset(x, band + 16)
		auto.Parent = body
		if view.settings and view.settings.autoSell and view.settings.autoSell.enabled then
			new("Frame", {
				Name = "On",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -2, 1, -2),
				Size = UDim2.fromOffset(22, 22),
				BackgroundColor3 = C.okGreen,
				ZIndex = 12,
				[CHILDREN] = { Components.corner(11), Components.stroke(C.ch13, 2) },
				Parent = auto,
			})
		end

		-- 容量：止まりそうなときだけ（宝箱 v3 と同じ札。D-218 ⑥）
		if ChestCommon.warehouseBlocked(view) then
			-- 数字（使用数／上限）は出さず、棒で見せる（D-218 ③⑥）
			local used, size = ChestCommon.warehouse(view)
			local chip = WarehouseCommon.pill(I.warehouse, I.warn, 25, C.inkLight)
			chip.AnchorPoint = Vector2.new(1, 0)
			chip.Position = UDim2.new(1, -120, 0, band + 23)
			chip.ZIndex = 12
			chip.Parent = body
			local track: Frame = new("Frame", {
				Name = "Fill",
				LayoutOrder = 3,
				Size = UDim2.fromOffset(120, 20),
				BackgroundColor3 = C.barTrack,
				ZIndex = 13,
				[CHILDREN] = { Components.corner(6) },
				Parent = chip,
			})
			new("Frame", {
				Name = "Bar",
				Position = UDim2.fromOffset(2, 2),
				Size = UDim2.new(math.clamp(used / math.max(1, size), 0, 1), -4, 1, -4),
				BackgroundColor3 = C.warnDark,
				ZIndex = 14,
				[CHILDREN] = { Components.corner(4) },
				Parent = track,
			})
		end

		-- 左の格子（暗い木）と右の要約（羊皮紙）
		local left, leftContent = Components.panel({
			size = UDim2.new(1, -(40 + 24 + SUMMARY_W + 40), 0, 396),
			position = UDim2.fromOffset(40, band + 98),
			dark = true,
		})
		left.Name = "Stock"
		left.Parent = body
		local right, rightContent = Components.panel({
			size = UDim2.fromOffset(SUMMARY_W, 396),
			position = UDim2.new(1, -40, 0, band + 98),
			anchor = Vector2.new(1, 0),
		})
		right.Name = "Summary"
		right.Parent = body
		local cells = grid(leftContent)
		local actions = Screen.actionRow(body)

		if isGear then
			local uids = Stock.list(view, tab, prefs, master, deps)
			for i, uid in uids do
				local item = view.equipment[uid]
				local base = master.equipmentBases[item.baseId]
				WarehouseCommon.tile({
					name = "Item_" .. uid,
					icon = I[if base then base.slot else "weapon"] or I.weapon,
					image = Art.equip(item),
					rarity = item.rarity,
					grade = item.grade,
					modifier = item.modifierId ~= nil,
					pinned = item.locked == true,
					selected = selected[uid] == true,
					order = i,
					onClick = function()
						selected[uid] = if selected[uid] then nil else true
						render()
					end,
				}).Parent =
					cells
			end

			-- 要約
			local picked = {}
			for _, uid in uids do
				if selected[uid] then
					table.insert(picked, uid)
				end
			end
			local list = new("UIListLayout", {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = rightContent,
			})
			local _ = list
			if #picked == 1 then
				local item = view.equipment[picked[1]]
				local band2: Frame = new("Frame", {
					Name = "RarityBand",
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 44),
					BackgroundColor3 = ChestCommon.rarityColor(item.rarity),
					[CHILDREN] = { Components.corner(6) },
					Parent = rightContent,
				})
				local shape = Components.text({
					text = ChestCommon.rarityShape(item.rarity),
					size = 30,
					color = C.inkLight,
					font = Tokens.font.number,
				})
				shape.AnchorPoint = Vector2.new(0.5, 0.5)
				shape.Position = UDim2.fromScale(0.5, 0.5)
				shape.Parent = band2
				-- 絵と保護のピン（押すと SetLock：D-217）
				local pic: Frame = new("Frame", {
					Name = "Picture",
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 110),
					BackgroundColor3 = C.ch13,
					[CHILDREN] = { Components.corner(8) },
					Parent = rightContent,
				})
				local base = master.equipmentBases[item.baseId]
				local big = Components.text({
					text = I[if base then base.slot else "weapon"] or I.weapon,
					size = 64,
					color = C.inkLight,
					font = Tokens.font.number,
				})
				big.AnchorPoint = Vector2.new(0.5, 0.5)
				big.Position = UDim2.fromScale(0.5, 0.5)
				big.Parent = pic
				local pin: TextButton = new("TextButton", {
					Name = "Pin",
					Text = Components.plain(I.pin),
					TextSize = 28,
					FontFace = Tokens.font.number,
					TextColor3 = C.inkLight,
					AutoButtonColor = false,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -8, 0, 8),
					Size = UDim2.fromOffset(66, 66),
					BackgroundColor3 = if item.locked then C.selAmber else C.secondary,
					[CHILDREN] = { Components.corner(33), Components.stroke(C.bronze, 3) },
					Parent = pic,
				})
				pin.Activated:Connect(function()
					if busy then
						return
					end
					send({ type = "SetLock", uid = item.uid, locked = not item.locked })
					render()
				end)
				local name = Components.text({
					text = WarehouseCommon.fullName(item),
					size = 23,
					color = C.inkDark,
					font = Tokens.font.display,
				})
				name.LayoutOrder = 3
				name.AutomaticSize = Enum.AutomaticSize.Y
				name.Size = UDim2.fromScale(1, 0)
				name.TextWrapped = true
				name.Parent = rightContent
				local vals: Frame = new("Frame", {
					Name = "Values",
					LayoutOrder = 4,
					Size = UDim2.fromScale(1, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					[CHILDREN] = {
						new("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							HorizontalAlignment = Enum.HorizontalAlignment.Center,
							Wraps = true,
							Padding = UDim.new(0, 8),
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
					},
					Parent = rightContent,
				})
				for i, v in WarehouseCommon.values(item) do
					local pill = WarehouseCommon.pill(v.icon, v.text, if v.icon == I.modifier then 21 else 25)
					pill.LayoutOrder = i
					pill.Parent = vals
				end
				local jobs: Frame = new("Frame", {
					Name = "Jobs",
					LayoutOrder = 5,
					Size = UDim2.fromScale(1, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					[CHILDREN] = {
						new("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							HorizontalAlignment = Enum.HorizontalAlignment.Center,
							Wraps = true,
							Padding = UDim.new(0, 6),
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
					},
					Parent = rightContent,
				})
				for i, j in WarehouseCommon.jobs(item) do
					local pill = WarehouseCommon.pill("", j, 21)
					pill.LayoutOrder = i
					pill.Parent = jobs
				end
			elseif #picked > 1 then
				local stack: Frame = new("Frame", {
					Name = "Stack",
					LayoutOrder = 1,
					Size = UDim2.fromOffset(200, 170),
					BackgroundTransparency = 1,
					Parent = rightContent,
				})
				for k = 1, math.min(3, #picked) do
					local item = view.equipment[picked[k]]
					local t = WarehouseCommon.tile({
						name = "Stacked" .. k,
						icon = I[tab],
						image = Art.equip(item),
						rarity = item.rarity,
						order = k,
						onClick = function() end,
					})
					t.Size = UDim2.fromOffset(104, 104)
					t.Position = UDim2.fromOffset(20 + (k - 1) * 34, 30 + (k - 1) * 8)
					t.Rotation = (k - 2) * 6
					t.Parent = stack
				end
				local n = WarehouseCommon.pill("", "×" .. #picked, 30)
				n.LayoutOrder = 2
				n.Parent = rightContent
			end

			-- 右下：条件で一括売却（茶）と Sell（金・語あり＋合計額）。保護中の品は売らない
			local sellable = {}
			for _, uid in picked do
				if not view.equipment[uid].locked then
					table.insert(sellable, uid)
				end
			end
			local bulk = Components.button({
				kind = "brown",
				width = 190,
				height = 66,
				icon = I.bulk,
				label = Words.bulkSell,
				name = "SellByRule",
				glyph = "X",
				onClick = function()
					overlay = "bulk"
					bulkMax = nil
					render()
				end,
			})
			bulk.LayoutOrder = 1
			bulk.Parent = actions
			local sell = Components.button({
				kind = if #sellable > 0 then "gold" else "disabled",
				width = 320,
				label = "Sell",
				cost = HubState.formatNumber(Stock.total(view, sellable, master, deps)),
				name = "Sell",
				glyph = "A",
				onClick = function()
					sellUids(sellable)
				end,
			})
			sell.LayoutOrder = 2
			sell.Parent = actions
		else
			-- アイテムのタブ：チケット・ポーションの数だけ（売却額0なので Sell なし）
			local rows = Stock.items(view, master)
			for i, r in rows do
				local def = master.items[r.itemId]
				WarehouseCommon.tile({
					name = "Item_" .. r.itemId,
					icon = if def and def.kind == "ticket" then I.items else I.potion,
					image = Art.item(r.itemId),
					count = r.count,
					selected = itemPick == r.itemId,
					order = i,
					onClick = function()
						itemPick = r.itemId
						render()
					end,
				}).Parent =
					cells
			end
			if itemPick and master.items[itemPick] then
				local def = master.items[itemPick]
				new("UIListLayout", {
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding = UDim.new(0, 12),
					SortOrder = Enum.SortOrder.LayoutOrder,
					Parent = rightContent,
				})
				local big = Components.text({
					text = if def.kind == "ticket" then I.items else I.potion,
					size = 64,
					color = C.inkDark,
					font = Tokens.font.number,
				})
				big.LayoutOrder = 1
				big.Parent = rightContent
				local name =
					Components.text({ text = def.nameEn, size = 23, color = C.inkDark, font = Tokens.font.display })
				name.LayoutOrder = 2
				name.AutomaticSize = Enum.AutomaticSize.Y
				name.Size = UDim2.fromScale(1, 0)
				name.TextWrapped = true
				name.Parent = rightContent
				local n = WarehouseCommon.pill("", "×" .. ((view.items or {})[itemPick] or 0), 25)
				n.LayoutOrder = 3
				n.Parent = rightContent
			end
		end

		-- 並べ替えの面（D-119・D-117）
		if overlay == "sort" then
			local _, content = sheet(body, "SortSheet", UDim2.fromOffset(640, 230), function()
				overlay = nil
				render()
			end)
			new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
			local function row(
				order: number,
				opts: { { id: string, text: string, on: boolean } },
				onPick: (string) -> ()
			)
				local r: Frame = new("Frame", {
					Name = "Row" .. order,
					LayoutOrder = order,
					Size = UDim2.new(1, 0, 0, 74),
					BackgroundColor3 = C.ch52,
					ZIndex = 32,
					[CHILDREN] = {
						Components.corner(37),
						Components.padding(4, 4, 4, 4),
						new("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							Padding = UDim.new(0, 4),
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
					},
					Parent = content,
				})
				for i, o in opts do
					local b: TextButton = new("TextButton", {
						Name = "Opt_" .. o.id,
						LayoutOrder = i,
						Text = o.text,
						TextSize = 28,
						FontFace = Tokens.font.number,
						TextColor3 = if o.on then C.inkDark else C.inkLight,
						AutoButtonColor = false,
						Size = UDim2.new(1 / #opts, -4, 0, 66),
						BackgroundColor3 = if o.on then C.selAmber else C.ch28,
						ZIndex = 33,
						[CHILDREN] = { Components.corner(33) },
						Parent = r,
					})
					b.Activated:Connect(function()
						onPick(o.id)
					end)
				end
			end
			local sorts = {}
			for _, id in { "rarity", "power", "sell", "new" } do
				table.insert(sorts, { id = id, text = WarehouseCommon.sortIcon[id], on = prefs.whSort == id })
			end
			row(1, sorts, function(id)
				if not busy then
					send({ type = "SetListPrefs", whSort = id })
					render()
				end
			end)
			row(2, {
				{ id = "desc", text = I.desc, on = prefs.whDesc },
				{ id = "asc", text = I.asc, on = not prefs.whDesc },
			}, function(id)
				if not busy then
					send({ type = "SetListPrefs", whDesc = id == "desc" })
					render()
				end
			end)
		end

		-- 条件で一括売却の面（D-120・D-231 ①⑮）：上限を選び、対象と合計を見て Sell
		if overlay == "bulk" and isGear then
			local maxR = bulkMax or prefs.bulkSellMaxRarity
			local uids, total = Stock.bulkPlan(view, tab, maxR, master, deps)
			local scrim, content = sheet(body, "BulkSheet", UDim2.fromOffset(720, 440), function()
				overlay = nil
				render()
			end)
			new("UIListLayout", {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 14),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = content,
			})
			local steps = WarehouseCommon.raritySteps(maxR, 640, function(r)
				if busy then
					return
				end
				bulkMax = r
				send({ type = "SetListPrefs", bulkSellMaxRarity = r }) -- 前回の上限として保存（D-231 ⑮）
				render()
			end)
			steps.LayoutOrder = 1
			steps.Parent = content
			-- 売らないもの（修飾語・装備中・保護）は固定の印で見せる
			local keeps: Frame = new("Frame", {
				Name = "Keeps",
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 44),
				BackgroundTransparency = 1,
				ZIndex = 32,
				[CHILDREN] = {
					new("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						Padding = UDim.new(0, 10),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				},
				Parent = content,
			})
			for i, icon in { I.modifier, "♟", I.pin } do
				local k = WarehouseCommon.pill(I.warehouse, icon, 25)
				k.LayoutOrder = i
				k.ZIndex = 33
				k.Parent = keeps
			end
			-- 対象の数（重ねた絵の代わりに数）
			local n = WarehouseCommon.pill(I[tab], "×" .. #uids, 30)
			n.LayoutOrder = 3
			n.ZIndex = 33
			n.Parent = content
			local sell = Components.button({
				kind = if #uids > 0 then "gold" else "disabled",
				width = 320,
				label = "Sell",
				cost = HubState.formatNumber(total),
				name = "SellRule",
				glyph = "A",
				onClick = function()
					sellUids(uids)
				end,
			})
			sell.LayoutOrder = 4
			sell.Parent = content
			local _ = scrim
		end
	end

	render()
	local conn = Session.changed:connect(function()
		if not busy then
			render()
		end
	end)
	return {
		frame = frame,
		scrim = 1,
		destroy = function()
			conn.disconnect()
		end,
	}
end

Nav.register("Warehouse", build)

return {}
