--!strict
-- S-20 ギルド＝受付の広間（D-231 ③。S-21a 受付をまとめた）。下メニューのギルドから開く。
--   - 受付嬢のバストアップと吹き出し、壁に今週の訪問者のポスター（D-158・D-226）。
--   - 主役は右下の金のベル（雇用費つき）。在籍がいっぱいなら押せず、警告の札（押すと在籍の拡張へ：D-232 ③）。
--   - 左の壁にギルドの旗：ギルドの印＋Lv＋経験値の棒（数字なし：D-218 ③）＋次の Lv の報酬。上限 Lv は棒を満たし、報酬を消し、Lv を金の光に（D-232 ②）。
--   - 旗の下に拡張の入口（茶・ハンマー）。買える拡張があるときだけ NEW（§5.1）。押すと S-22。
--   - ベルの角に雇用の印（無料の引き直しの数、新しいパーティ枠＝空のパーティがあるとき光る：D-232 ①）。
--   途中の雇用があれば、開いたときにその続き（求人票・引き直し）へ進む（D-131）。

local Game = require("@game/ReplicatedStorage/Core/Game")
local Guild = require("@game/ReplicatedStorage/Core/Guild")
local Party = require("@game/ReplicatedStorage/Core/Party")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local ExpandInfo = require("../../guild/ExpandInfo")
local HireCommon = require("./HireCommon")
local HubState = require("../../hub/HubState")
local Nav = require("../../ui/Nav")
local Root = require("../../ui/Root")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local Words = require("../../ui/Words")
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
			Position = UDim2.fromOffset(836, band + 170), -- 右後ろの壁（S-20 の見本）
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
		position = UDim2.fromOffset(260, band + 80), -- 左の壁の旗を避ける（S-20）
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

	-- 左の壁：ギルドの旗（D-074・D-232 ②）
	if view then
		local lv = view.guild.level
		local maxed = lv >= Guild.maxLevel(master)
		local need = Guild.expToNext(lv, master)
		local banner: TextButton = new("TextButton", {
			Name = "GuildBanner",
			Text = "",
			AutoButtonColor = false,
			Position = UDim2.fromOffset(28, band + 22),
			Size = UDim2.fromOffset(200, 276),
			BackgroundColor3 = C.ch68,
			ZIndex = 5,
			[CHILDREN] = {
				Components.stroke(C.bronze, 4),
				Components.padding(14, 12, 30, 12),
				new("UIListLayout", {
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding = UDim.new(0, 8),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = frame,
		})
		local mark = Components.text({ text = "⌂", size = 25, color = C.bronzeHi, font = Tokens.font.number })
		mark.LayoutOrder = 1
		mark.ZIndex = 6
		mark.Parent = banner
		local lvPill = Components.chip("Lv", tostring(lv), if maxed then C.rewardGlow else C.lvOrange)
		lvPill.LayoutOrder = 2
		lvPill.ZIndex = 6
		lvPill.Parent = banner
		if maxed then
			Components.stroke(C.rewardGlow, 3).Parent = lvPill
		end
		local track: Frame = new("Frame", {
			Name = "Exp",
			LayoutOrder = 3,
			Size = UDim2.fromOffset(164, 24),
			BackgroundColor3 = C.barTrack,
			ZIndex = 6,
			[CHILDREN] = { Components.corner(8) },
			Parent = banner,
		})
		new("Frame", {
			Name = "Fill",
			Position = UDim2.fromOffset(3, 3),
			Size = UDim2.new(if maxed or need == nil then 1 else math.clamp(view.guild.exp / need, 0, 1), -6, 1, -6),
			BackgroundColor3 = C.barFill,
			ZIndex = 7,
			[CHILDREN] = { Components.corner(6) },
			Parent = track,
		})
		local nextLv = master.raw.GuildLevels.levels[lv + 1]
		if not maxed and nextLv then
			local rewards: Frame = new("Frame", {
				Name = "NextReward",
				LayoutOrder = 4,
				Size = UDim2.fromOffset(176, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				ZIndex = 6,
				[CHILDREN] = {
					new("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						Wraps = true,
						Padding = UDim.new(0, 6),
					}),
				},
				Parent = banner,
			})
			for itemId, n in nextLv.rewards do
				local def = master.items[itemId]
				local icon = if def and def.kind == "ticket" then Components.icon.ticket else "◈"
				local chip = Components.chip(icon, "×" .. n, C.bronzeHi)
				chip.ZIndex = 7
				chip.Parent = rewards
			end
		end
		-- 旗の下：拡張の入口（D-232 ③）。買える拡張があるときだけ NEW
		local expand: TextButton = new("TextButton", {
			Name = "Expand",
			Text = "🔨 " .. Words.expand, -- 語を添える（D-245）
			TextSize = 21,
			FontFace = Tokens.font.display,
			TextColor3 = C.inkLight,
			AutoButtonColor = false,
			Position = UDim2.fromOffset(60, band + 314),
			Size = UDim2.fromOffset(150, 66),
			BackgroundColor3 = C.secondary,
			ZIndex = 6,
			[CHILDREN] = { Components.corner(18), Components.stroke(C.secondaryRim, 3) },
			Parent = frame,
		})
		expand.Activated:Connect(function()
			api.open("Expand")
		end)
		if ExpandInfo.anyBuyable(view, master) then
			new("TextLabel", {
				Name = "New",
				Text = "NEW",
				TextSize = 21,
				FontFace = Tokens.font.number,
				TextColor3 = C.inkDark,
				BackgroundColor3 = C.okGreen,
				Position = UDim2.new(1, -28, 0, -14),
				Size = UDim2.fromOffset(60, 32),
				ZIndex = 7,
				[CHILDREN] = { Components.corner(16) },
				Parent = expand,
			})
		end
	end

	local actions = HireCommon.actionRow(frame)
	local cost = master.K.hireCost
	local canPay = view ~= nil and view.gold >= cost
	if full then
		-- 満員の札（数字の「20/20」は出さない：D-218 ③）。押すと在籍の拡張へ（D-232 ③）
		local warn: TextButton = new("TextButton", {
			Name = "RosterFull",
			LayoutOrder = 1,
			Text = "♟ " .. Words.full,
			TextSize = 21,
			FontFace = Tokens.font.display,
			TextColor3 = C.warnDark,
			AutoButtonColor = false,
			Size = UDim2.fromOffset(130, 66),
			BackgroundColor3 = C.ch10,
			[CHILDREN] = { Components.corner(33), Components.stroke(C.warnDark, 2) },
			Parent = actions,
		})
		warn.Activated:Connect(function()
			api.open("Expand", { kind = "rosterSize" })
		end)
	end
	local call = Components.button({
		kind = if full or not canPay then "disabled" else "gold",
		width = 260,
		icon = Components.icon.bell,
		label = Words.hire,
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
	-- ベルの角の雇用の印（D-232 ①）：新しいパーティ枠（空のパーティ）があれば光る。なければ無料の引き直しの数
	local emptyParty = false
	for _, p in (view and view.parties) or {} do
		if Party.isEmpty(p) then
			emptyParty = true
		end
	end
	local markText = if emptyParty then "♟✚" else Components.icon.reroll .. master.K.hireFreeRerolls
	new("TextLabel", {
		Name = "HireMark",
		Text = markText,
		TextSize = 21,
		FontFace = Tokens.font.number,
		TextColor3 = if emptyParty then C.inkDark else C.inkLight,
		BackgroundColor3 = if emptyParty then C.rewardGlow else C.ch13,
		Position = UDim2.fromOffset(-12, -12),
		Size = UDim2.fromOffset(64, 32),
		ZIndex = 5,
		[CHILDREN] = { Components.corner(16), Components.stroke(C.bronze, 2) },
		Parent = call,
	})
	return { frame = frame, scrim = 1 }
end

Nav.register("HireDesk", build)

return {}
