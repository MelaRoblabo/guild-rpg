--!strict
-- ログインボーナスのカレンダー（D-155・D-208：まとめの後に1回・D-231 ⑬・D-232 ④）。その日の最初のログインで出す。
--   - 羊皮紙の面（1200×466）。左＝7日目の大きな札（ログイン用のユニーク、いなければレアな宝箱＋チケット）。
--     7日目が近いほど明るく。左上に7日目までの残りの日数、右上に「7」。7日目に受け取ったら判子。
--   - 右＝1〜6日目のマス（3×2）。受け取った日は判子＋暗く、今日のマスは琥珀の輪と判子を大きく、中身を数字で（受け取り箱へ届く）。
--     ほかの日はアイコンだけ。
--   - × はない。右下の金＝次へ（▶）だけ。

local Chest = require("@game/ReplicatedStorage/Core/Chest")
local Formulas = require("@game/ReplicatedStorage/Core/Formulas")
local Game = require("@game/ReplicatedStorage/Core/Game")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local HubState = require("../../hub/HubState")
local LoginFlow = require("../../login/LoginFlow")
local Nav = require("../../ui/Nav")
local Root = require("../../ui/Root")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local Words = require("../../ui/Words")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local ICON = {
	chest = "▣",
	itm_slot_ticket = Components.icon.ticket,
	itm_potion_appearance_change = "🎲",
	itm_potion_appearance_keep = "🧪",
}
local DAYS = 7

local function lineIcon(l: LoginFlow.RewardLine): (string, Color3)
	if l.kind == "gold" then
		return Components.icon.coin, C.coinGold
	elseif l.kind == "chest" then
		return ICON.chest, C.bronzeHi
	end
	return ICON[l.id or ""] or "◈", C.inkLight
end

local function stamp(parent: GuiObject, size: number, transparency: number)
	local s: Frame = new("Frame", {
		Name = "Stamp",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		Rotation = -14,
		BackgroundTransparency = 1,
		ZIndex = 6,
		[CHILDREN] = { Components.corner(size / 2), Components.stroke(C.bronze, 6, transparency) },
		Parent = parent,
	})
	local l = Components.text({ text = Components.icon.check, size = math.floor(size * 0.5), color = C.bronze })
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, 0.5)
	l.TextTransparency = transparency
	l.ZIndex = 6
	l.Parent = s
end

local function dayBadge(parent: GuiObject, day: number, size: number, fill: Color3, ink: Color3)
	local b: Frame = new("Frame", {
		Name = "Day",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = fill,
		ZIndex = 4,
		[CHILDREN] = { Components.corner(size / 2), Components.stroke(C.bronze, 2) },
		Parent = parent,
	})
	local l = Components.text({ text = tostring(day), size = 21, color = ink, font = Tokens.font.display })
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, 0.5)
	l.ZIndex = 5
	l.Parent = b
	return b
end

