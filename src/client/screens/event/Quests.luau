--!strict
-- クエスト（D-153・D-164・D-179・D-191・D-215 ⑦・D-233）。メイン画面の右上の小さなアイコン（✔）から開く。
--   - 羊皮紙の面（幅860、右寄せ）。上の札はクエストのアイコン。左＝デイリー、右＝ウィークリー。
--   - 見出し：Daily／Weekly の語＋区切りまでの残り時間（D-233 ②）。
--   - 行：1段目＝何をするかの短い英語（アイコンなし：D-233 ①）＋右に報酬の札（一番大きい報酬1つ：④）、
--     2段目＝進みの棒に「18 / 30」（③）。済んだ行は報酬の札を✓に変え、行を暗くして沈める。
--   - 下の段＝全部済んだときのボーナス：★の宝箱の下に済んだ行の数（1 / 3：⑤）、右に中身。全部済むと金の輪。
--   - 報酬は達成した瞬間に受け取り箱へ（D-164）。この面に受け取るボタンはない。× は面の右上の角。

local Calendar = require("@game/ReplicatedStorage/Core/Calendar")
local Chest = require("@game/ReplicatedStorage/Core/Chest")
local Formulas = require("@game/ReplicatedStorage/Core/Formulas")
local Game = require("@game/ReplicatedStorage/Core/Game")
local Rebirth = require("@game/ReplicatedStorage/Core/Rebirth")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Guide = require("../../hub/Guide")
local HubState = require("../../hub/HubState")
local Nav = require("../../ui/Nav")
local QuestView = require("../../quest/QuestView")
local Root = require("../../ui/Root")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local WarehouseCommon = require("../warehouse/WarehouseCommon")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local deps = { nextDayStart = Calendar.nextDayStart, nextWeekStart = Calendar.nextWeekStart }
local REWARD_ICON = { chest = "@chest", ticket = Components.icon.ticket, gold = Components.icon.coin }

