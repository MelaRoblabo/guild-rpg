--!strict
-- S-01 ログイン時のまとめ（D-109・D-132・D-161・D-162・D-164・D-208・D-231・D-232）。ログインで留守の間の出来事があれば1枚だけ出す。
--   - 羊皮紙の面（1200×466）。左の凹み＝パーティごとの行：番号・状態（⇄＝留守の間も出た／⌂＝出なかった＋赤い！）・
--     メンバーの顔（Lv が上がった人に▲）・持ち帰った宝箱の数。下の行＝持ち帰ったゴールドの合計と、上がったギルドLv。
--   - 右の上＝休息ボーナス：月の円に水色がたまる（上限に対する割合）＋「XP ×2」。右の下＝受け取り箱（届いたものの件数と！）。
--   - × はない。右下の金＝次へ（▶）だけ（D-231 ⑬・D-232 ④）。次へで、カットイン（最大1回）→ カレンダー（1回）へ。
--   - 休息ボーナスは、Roblox で弧が描けないため、月の円に下から水色がたまる形で出す（D-238 ①）。

local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local HubState = require("../../hub/HubState")
local LoginFlow = require("../../login/LoginFlow")
local Nav = require("../../ui/Nav")
local Root = require("../../ui/Root")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local I = { loop = "⇄", stay = Components.icon.home, chest = "▣", inbox = "▤", face = Components.icon.party }

local function circle(size: number, fill: Color3, rim: Color3?, rimW: number?): Frame
	local f: Frame = new("Frame", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = fill,
		[CHILDREN] = { Components.corner(size / 2) },
	})
	if rim then
		Components.stroke(rim, rimW or 2).Parent = f
	end
	return f
end

local function glyph(parent: GuiObject, t: string, size: number, color: Color3)
	local l = Components.text({ text = t, size = size, color = color, font = Tokens.font.number })
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, 0.5)
	l.Parent = parent
	return l
end

local function badge(parent: GuiObject, t: string, fill: Color3, ink: Color3, size: number, pos: UDim2)
	local b = circle(size, fill, C.ch75, 2)
	b.Name = "Badge"
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = pos
	b.ZIndex = 4
	b.Parent = parent
	local l = glyph(b, t, 21, ink)
	l.ZIndex = 5
	return b
end