local function build(params: any?, _api: Nav.Api): Nav.Built
	local bonus = (params :: any).loginBonus :: any
	local onNext = (params :: any).onNext :: () -> ()
	local view = Session.view
	local today = bonus.day :: number
	local band = Root.bandBottom()
	local frame: Frame = new("Frame", {
		Name = "LoginCalendar",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	local panel, content = Components.panel({
		size = UDim2.new(1, -80, 0, 466),
		position = UDim2.fromOffset(40, band + 16),
	})
	panel.Name = "Panel"
	panel.Parent = frame
	local base = if view then Chest.baseDungeon(view, master) else nil
	local function goldOf(mult: number): number
		return if base then Formulas.rewardGold(base, mult, master.K) else 0
	end

	-- 左：7日目
	local t = (today - 1) / (DAYS - 1)
	local hero: Frame = new("Frame", {
		Name = "Day7",
		Size = UDim2.new(0, 420, 1, 0),
		BackgroundColor3 = C.ch13,
		[CHILDREN] = {
			Components.corner(8),
			Components.gradient(C.ch28, C.ch10),
		},
		Parent = content,
	})
	if today == DAYS then
		Components.stroke(C.selAmber, 3).Parent = hero
	end
	new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(360, 360),
		BackgroundColor3 = C.rewardGlow,
		BackgroundTransparency = 0.97 - 0.12 * t,
		[CHILDREN] = { Components.corner(180) },
		Parent = hero,
	})
	-- 7日目の中身：その周のログイン用のユニーク（いなければ fallback）
	local unique = if bonus.day == DAYS and bonus.uniqueId then master.uniques[bonus.uniqueId] else nil
	if unique == nil and view then
		local cal = Game.query.loginCalendar(view, Session.now(), master)
		unique = if cal.uniqueId then master.uniques[cal.uniqueId] else nil
	end
	local medal: Frame = new("Frame", {
		Name = "Medal",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(220, 220),
		BackgroundColor3 = C.ch16,
		[CHILDREN] = { Components.corner(110), Components.stroke(C.bronze, 6) },
		Parent = hero,
	})
	local medalIcon = Components.text({
		text = if unique then Components.icon.party else ICON.chest,
		size = 110,
		color = C.bronzeHi,
		font = Tokens.font.number,
	})
	medalIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	medalIcon.Position = UDim2.fromScale(0.5, 0.5)
	medalIcon.TextTransparency = 0.6 * (1 - t)
	medalIcon.Parent = medal
	local foot: Frame = new("Frame", {
		Name = "Foot",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.new(1, -32, 0, 60),
		BackgroundColor3 = C.ch10,
		[CHILDREN] = {
			Components.corner(10),
			Components.stroke(C.bronze, 2),
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 22),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = hero,
	})
	if unique then
		local name = Components.text({
			text = unique.nameEn or unique.name,
			size = 23,
			color = C.inkLight,
			font = Tokens.font.display,
		})
		name.Parent = foot
	else
		for i, l in LoginFlow.dayRewards(master.loginBonus.fallback, goldOf) do
			local icon = lineIcon(l)
			local tx = Components.text({
				text = icon .. " ×" .. HubState.formatNumber(l.n),
				size = 25,
				color = C.inkLight,
				font = Tokens.font.number,
			})
			tx.LayoutOrder = i
			tx.Parent = foot
		end
	end
	local seven = dayBadge(hero, DAYS, 52, C.ch75, C.inkDark)
	seven.AnchorPoint = Vector2.new(1, 0)
	seven.Position = UDim2.new(1, -14, 0, 14)
	local left = DAYS - today
	if left > 0 then
		local chip = Components.chip("🕒", tostring(left), C.inkLight)
		chip.Name = "DaysLeft"
		chip.Position = UDim2.fromOffset(14, 14)
		chip.ZIndex = 4
		chip.Parent = hero
	else
		stamp(hero, 160, 0)
	end

	-- 右：1〜6日目
	local grid: Frame = new("Frame", {
		Name = "Days",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(1, -444, 1, 0),
		BackgroundColor3 = C.ch50,
		[CHILDREN] = {
			Components.corner(8),
			Components.padding(10, 10, 10, 10),
			new("UIGridLayout", {
				CellSize = UDim2.new(1 / 3, -7, 0.5, -5),
				CellPadding = UDim2.fromOffset(10, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = content,
	})
	for day = 1, DAYS - 1 do
		local state = LoginFlow.cellState(day, today)
		local cell: Frame = new("Frame", {
			Name = "Day" .. day,
			LayoutOrder = day,
			BackgroundColor3 = if state == "past" then C.ch68 else C.ch75,
			[CHILDREN] = { Components.corner(8) },
			Parent = grid,
		})
		if state == "today" then
			Components.stroke(C.selAmber, 3).Parent = cell
		end
		dayBadge(cell, day, 40, C.ch45, C.inkLight)
		local lines = LoginFlow.dayRewards(master.loginBonus.days[day], goldOf)
		local list: Frame = new("Frame", {
			Name = "Rewards",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, if state == "today" then 22 else 0, 0.5, 0),
			Size = UDim2.new(1, if state == "today" then -64 else -20, 1, -20),
			BackgroundTransparency = 1,
			[CHILDREN] = {
				new("UIListLayout", {
					FillDirection = if state == "today"
						then Enum.FillDirection.Vertical
						else Enum.FillDirection.Horizontal,
					Wraps = true,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, if state == "today" then 6 else 10),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = cell,
		})
		for i, l in lines do
			local icon, color = lineIcon(l)
			if state == "today" then
				-- 今日のマス：中身を数字で
				local row: Frame = new("Frame", {
					LayoutOrder = i,
					Size = UDim2.new(1, 0, 0, 34),
					BackgroundColor3 = C.ch13,
					[CHILDREN] = {
						Components.corner(8),
						Components.padding(0, 12, 0, 6),
						new("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0, 8),
						}),
					},
					Parent = list,
				})
				local a = Components.text({ text = icon, size = 21, color = color, font = Tokens.font.number })
				a.LayoutOrder = 1
				a.Parent = row
				local b = Components.text({
					text = (if l.kind == "gold" then "" else "×") .. HubState.formatNumber(l.n),
					size = 23,
					color = C.numHi,
					font = Tokens.font.number,
				})
				b.LayoutOrder = 2
				b.Parent = row
			else
				local ic: Frame = new("Frame", {
					LayoutOrder = i,
					Size = UDim2.fromOffset(52, 52),
					BackgroundColor3 = C.ch16,
					BackgroundTransparency = if state == "past" then 0.55 else 0,
					[CHILDREN] = { Components.corner(26), Components.stroke(C.bronze, 2) },
					Parent = list,
				})
				local g = Components.text({ text = icon, size = 25, color = color, font = Tokens.font.number })
				g.AnchorPoint = Vector2.new(0.5, 0.5)
				g.Position = UDim2.fromScale(0.5, 0.5)
				g.TextTransparency = if state == "past" then 0.55 else 0
				g.Parent = ic
			end
		end
		if state == "past" then
			stamp(cell, 120, 0.4)
		elseif state == "today" then
			stamp(cell, 150, 0.6) -- 今日の中身を読めるように薄く
		end
	end

	local nextBtn = Components.button({
		kind = "gold",
		width = 320,
		icon = "▶",
		label = Words.next,
		name = "Next",
		glyph = "A",
		onClick = onNext,
	})
	nextBtn.AnchorPoint = Vector2.new(1, 1)
	nextBtn.Position = UDim2.new(1, -40, 1, -24)
	nextBtn.Parent = frame
	return { frame = frame }
end

Nav.register("LoginCalendar", build)

return {}
