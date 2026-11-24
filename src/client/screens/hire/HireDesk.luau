--!strict
-- S-21a 受付（D-220・D-226）。受付嬢のバストアップと吹き出し、壁に今週の訪問者のポスター。
-- 右下のベル（雇用費つき）で候補を呼ぶ。在籍がいっぱいなら押せず、警告の札を出す。
-- 途中の雇用があれば、開いたときにその続き（求人票・引き直し）へ進む（D-131）。

local Game = require("@game/ReplicatedStorage/Core/Game")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local HireCommon = require("./HireCommon")
local HubState = require("../../hub/HubState")
local Nav = require("../../ui/Nav")
local Root = require("../../ui/Root")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local function rosterCount(view: any): number
	local n = 0
	for _ in view.adventurers or {} do
		n += 1
	end
	return n
end

local function build(_params: any?, api: Nav.Api): Nav.Built
	local view = Session.view
	-- 途中の雇用があれば続きへ（D-131）
	if view and view.hireSession then
		task.defer(function()
			if view.hireSession.pickedIndex then
				api.replace("HireReroll")
			else
				api.replace("HirePostings")
			end
		end)
	end
	local band = Root.bandBottom()
	local frame = HireCommon.scene("HireDesk")

	-- 壁のポスター（今週の訪問者：D-158・D-226 ①）
	local visitor = view and Game.query.weeklyVisitor(view, Session.now(), master)
	if visitor and visitor.uniqueId then
		local poster: TextButton = new("TextButton", {
			Name = "VisitorPoster",
			Text = "",
			AutoButtonColor = false,
			Position = UDim2.fromOffset(560, band + 60),
			Size = UDim2.fromOffset(180, 224),
			Rotation = 2,
			BackgroundColor3 = C.ch68,
			ZIndex = 2,
			[CHILDREN] = {
				Components.corner(6),
				Components.stroke(C.ch16, 3),
				Components.padding(12, 12, 12, 12),
				new("UIListLayout", {
					Padding = UDim.new(0, 8),
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = frame,
		})
		local face: Frame = new("Frame", {
			LayoutOrder = 1,
			Size = UDim2.fromOffset(110, 110),
			BackgroundColor3 = C.ch45,
			ZIndex = 3,
			[CHILDREN] = { Components.corner(8), Components.stroke(C.rewardGlow, 3) },
			Parent = poster,
		})
		local star = Components.text({ text = "★", size = 40, color = C.rewardGlow, font = Tokens.font.number })
		star.AutomaticSize = Enum.AutomaticSize.None
		star.Size = UDim2.fromScale(1, 1)
		star.ZIndex = 4
		star.Parent = face
		local days = math.max(0, math.ceil((visitor.nextWeekAt - Session.now()) / 86400))
		local d = Components.chip("▦", tostring(days), C.inkLight)
		d.LayoutOrder = 2
		d.ZIndex = 3
		d.Parent = poster
		if visitor.owned then
			local check = Components.text({ text = "✓", size = 30, color = C.okGreen, font = Tokens.font.number })
			check.Position = UDim2.new(1, -30, 0, -6)
			check.ZIndex = 5
			check.Parent = poster
		end
	end

	-- 受付嬢（仮：バストアップの代わりの枠）
	local lady, ladyContent = Components.panel({
		size = UDim2.fromOffset(360, 420),
		position = UDim2.fromOffset(120, band + 80),
		dark = true,
	})
	lady.Parent = frame
	local ph = Components.text({ text = "Receptionist (placeholder)", size = 21, color = C.inkLight })
	ph.AutomaticSize = Enum.AutomaticSize.None
	ph.Size = UDim2.fromScale(1, 1)
	ph.Parent = ladyContent
	-- カウンター
	new("Frame", {
		Name = "Counter",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 150),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
		[CHILDREN] = { Components.gradient(C.ch28, C.ch16) },
		Parent = frame,
	})

	local full = view ~= nil and rosterCount(view) >= view.expansions.rosterSize
	local line = if full then "Our roster is full." else "Hire a new adventurer?"
	local bubble = Components.speechBubble(line, 340)
	bubble.Position = UDim2.fromOffset(500, band + 330)
	bubble.ZIndex = 4
	bubble.Parent = frame

	HireCommon.closeTopRight(frame, api.close)

	local actions = HireCommon.actionRow(frame)
	local cost = master.K.hireCost
	local canPay = view ~= nil and view.gold >= cost
	if full then
		local warn = Components.chip("⚠", rosterCount(view) .. "/" .. view.expansions.rosterSize, C.warnDark)
		warn.LayoutOrder = 1
		warn.Parent = actions
	end
	local call = Components.button({
		kind = if full or not canPay then "disabled" else "gold",
		width = 260,
		icon = Components.icon.bell,
		name = "Call",
		cost = HubState.formatNumber(cost),
		glyph = "A",
		onClick = function()
			local r = Session.sendAndWait({ type = "HireStart" })
			if r and r.ok then
				api.replace("HirePostings")
			end
		end,
	})
	call.LayoutOrder = 2
	call.Parent = actions
	return { frame = frame, scrim = 1 }
end

Nav.register("HireDesk", build)

return {}