-- 暗い凹みの札（宝箱の数・ゴールドなど）
local function well(icon: string, iconColor: Color3, text: string, h: number): Frame
	local f: Frame = new("Frame", {
		Size = UDim2.fromOffset(0, h),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ch13,
		[CHILDREN] = {
			Components.corner(8),
			Components.padding(0, 18, 0, 14),
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	})
	local a = Components.text({ text = icon, size = 30, color = iconColor, font = Tokens.font.number })
	a.LayoutOrder = 1
	a.Parent = f
	local b = Components.text({ text = text, size = 30, color = C.numHi, font = Tokens.font.number })
	b.Name = "Value"
	b.LayoutOrder = 2
	b.Parent = f
	return f
end

local function build(params: any?, _api: Nav.Api): Nav.Built
	local sum = (params :: any).summary :: LoginFlow.Summary
	local onNext = (params :: any).onNext :: () -> ()
	local view = Session.view
	local band = Root.bandBottom()
	local frame: Frame = new("Frame", {
		Name = "LoginSummary",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	local panel, content = Components.panel({
		size = UDim2.new(1, -80, 0, 466),
		position = UDim2.fromOffset(40, band + 16),
	})
	panel.Name = "Panel"
	panel.Parent = frame

	-- 左：パーティの行と、ゴールド・ギルドLv
	local left: Frame = new("Frame", {
		Name = "Parties",
		Size = UDim2.new(1, -372, 1, 0),
		BackgroundColor3 = C.ch50,
		[CHILDREN] = {
			Components.corner(8),
			Components.padding(10, 10, 10, 10),
			new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		},
		Parent = content,
	})
	for order, p in sum.parties do
		local row: Frame = new("Frame", {
			Name = "Party" .. p.index,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 86),
			BackgroundColor3 = if p.moved then C.ch75 else C.ch68,
			[CHILDREN] = {
				Components.corner(8),
				Components.padding(0, 16, 0, 16),
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 14),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = left,
		})
		local num = circle(52, C.ch45, C.bronze, 3)
		num.LayoutOrder = 1
		num.Parent = row
		glyph(num, tostring(p.index), 25, C.inkLight).FontFace = Tokens.font.display
		local st = circle(44, C.ch13, C.bronze, 2)
		st.Name = "State"
		st.LayoutOrder = 2
		st.Parent = row
		glyph(st, if p.moved then I.loop else I.stay, 25, C.inkLight)
		if not p.moved then
			badge(st, "!", C.notice, C.inkWhite, 28, UDim2.fromScale(1, 0))
		end
		local faces: Frame = new("Frame", {
			Name = "Faces",
			LayoutOrder = 3,
			Size = UDim2.new(1, -(52 + 44 + 14 * 3 + 170), 0, 56),
			BackgroundTransparency = 1,
			[CHILDREN] = {
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 8),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = row,
		})
		for i, m in p.members do
			local f = circle(56, C.ch28, C.ch16, 2)
			f.Name = "Face" .. i
			f.LayoutOrder = i
			f.Parent = faces
			glyph(f, I.face, 30, C.inkLight)
			if m.up then
				badge(f, Components.icon.up, C.ch75, C.up, 26, UDim2.new(1, -4, 1, -4))
			end
		end
		if p.moved then
			local chest = well(I.chest, C.bronzeHi, "+" .. HubState.formatNumber(p.chests), 60)
			chest.Name = "Chests"
			chest.LayoutOrder = 4
			chest.Parent = row
		end
		if not p.moved then
			row.BackgroundTransparency = 0.3
		end
	end
	local foot: Frame = new("Frame", {
		Name = "Totals",
		LayoutOrder = 99,
		Size = UDim2.new(1, 0, 0, 88),
		BackgroundColor3 = C.ch75,
		[CHILDREN] = {
			Components.corner(8),
			Components.padding(0, 16, 0, 16),
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 12),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = left,
	})
	-- 増えたものだけ出す（D-218 ⑥）。どちらもなければ行ごと出さない
	foot.Visible = sum.gold > 0 or sum.guildLevel ~= nil
	if sum.gold > 0 then
		local gold = well(Components.icon.coin, C.coinGold, "+" .. HubState.formatNumber(sum.gold), 60)
		gold.Name = "Gold"
		gold.LayoutOrder = 1
		gold.Parent = foot
	end
	if sum.guildLevel then
		local lv = well("Lv", C.inkLight, tostring(sum.guildLevel) .. " " .. Components.icon.up, 60)
		lv.Name = "GuildLevel"
		lv.LayoutOrder = 2
		lv.Parent = foot
		local v = lv:FindFirstChild("Value") :: TextLabel
		v.TextColor3 = C.lvOrange
	end

	-- 右：休息ボーナスと受け取り箱
	local right: Frame = new("Frame", {
		Name = "Right",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 348, 1, 0),
		BackgroundTransparency = 1,
		[CHILDREN] = { new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }) },
		Parent = content,
	})
	local rest: Frame = new("Frame", {
		Name = "Rest",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0.62, -6),
		BackgroundColor3 = C.ch13,
		[CHILDREN] = { Components.corner(8) },
		Parent = right,
	})
	local moon: CanvasGroup = new("CanvasGroup", {
		Name = "Moon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 18),
		Size = UDim2.fromOffset(150, 150),
		BackgroundColor3 = C.ch10,
		[CHILDREN] = { Components.corner(75) },
		Parent = rest,
	})
	local share = if view then LoginFlow.restShare(view, master) else 0
	local fill: Frame = new("Frame", {
		Name = "Fill",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = C.rest,
		Parent = moon,
	})
	new("UIStroke", { Color = C.ch16, Thickness = 6, Parent = moon })
	-- たまる動き（D-162：休息ボーナスが月にたまる）
	task.defer(function()
		if fill.Parent then
			game:GetService("TweenService")
				:Create(fill, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = UDim2.fromScale(1, share),
				})
				:Play()
		end
	end)
	local xp = Components.chip("", "XP ×" .. tostring(master.K.restBonusExpMult))
	xp.Name = "RestMult"
	xp.AnchorPoint = Vector2.new(0.5, 1)
	xp.Position = UDim2.new(0.5, 0, 1, -14)
	xp.Parent = rest
	local box: Frame = new("Frame", {
		Name = "Inbox",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0.38, -6),
		BackgroundColor3 = C.ch13,
		[CHILDREN] = {
			Components.corner(8),
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 22),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = right,
	})
	local count = if view then LoginFlow.inboxCount(view) else 0
	local boxIcon = circle(96, C.ch16, C.bronze, 3)
	boxIcon.Name = "Icon"
	boxIcon.LayoutOrder = 1
	boxIcon.Parent = box
	glyph(boxIcon, I.inbox, 52, C.bronzeHi)
	if count > 0 then
		badge(boxIcon, "!", C.notice, C.inkWhite, 34, UDim2.new(1, -8, 0, 8))
		local n = well("×", C.inkLight, HubState.formatNumber(count), 60)
		n.Name = "Count"
		n.LayoutOrder = 2
		n.Parent = box
	else
		box.BackgroundTransparency = 0.45
	end

	-- 右下の金：次へ
	local nextBtn = Components.button({
		kind = "gold",
		width = 320,
		icon = "▶",
		name = "Next",
		glyph = "A",
		onClick = onNext,
	})
	nextBtn.AnchorPoint = Vector2.new(1, 1)
	nextBtn.Position = UDim2.new(1, -40, 1, -24)
	nextBtn.Parent = frame
	return { frame = frame }
end

Nav.register("LoginSummary", build)

return {}
