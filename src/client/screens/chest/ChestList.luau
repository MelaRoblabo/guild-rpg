--!strict
-- S-30 宝箱（D-084・D-087・D-089・D-164・D-166・D-223 ②）。
--   - 左上のタブで宝箱の山と受け取り箱を切り替える（選んだ方が琥珀）。
--   - 宝箱：左に普通の山（ダンジョン）、右に特別な宝箱の山。行ごとに数と ×N（最大 chestBatchOpen 個）。
--     レアリティは開けるまで見せない（D-087）。右下の金が All（山ごとに最大 chestBatchOpen 個：D-129）。
--   - 倉庫がいっぱいで開けられないときだけ、警告の札と Sell（今の装備より弱いものを売る：D-167・D-207）。
--   - 受け取り箱：届いたものの行と、右下の金で受け取れるものを全部受け取る（D-164・D-176）。
--   - 状態が変わったら中身を作り直す（開封の画面を閉じて戻ったとき、数が新しくなっている）。

local Game = require("@game/ReplicatedStorage/Core/Game")
local ChestCommon = require("./ChestCommon")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local HubState = require("../../hub/HubState")
local Nav = require("../../ui/Nav")
local Root = require("../../ui/Root")
local Screen = require("../Screen")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local Guide = require("../../hub/Guide")
local Words = require("../../ui/Words")
local master = require("../../Master")

local C = Tokens.color
local I = ChestCommon.icon
local new = Create.new
local CHILDREN = Create.Children

-- 数の札（暗い凹みにアイコンと数字）
local OPEN_W = 160 -- 山ごとの「Open ×N」の幅（D-245）

local function countPill(icon: string, n: number, iconColor: Color3?): Frame
	local pill: Frame = new("Frame", {
		Name = "Count",
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ch10,
		[CHILDREN] = {
			Components.corner(22),
			Components.padding(0, 14, 0, 10),
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	})
	local ic = Components.text({ text = icon, size = 23, color = iconColor or C.bronzeHi, font = Tokens.font.number })
	ic.LayoutOrder = 1
	ic.Parent = pill
	local t =
		Components.text({ text = HubState.formatNumber(n), size = 25, color = C.inkLight, font = Tokens.font.number })
	t.LayoutOrder = 2
	t.Parent = pill
	return pill
end

-- 並びの行の入れ物（スクロールできる）
local function list(parent: Frame): ScrollingFrame
	return new("ScrollingFrame", {
		Name = "List",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.bronze,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		[CHILDREN] = {
			new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
			Components.padding(4, 8, 4, 4),
		},
		Parent = parent,
	})
end

-- 宝箱の山の行
local function pileRow(
	info: ChestCommon.PileInfo,
	count: number,
	order: number,
	enabled: boolean,
	onOpen: () -> ()
): Frame
	local row: Frame = new("Frame", {
		Name = "Pile_" .. info.pileKey,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 76),
		BackgroundColor3 = C.ch16,
		[CHILDREN] = { Components.corner(8) },
	})
	-- 右から：×N のボタン、数の札。名前は残りの幅（普通の山はダンジョン名。特別な宝箱はアイコンを頭に）
	local n = math.min(count, master.K.chestBatchOpen)
	local open = Components.button({
		kind = if enabled then "brown" else "disabled",
		width = OPEN_W,
		height = 66,
		label = Words.open .. " ×" .. n, -- 山の印は左の数の札にあるので、ボタンは語と数だけ（D-245）
		name = "Open",
		onClick = onOpen,
	})
	open.AnchorPoint = Vector2.new(1, 0.5)
	open.Position = UDim2.new(1, -6, 0.5, 0)
	open.Parent = row
	-- 閉じた箱の絵を積んだ形（数に応じて1〜3個）と、上に数の札（D-268 ②）。
	-- 箱はレアリティを表さないふつうの宝箱のアイコン（開けるまでレアリティは見せない：D-087）
	local stack: Frame = new("Frame", {
		Name = "Stack",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(6 + OPEN_W + 12), 0.5, 0),
		Size = UDim2.fromOffset(100, 70),
		BackgroundTransparency = 1,
		Parent = row,
	})
	local boxes = if count >= 10 then 3 elseif count >= 2 then 2 else 1
	for k = 1, boxes do
		local b = Components.text({ text = I.chest, size = 34, color = C.bronzeHi, font = Tokens.font.number })
		b.Name = "Box" .. k
		b.AutomaticSize = Enum.AutomaticSize.None
		b.AnchorPoint = Vector2.new(0.5, 1)
		b.Size = UDim2.fromOffset(38, 38)
		b.Position = UDim2.new(1, -19 - (k - 1) * 20, 1, -4) -- 右寄せ（名前と重ならないように）
		b.ZIndex = 3 + k
		b.Parent = stack
	end
	local badge = Components.text({
		text = "×" .. HubState.formatNumber(count),
		size = 21,
		color = C.inkLight,
		font = Tokens.font.number,
		stroke = true,
	})
	badge.Name = "Count"
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, 0, 0, -2)
	badge.ZIndex = 8
	badge.Parent = stack
	-- 特別な宝箱はアイコン＋語（「@login」の記号を文字のまま出していたのを直す）
	local word = info.name
	if info.special and word == "" then
		local key = string.match(info.pileKey, "^special:(%w+)") or ""
		word = ChestCommon.sourceWord[key] or ""
	end
	local name = Components.text({
		text = "",
		size = if info.special then 23 else 25,
		color = C.inkLight,
		font = Tokens.font.display,
		xAlign = Enum.TextXAlignment.Left,
	})
	name.AutomaticSize = Enum.AutomaticSize.None
	name.AnchorPoint = Vector2.new(0, 0.5)
	name.Position = UDim2.new(0, 16, 0.5, 0)
	name.Size = UDim2.new(1, -(16 + 6 + OPEN_W + 12 + 110), 0, 40)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	if info.special then
		Components.setParts(name, { info.icon, word })
	else
		name.Text = word
	end
	name.Parent = row
	return row