local function build(_params: any?, api: Nav.Api): Nav.Built
	Guide.done("quests") -- 誘導の最後の段（D-246 ②）
	local band = Root.bandBottom()
	local frame: Frame = new("Frame", {
		Name = "Quests",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	local panel, content = Components.panel({
		size = UDim2.fromOffset(860, 574),
		position = UDim2.new(1, -40, 0, band + 20),
		anchor = Vector2.new(1, 0),
		title = "@quest",
	})
	panel.Name = "Panel"
	panel.Parent = frame
	local close = Components.closeButton(api.close)
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.ZIndex = 20
	close.Parent = panel
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = content,
	})

	local function render()
		body:ClearAllChildren()
		local view = Session.view
		if view == nil then
			return
		end
		local q = Game.query.quests(view, master)
		local now = Session.now()
		local base = Chest.baseDungeon(view, master)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = body,
		})
		for col, period in { "daily", "weekly" } do
			local book = q[period]
			local bonus = if period == "daily" then master.K.questDailyBonus else master.K.questWeeklyBonus
			local done = 0
			for _, e in book.entries do
				if e.done then
					done += 1
				end
			end
			local all = #book.entries > 0 and done == #book.entries
			local b: Frame = new("Frame", {
				Name = if period == "daily" then "Daily" else "Weekly",
				LayoutOrder = col,
				Size = UDim2.new(0.5, -6, 1, 0),
				BackgroundColor3 = C.ch50,
				[CHILDREN] = {
					Components.corner(8),
					Components.padding(10, 10, 10, 10),
					new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
				},
				Parent = body,
			})
			-- 見出し：Daily／Weekly と残り時間
			local head: Frame = new("Frame", {
				Name = "Head",
				LayoutOrder = 0,
				Size = UDim2.new(1, 0, 0, 48),
				BackgroundColor3 = C.ch13,
				[CHILDREN] = { Components.corner(8), Components.padding(0, 8, 0, 16) },
				Parent = b,
			})
			local title = Components.text({
				text = if period == "daily" then "Daily" else "Weekly",
				size = 25,
				color = C.inkLight,
				font = Tokens.font.display,
			})
			title.AnchorPoint = Vector2.new(0, 0.5)
			title.Position = UDim2.fromScale(0, 0.5)
			title.Parent = head
			local left = WarehouseCommon.pill("@time", QuestView.left(period, now, deps), 23)
			left.AnchorPoint = Vector2.new(1, 0.5)
			left.Position = UDim2.fromScale(1, 0.5)
			left.Parent = head
			-- 転生できる冒険者がいるか（Rebirth の行の鍵：D-250 ⑦）
			local anyRebirthable = false
			for _, a in view.adventurers or {} do
				if Rebirth.canRebirth(a, master) == nil then
					anyRebirthable = true
					break
				end
			end
			-- 行
			for i, e in book.entries do
				local row = master.quests[e.questId]
				local locked = QuestView.locked(row and row.kind, e, anyRebirthable)
				local r: Frame = new("Frame", {
					Name = "Row_" .. e.questId,
					LayoutOrder = i,
					Size = UDim2.new(1, 0, 0, 76),
					BackgroundColor3 = if e.done then C.ch68 else C.ch75,
					BackgroundTransparency = if e.done or locked then 0.35 else 0,
					[CHILDREN] = { Components.corner(8), Components.padding(6, 10, 7, 14) },
					Parent = b,
				})
				local word = Components.text({
					text = if locked then "" else (if row then row.nameEn else e.questId),
					size = 23,
					color = C.inkDark,
					font = Tokens.font.bodyStrong,
					xAlign = Enum.TextXAlignment.Left,
				})
				word.Position = UDim2.fromOffset(0, 0)
				word.Parent = r
				if locked then
					Components.setParts(word, { "@locked", if row then row.nameEn else e.questId })
				end
				if e.done then
					local ok =
						Components.text({ text = "✓", size = 23, color = C.inkDark, font = Tokens.font.number })
					ok.AnchorPoint = Vector2.new(1, 0)
					ok.Position = UDim2.fromScale(1, 0)
					ok.BackgroundTransparency = 0
					ok.BackgroundColor3 = C.okGreen
					ok.Size = UDim2.fromOffset(30, 30)
					ok.AutomaticSize = Enum.AutomaticSize.None
					new("UICorner", { CornerRadius = UDim.new(0, 15), Parent = ok })
					ok.Parent = r
				else
					local main = QuestView.mainReward(row and row.rewards)
					if main then
						local n = if main.kind == "gold" then Formulas.rewardGold(base, main.n, master.K) else main.n
						local tag = WarehouseCommon.pill(REWARD_ICON[main.kind], "×" .. HubState.formatNumber(n), 21)
						tag.AnchorPoint = Vector2.new(1, 0)
						tag.Position = UDim2.fromScale(1, 0)
						tag.Parent = r
					end
				end
				local track: Frame = new("Frame", {
					Name = "Bar",
					Visible = not locked, -- 鍵の行は進みの棒を出さない（D-250 ⑦）
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.fromScale(0, 1),
					Size = UDim2.new(1, 0, 0, 28),
					BackgroundColor3 = C.barTrack,
					[CHILDREN] = { Components.corner(6) },
					Parent = r,
				})
				new("Frame", {
					Name = "Fill",
					Size = UDim2.fromScale(math.clamp(e.progress / math.max(1, e.target), 0, 1), 1),
					BackgroundColor3 = if e.done then C.okGreen else C.barFill,
					[CHILDREN] = { Components.corner(6) },
					Parent = track,
				})
				local num = Components.text({
					text = HubState.formatNumber(math.min(e.progress, e.target)) .. " / " .. HubState.formatNumber(
						e.target
					),
					size = 23,
					color = C.inkWhite,
					font = Tokens.font.number,
					stroke = true,
				})
				num.AnchorPoint = Vector2.new(0.5, 0.5)
				num.Position = UDim2.fromScale(0.5, 0.5)
				num.Parent = track
			end
			-- 全部済んだときのボーナス（済んだ行の数で行とつなげる）
			local bonusRow: Frame = new("Frame", {
				Name = "Bonus",
				LayoutOrder = 99,
				Size = UDim2.new(1, 0, 0, 80),
				BackgroundColor3 = C.ch75,
				[CHILDREN] = {
					Components.corner(8),
					Components.padding(0, 12, 0, 10),
					if all then Components.stroke(C.selAmber, 3) else nil,
				},
				Parent = b,
			})
			local chestIc =
				Components.text({ text = "▣★", size = 25, color = C.inkDark, font = Tokens.font.number })
			chestIc.Position = UDim2.fromOffset(4, 8)
			chestIc.Parent = bonusRow
			local count = WarehouseCommon.pill("", done .. " / " .. #book.entries, 21, nil)
			count.Position = UDim2.fromOffset(0, 40)
			if all then
				count.BackgroundColor3 = C.okGreen
			end
			count.Parent = bonusRow
			local items: Frame = new("Frame", {
				Name = "Items",
				Position = UDim2.fromOffset(84, 0),
				Size = UDim2.new(1, -84, 1, 0),
				BackgroundTransparency = 1,
				[CHILDREN] = {
					new("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Wraps = true,
						Padding = UDim.new(0, 6),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				},
				Parent = bonusRow,
			})
			local k = 0
			local function chip(icon: string, text: string)
				k += 1
				local p = WarehouseCommon.pill(icon, text, 21)
				p.LayoutOrder = k
				p.Parent = items
			end
			if bonus.goldMult then
				chip(Components.icon.coin, HubState.formatNumber(Formulas.rewardGold(base, bonus.goldMult, master.K)))
			end
			for _, c in bonus.chests or {} do
				chip("@chest", "×" .. c.count)
			end
			for itemId, n in bonus.items or {} do
				local def = master.items[itemId]
				chip(if def and def.kind == "ticket" then Components.icon.ticket else "◈", "×" .. n)
			end
		end
	end

	render()
	local conn = Session.changed:connect(render)
	return {
		frame = frame,
		destroy = function()
			conn.disconnect()
		end,
	}
end

Nav.register("Quests", build)

return {}
