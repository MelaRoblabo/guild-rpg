--!strict
-- クエスト（D-153・D-164・D-179・D-191・D-215 ⑦・D-233）。メイン画面の右上の小さなアイコン（✔）から開く。
--   - 羊皮紙の面（幅860、右寄せ）。上の札はクエストのアイコン。左＝デイリー、右＝ウィークリー。
--   - 見出し：Daily／Weekly の語＋区切りまでの残り時間（D-233 ②）。
--   - 行：1段目＝何をするかの短い英語（アイコンなし：D-233 ①）＋右に報酬の札（一番大きい報酬1つ：④）、
--     2段目＝進みの棒に「18 / 30」（③）。済んだ行は報酬の札を✓に変え、行を暗くして沈める。
--   - 下の段＝全部済んだときのボーナス：★の宝箱の下に済んだ行の数（1 / 3：⑤）、右に中身。全部済むと金の輪。
--   - 達成した行とボーナスに金の Claim。押すとその場で受け取り、獲得の画面（RewardGet）で中身を見せる（受け取り箱を通さない：D-286）。
--     受け取った行は✓にして沈める。× は面の右上の角。

local Calendar = require("@game/ReplicatedStorage/Core/Calendar")
local Chest = require("@game/ReplicatedStorage/Core/Chest")
local Formulas = require("@game/ReplicatedStorage/Core/Formulas")
local Game = require("@game/ReplicatedStorage/Core/Game")
local Rebirth = require("@game/ReplicatedStorage/Core/Rebirth")
local Art = require("../../ui/Art")
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
local Words = require("../../ui/Words")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local deps = { nextDayStart = Calendar.nextDayStart, nextWeekStart = Calendar.nextWeekStart }
local REWARD_ICON = { chest = "@chest", ticket = Components.icon.ticket, gold = Components.icon.coin }

-- 受け取った中身（Inbox.grant の形）を獲得の画面の札にする（D-286）
local function tilesOf(r: any): { any }
	local tiles = {}
	if r == nil then
		return tiles
	end
	if (r.gold or 0) > 0 then
		table.insert(tiles, { kind = "gold", n = r.gold })
	end
	local chests = 0
	for _, c in r.chests or {} do
		chests += c.count
	end
	if chests > 0 then
		table.insert(tiles, { kind = "chest", n = chests })
	end
	local ids = {}
	for id in r.items or {} do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		table.insert(tiles, { kind = "item", id = id, n = r.items[id] })
	end
	return tiles
end

-- 受け取るコマンドを送り、獲得の画面を重ねる（D-286）
local busy = false
local function claim(cmd: any, api: Nav.Api)
	if busy then
		return
	end
	busy = true
	local ok, r = pcall(Session.sendAndWait, cmd)
	busy = false
	if ok and r and r.ok then
		for _, e in r.events or {} do
			if e.type == "QuestClaimed" or e.type == "QuestBonusClaimed" then
				api.open("RewardGet", { tiles = tilesOf(e.rewards) })
			end
		end
	end