end

local function build(params: any?, api: Nav.Api): Nav.Built
	local tab = if params and (params :: any).tab == "inbox" then "inbox" else "chests"
	Guide.done("chests") -- 初回の誘導：宝箱ボタン（一覧を開いた：D-244 ①）
	local band = Root.bandBottom()
	local frame = Screen.scene("ChestList")
	Screen.closeTopRight(frame, api.close)

	-- 中身（状態が変わるたびに作り直す）
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local busy = false
	local gained: { gold: number, tickets: number }? = nil

	local render: () -> ()

	local function openPiles(piles: { string }, all: boolean)
		if busy or #piles == 0 then
			return
		end
		-- 初めての開封か（誘導の Open All の段がまだ済んでいない）。初回は設定にかかわらず演出をフルで見せる（D-267 ④）
		local first = Guide.is("chests") or Guide.is("openAll")
		Guide.done("openAll") -- 初回の誘導：開けた（Open All でも山ごとでも）
		busy = true
		local batch = ChestCommon.open(piles, all)
		busy = false
		if batch then
			batch.first = first
			api.open("ChestOpening", { batch = batch })
		else
			render()
		end
	end

	render = function()
		body:ClearAllChildren()
		local view = Session.view
		if view == nil then
			return
		end
		local total = 0
		for _, c in view.chests or {} do
			total += c.count
		end
		local inbox = view.inbox or {}

		-- 左上のタブ（宝箱の数／受け取り箱）。選んだ方が琥珀（D-223 ②）
		local tabs: Frame = new("Frame", {
			Name = "Tabs",
			Position = UDim2.fromOffset(40, band + 12),
			Size = UDim2.fromOffset(0, 74),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.ch10,
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
		local function tabButton(id: string, icon: string, word: string, count: number?, order: number)
			local on = tab == id
			local b: TextButton = new("TextButton", {
				Name = "Tab_" .. id,
				LayoutOrder = order,
				Text = "",
				AutoButtonColor = false,
				Size = UDim2.fromOffset(if count then 250 else 180, 66),
				BackgroundColor3 = if on then C.selAmber else C.ch16,
				ZIndex = 11,
				[CHILDREN] = { Components.corner(33) },
				Parent = tabs,
			})
			-- 中身は別の枠に並べる（「！」を並びの外、角に置くため）
			local inner: Frame = new("Frame", {
				Name = "Inner",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 11,
				[CHILDREN] = {
					new("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 10),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				},
				Parent = b,
			})
			local ink = if on then C.inkDark else C.inkLight
			local ic = Components.text({ text = icon, size = 25, color = ink, font = Tokens.font.number })
			ic.LayoutOrder = 1
			ic.ZIndex = 12
			ic.Parent = inner
			local wd = Components.text({ text = word, size = 21, color = ink, font = Tokens.font.display })
			wd.LayoutOrder = 2
			wd.ZIndex = 12
			wd.Parent = inner
			if count then
				local t = Components.text({
					text = HubState.formatNumber(count),
					size = 25,
					color = ink,
					font = Tokens.font.number,
				})
				t.LayoutOrder = 3
				t.ZIndex = 12
				t.Parent = inner
			end
			b.Activated:Connect(function()
				if tab ~= id then
					tab = id
					render()
				end
			end)
			return b
		end
		tabButton("chests", I.chest, Words.chests, total, 1)
		local inboxTab = tabButton("inbox", I.inbox, Words.inbox, nil, 2)
		if #inbox > 0 then
			-- 受け取り箱に届いたものがあるときだけ「！」（D-208 ⑤）
			new("TextLabel", {
				Name = "Notice",
				Text = "!",
				TextSize = 21,
				FontFace = Tokens.font.number,
				TextColor3 = C.inkWhite,
				BackgroundColor3 = C.notice,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -6, 0, 6),
				Size = UDim2.fromOffset(30, 30),
				ZIndex = 13,
				[CHILDREN] = { Components.corner(15) },
				Parent = inboxTab,
			})
		end

		local actions = Screen.actionRow(body)

		if tab == "chests" then
			local blocked = ChestCommon.warehouseBlocked(view)
			-- 特別な宝箱の山が1つもなければ右の枠を出さず、左を全幅にする（D-251 ②）
			local hasSpecial = false
			for _, c in view.chests or {} do
				if c.count > 0 and ChestCommon.pileInfo(c.pileKey).special then
					hasSpecial = true
					break
				end
			end
			-- 左：普通の山（ダンジョン）
			local left, leftContent = Components.panel({
				size = if hasSpecial then UDim2.new(1, -(40 + 24 + 456 + 40), 0, 392) else UDim2.new(1, -80, 0, 392), -- 横に広い端末では左の面が伸びる
				position = UDim2.fromOffset(40, band + 98),
				dark = true,
			})
			left.Name = "DungeonPiles"
			left.Parent = body
			local right, rightContent = Components.panel({
				size = UDim2.fromOffset(456, 392),
				position = UDim2.new(1, -40, 0, band + 98),
				anchor = Vector2.new(1, 0),
				dark = true,
			})
			right.Name = "SpecialPiles"
			right.Visible = hasSpecial
			right.Parent = body
			local leftList = list(leftContent)
			local rightList = list(rightContent)
			for i, c in view.chests or {} do
				if c.count > 0 then
					local info = ChestCommon.pileInfo(c.pileKey)
					local row = pileRow(info, c.count, i, not blocked, function()
						openPiles({ c.pileKey }, false)
					end)
					row.Parent = if info.special then rightList else leftList
				end
			end

			-- 倉庫がいっぱい：右上の警告の札と Sell（D-130・D-223 ②）
			if blocked then
				local used, size = ChestCommon.warehouse(view)
				local chip: Frame = new("Frame", {
					Name = "WarehouseFull",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -120, 0, band + 19),
					Size = UDim2.fromOffset(0, 52),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundColor3 = C.ch10,
					ZIndex = 12,
					[CHILDREN] = {
						Components.corner(26),
						Components.stroke(C.warnDark, 2),
						Components.padding(0, 18, 0, 14),
						new("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0, 10),
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
					},
					Parent = body,
				})
				local ic =
					Components.text({ text = I.warehouse, size = 25, color = C.warnDark, font = Tokens.font.number })
				ic.LayoutOrder = 1
				ic.ZIndex = 13
				ic.Parent = chip
				local track: Frame = new("Frame", {
					LayoutOrder = 2,
					Size = UDim2.fromOffset(120, 20),
					BackgroundColor3 = C.barTrack,
					ZIndex = 13,
					[CHILDREN] = { Components.corner(6) },
					Parent = chip,
				})
				new("Frame", {
					Position = UDim2.fromOffset(2, 2),
					Size = UDim2.new(math.clamp(used / math.max(1, size), 0, 1), -4, 1, -4),
					BackgroundColor3 = C.warnDark,
					ZIndex = 14,
					[CHILDREN] = { Components.corner(4) },
					Parent = track,
				})
				local uids = {}
				for uid, e in view.equipment or {} do
					if e.equippedBy == nil then
						table.insert(uids, uid)
					end
				end
				local preview = Game.query.bulkSellPreview(view, uids, master)
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
			end

			local all = Components.button({
				kind = if blocked or total == 0 then "disabled" else "gold",
				width = 320,
				icon = I.all,
				label = Words.openAll,
				name = "All",
				glyph = "A",
				onClick = function()
					openPiles(ChestCommon.allPiles(Session.view), true)
				end,
			})
			all.LayoutOrder = 2
			all.Parent = actions
			Guide.mark(all, Guide.is("openAll") and not blocked and total > 0, 18, true) -- 初回の誘導：Open All
		else
			-- 受け取り箱
			local panel, content = Components.panel({
				size = UDim2.new(1, -80, 0, 392),
				position = UDim2.fromOffset(40, band + 98),
				dark = true,
			})
			panel.Name = "Inbox"
			panel.Parent = body
			local rows = list(content)
			local roster = 0
			for _ in view.adventurers or {} do
				roster += 1
			end
			for i, entry in inbox do
				local row: Frame = new("Frame", {
					Name = "Entry_" .. tostring(entry.uid),
					LayoutOrder = i,
					Size = UDim2.new(1, 0, 0, 72),
					BackgroundColor3 = C.ch16,
					[CHILDREN] = {
						Components.corner(8),
						Components.padding(0, 14, 0, 14),
						new("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0, 14),
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
					},
					Parent = rows,
				})
				local src = Components.text({
					text = ChestCommon.sourceIcon[entry.source] or I.inbox,
					size = 30,
					color = C.bronzeHi,
					font = Tokens.font.number,
				})
				src.AutomaticSize = Enum.AutomaticSize.None
				src.Size = UDim2.fromOffset(48, 48)
				src.LayoutOrder = 0
				src.Parent = row
				-- どこからの報酬かを語で（D-251 ①）
				local srcWord = ChestCommon.sourceWord[entry.source]
				if srcWord then
					local w = Components.text({
						text = srcWord,
						size = 21,
						color = C.inkLight,
						font = Tokens.font.display,
					})
					w.AutomaticSize = Enum.AutomaticSize.None
					w.Size = UDim2.fromOffset(110, 48)
					w.TextXAlignment = Enum.TextXAlignment.Left
					w.LayoutOrder = 1
					w.Name = "SourceWord"
					w.Parent = row
				end
				local order = 2
				local function put(inst: GuiObject)
					inst.LayoutOrder = order
					order += 1
					inst.Parent = row
				end
				if entry.uniqueId then
					-- ユニークは所属枠に空きがないと受け取れず残る（D-176）
					local full = roster >= view.expansions.rosterSize
					put(countPill(I.unique, 1, if full then C.warnDark else C.rewardGlow))
					if full then
						put(
							Components.text({ text = I.warn, size = 25, color = C.warnDark, font = Tokens.font.number })
						)
					end
				end
				if entry.gold then
					put(countPill(I.gold, entry.gold, C.coinGold))
				end
				for _, c in entry.chests or {} do
					put(countPill(ChestCommon.pileInfo(c.pileKey).icon, c.count))
				end
				for itemId, n in entry.items or {} do
					local item = master.items[itemId]
					put(countPill(if item and item.kind == "ticket" then I.ticket else "◆", n))
				end
			end

			-- 受け取った瞬間だけ、増えた分を右上に出す（D-218 ⑥）
			if gained then
				local g = gained :: { gold: number, tickets: number }
				local row: Frame = new("Frame", {
					Name = "Gained",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -120, 0, band + 19),
					Size = UDim2.fromOffset(0, 52),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					ZIndex = 12,
					[CHILDREN] = {
						new("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							Padding = UDim.new(0, 12),
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
					},
					Parent = body,
				})
				if g.tickets > 0 then
					local chip = Components.chip(I.ticket, "+" .. HubState.formatNumber(g.tickets), C.bronzeHi)
					chip.LayoutOrder = 1
					chip.Parent = row
				end
				if g.gold > 0 then
					local chip = Components.chip(I.gold, "+" .. HubState.formatNumber(g.gold))
					chip.LayoutOrder = 2
					chip.Parent = row
				end
			end

			local claim = Components.button({
				kind = if #inbox == 0 then "disabled" else "gold",
				width = 320,
				icon = I.claim,
				label = Words.claim,
				name = "Claim",
				glyph = "A",
				onClick = function()
					if busy then
						return
					end
					busy = true
					local r = Session.sendAndWait({ type = "ClaimInbox" })
					busy = false
					if r and r.ok then
						local g = { gold = 0, tickets = 0 }
						for _, e in r.events or {} do
							if e.type == "InboxClaimed" then
								g.gold += e.gold or 0
								for itemId, n in e.items or {} do
									local item = master.items[itemId]
									if item and item.kind == "ticket" then
										g.tickets += n
									end
								end
							end
						end
						gained = g
						task.delay(2.5, function()
							if gained == g then
								gained = nil
								if body.Parent then
									render()
								end
							end
						end)
					end
					render()
				end,
			})
			claim.LayoutOrder = 2
			claim.Parent = actions
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

Nav.register("ChestList", build)

return {}