end

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
			local bonusClaimable = book.bonusDone and not book.bonusClaimed -- D-286
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
				local claimable = e.done and not e.claimed -- 受け取れる（D-286）
				local sunk = e.done and not claimable
				local r: Frame = new("Frame", {
					Name = "Row_" .. e.questId,
					LayoutOrder = i,
					Size = UDim2.new(1, 0, 0, if claimable then 86 else 76),
					BackgroundColor3 = if sunk then C.ch68 else C.ch75,
					BackgroundTransparency = if sunk or locked then 0.35 else 0,
					[CHILDREN] = if claimable then { Components.stroke(C.selAmber, 3) } else nil,
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
				if claimable then
					local qid, per = e.questId, period
					local btn = Components.button({
						kind = "gold",
						width = 150,
						label = Words.claim,
						name = "Claim",
						onClick = function()
							claim({ type = "ClaimQuest", period = per, questId = qid }, api)
						end,
					})
					btn.AnchorPoint = Vector2.new(1, 0.5)
					btn.Position = UDim2.fromScale(1, 0.5)
					btn.ZIndex = 3
					btn.Parent = r
				elseif e.done then
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
					Size = UDim2.new(1, if claimable then -164 else 0, 0, 28), -- 受け取れる行は右に Claim
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
			if bonusClaimable then
				local per = period
				local btn = Components.button({
					kind = "gold",
					width = 150,
					label = Words.claim,
					name = "ClaimBonus",
					onClick = function()
						claim({ type = "ClaimQuestBonus", period = per }, api)
					end,
				})
				btn.AnchorPoint = Vector2.new(1, 0.5)
				btn.Position = UDim2.fromScale(1, 0.5)
				btn.ZIndex = 3
				btn.Parent = bonusRow
			end
			-- 「全部終えるともらえる」を、行の数だけの小さなチェック枠が埋まっていく形で見せる（D-269 ②。▣★ 0/3 では分からなかった）
			local bonusWord =
				Components.text({ text = "Bonus", size = 21, color = C.inkDark, font = Tokens.font.display })
			bonusWord.Position = UDim2.fromOffset(2, 6)
			bonusWord.Parent = bonusRow
			local checks: Frame = new("Frame", {
				Name = "Checks",
				Position = UDim2.fromOffset(0, 40),
				Size = UDim2.fromOffset(0, 28),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				[CHILDREN] = {
					new("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = UDim.new(0, 4),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				},
				Parent = bonusRow,
			})
			for j = 1, #book.entries do
				local filled = j <= done
				local box: Frame = new("Frame", {
					Name = "Check" .. j,
					LayoutOrder = j,
					Size = UDim2.fromOffset(24, 24),
					BackgroundColor3 = if filled then C.okGreen else C.ch13,
					[CHILDREN] = { Components.corner(5), Components.stroke(C.ch16, 2) },
					Parent = checks,
				})
				if filled then
					local ok =
						Components.text({ text = "✓", size = 21, color = C.inkDark, font = Tokens.font.number })
					ok.AutomaticSize = Enum.AutomaticSize.None
					ok.Size = UDim2.fromScale(1, 1)
					ok.Parent = box
				end
			end
			local items: Frame = new("Frame", {
				Name = "Items",
				Position = UDim2.fromOffset(124, 0),
				Size = UDim2.new(1, if bonusClaimable then -284 else -124, 1, 0),
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
			-- ボーナスの1つ：背景なしの小さな「絵＋数」（列の高さに2行で収める）
			local function compact(text: string): (Frame, Frame)
				k += 1
				local f: Frame = new("Frame", {
					Name = "Reward" .. k,
					LayoutOrder = k,
					Size = UDim2.fromOffset(0, 30),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					[CHILDREN] = {
						new("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0, 4),
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
					},
					Parent = items,
				})
				local pic: Frame = new("Frame", {
					Name = "Pic",
					LayoutOrder = 1,
					Size = UDim2.fromOffset(26, 26),
					BackgroundTransparency = 1,
					Parent = f,
				})
				local t = Components.text({ text = text, size = 21, color = C.inkDark, font = Tokens.font.number })
				t.LayoutOrder = 2
				t.Parent = f
				return f, pic
			end
			local function chip(icon: string, text: string)
				local _, pic = compact(text)
				local g = Components.text({ text = icon, size = 21, color = C.inkDark, font = Tokens.font.number })
				g.AutomaticSize = Enum.AutomaticSize.None
				g.Size = UDim2.fromScale(1, 1)
				g.Parent = pic
			end
			if bonus.goldMult then
				chip(Components.icon.coin, HubState.formatNumber(Formulas.rewardGold(base, bonus.goldMult, master.K)))
			end
			for _, c in bonus.chests or {} do
				chip("@chest", "×" .. c.count)
			end
			-- 品は絵（D-269 ④。◈ の記号だけでは分からなかった）。列の高さが決まっているので名前は入れず、絵と数
			for itemId, n in bonus.items or {} do
				local def = master.items[itemId]
				local _, pic = compact("×" .. n)
				if not Art.put(pic, Art.item(itemId)) then
					local g = Components.text({
						text = if def and def.kind == "ticket" then Components.icon.ticket else "◈",
						size = 21,
						color = C.inkDark,
						font = Tokens.font.number,
					})
					g.Parent = pic
				end
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
