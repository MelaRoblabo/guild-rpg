--!strict
-- S-40 冒険者一覧（D-117・D-119・D-130・D-217・D-218・§5.1）。問い＝「誰を見る？」。カードを押すと S-41。
--   - 6列のカード（肖像・名前・♂♀・転生の★・職業の札・Lv）。左上にパーティの番号と状態の印（パーティなしは何も付けない）。
--   - ティッカー：転生できる人＝赤い「!」、倉庫にもっと良い装備がある人＝緑の▲。保護中＝ピン（D-217）。
--   - 在籍数（14/16）は出さず、上限までの残りを点線の空き枠で見せる。満杯のときだけ右上に警告の札（D-218）。
--   - 上の並んだタブ＝職業系統（全員・Warrior・Scout・Mage・Support）。その右に並べ方のボタン（面で並べ方・向き・状態）。
--     並べ方と向きはサーバーに保存（D-117、SetListPrefs）。

local Game = require("@game/ReplicatedStorage/Core/Game")
local AdvCommon = require("./AdvCommon")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Portrait = require("../../ui/Portrait")
local LevelUpMarks = require("../../hub/LevelUpMarks")
local Nav = require("../../ui/Nav")
local Root = require("../../ui/Root")
local Roster = require("../../adventurers/Roster")
local Screen = require("../Screen")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local Words = require("../../ui/Words")
local master = require("../../Master")

local C = Tokens.color
local I = AdvCommon.icon
local new = Create.new
local CHILDREN = Create.Children
local deps = AdvCommon.deps

local SORT_GLYPH = { level = "Lv", attack = I.attack, maxHp = I.hp, hired = I.bell, rebirths = I.rebirth }
local STATE_GLYPH = { all = I.all, wait = "@cart_waiting", exploring = "@cart_exploring", none = "○" }

local function smallText(text: string, size: number, color: Color3, parent: GuiObject, z: number): TextLabel
	local t = Components.text({ text = text, size = size, color = color, font = Tokens.font.number })
	t.ZIndex = z
	t.Parent = parent
	return t
end

-- 角の丸い印
local function dot(parent: GuiObject, text: string, fill: Color3, ink: Color3, pos: UDim2): TextLabel
	local d: TextLabel = new("TextLabel", {
		Name = "Ticker",
		Text = "",
		TextSize = 21,
		FontFace = Tokens.font.number,
		TextColor3 = ink,
		BackgroundColor3 = fill,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		Size = UDim2.fromOffset(32, 32),
		ZIndex = 12,
		[CHILDREN] = { Components.corner(16), Components.stroke(C.ch13, 2) },
		Parent = parent,
	})
	Components.setText(d, text) -- 「@キー」なら絵（D-256）
	return d
end

local function card(view: any, adv: any, order: number, onClick: () -> ()): TextButton
	local job = master.jobs[adv.jobId]
	local b: TextButton = new("TextButton", {
		Name = "Adv_" .. adv.uid,
		LayoutOrder = order,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.ch17,
		ZIndex = 8,
		[CHILDREN] = { Components.corner(10) },
	})
	-- 肖像（仮）
	local pic: Frame = new("Frame", {
		Name = "Portrait",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 0, 112),
		BackgroundColor3 = C.ch13,
		ZIndex = 9,
		[CHILDREN] = { Components.corner(6) },
		Parent = b,
	})
	local face = smallText(I.party, 56, C.ch45, pic, 10)
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.55)
	if Portrait.fill(pic, adv.appearanceId) then
		face.Visible = false
	end
	-- 顔の下の帯：パーティの番号と状態（顔にかからないように：D-269 ②）
	local badge = AdvCommon.partyBadge(view, adv.uid)
	if badge then
		local tag: Frame = new("Frame", {
			Name = "Party",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromOffset(0, 34),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.ch10,
			BackgroundTransparency = 0.15,
			ZIndex = 11,
			[CHILDREN] = { Components.corner(6), Components.padding(0, 10, 0, 8) },
			Parent = pic,
		})
		local bt = smallText("", 21, C.inkLight, tag, 12)
		bt.Size = UDim2.fromOffset(0, 34)
		Components.setParts(bt, badge)
	end
	-- 右上：転生できる「!」、もっと良い装備の ▲
	if adv.level >= adv.levelCap then
		dot(b, "!", C.notice, C.inkWhite, UDim2.new(1, -4, 0, 4))
	elseif Roster.anyBetterGear(view, adv, master, deps) then
		dot(b, I.up, C.okGreen, C.inkDark, UDim2.new(1, -4, 0, 4))
	end
	if adv.locked then
		dot(b, I.pin, C.ch10, C.inkLight, UDim2.new(1, -24, 0, 98))
	end
	-- 名前・性別・転生の★
	local name = Components.text({
		text = adv.name .. " " .. (if adv.gender == "f" then I.female else I.male),
		size = 23,
		color = C.inkLight,
		font = Tokens.font.display,
		xAlign = Enum.TextXAlignment.Left,
	})
	name.AutomaticSize = Enum.AutomaticSize.None
	name.Position = UDim2.fromOffset(10, 124)
	name.Size = UDim2.new(1, -60, 0, 32)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 10
	name.Parent = b
	if (adv.rebirthCount or 0) > 0 then
		local rb = smallText(string.rep(Components.plain(I.rebirth), math.min(adv.rebirthCount, 3)), 21, C.numHi, b, 10)
		rb.AnchorPoint = Vector2.new(1, 0)
		rb.Position = UDim2.new(1, -8, 0, 128)
	end
	-- 職業の札と Lv
	local jobTag: Frame = new("Frame", {
		Name = "Job",
		Position = UDim2.fromOffset(8, 162),
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ch13,
		ZIndex = 10,
		[CHILDREN] = { Components.corner(17), Components.padding(0, 8, 0, 8) },
		Parent = b,
	})
	local jt = smallText("", 21, C.inkLight, jobTag, 11)
	jt.Size = UDim2.fromOffset(0, 34)
	Components.setParts(jt, {
		if job and job.attackType == "magic" then "@job_magic" else "@job_physical",
		if job then job.nameEn else adv.jobId,
	})
	local lv: Frame = new("Frame", {
		Name = "Level",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 162),
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ch13,
		ZIndex = 10,
		[CHILDREN] = { Components.corner(17), Components.padding(0, 8, 0, 8) },
		Parent = b,
	})
	smallText("Lv " .. adv.level, 21, C.lvOrange, lv, 11).Size = UDim2.fromOffset(0, 34)
	b.Activated:Connect(onClick)
	return b
end

local function build(_params: any?, api: Nav.Api): Nav.Built
	LevelUpMarks.seenAll() -- Adventurers のボタンの ▲ の札を消す（D-269 ③）
	local band = Root.bandBottom()
	local frame = Screen.scene("AdvList")
	Screen.closeTopRight(frame, api.close)
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local line = "all"
	local stateFilter = "all"
	local sheetOpen = false
	local busy = false
	local render: () -> ()

	local function send(cmd: any)
		busy = true
		Session.sendAndWait(cmd)
		busy = false
		render()
	end

	render = function()
		body:ClearAllChildren()
		local view = Session.view
		if view == nil then
			return
		end
		local prefs = Game.query.listPrefs(view, master)

		-- 職業系統のタブ
		local tabs: Frame = new("Frame", {
			Name = "Lines",
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
		for i, id in Roster.LINES do
			local on = line == id
			local b: TextButton = new("TextButton", {
				Name = "Line_" .. id,
				LayoutOrder = i,
				Text = if id == "all" then Words.all else AdvCommon.lineWord[id], -- 語にする（D-245）
				TextSize = 21,
				FontFace = Tokens.font.number,
				TextColor3 = if on then C.inkDark else C.inkLight,
				AutoButtonColor = false,
				Size = UDim2.fromOffset(96, 66),
				BackgroundColor3 = if on then C.selAmber else C.ch28,
				ZIndex = 11,
				[CHILDREN] = { Components.corner(33) },
				Parent = tabs,
			})
			b.Activated:Connect(function()
				line = id
				render()
			end)
		end
		-- 並べ方のボタン（今の並べ方と向き）
		local sortBtn: TextButton = new("TextButton", {
			Name = "Sort",
			Text = "",
			TextSize = 21,
			FontFace = Tokens.font.number,
			TextColor3 = C.inkLight,
			AutoButtonColor = false,
			Position = UDim2.fromOffset(40 + 8 + 5 * 96 + 4 * 4 + 28, band + 16),
			Size = UDim2.fromOffset(150, 66),
			BackgroundColor3 = if sheetOpen then C.selAmber else C.secondary,
			ZIndex = 10,
			[CHILDREN] = { Components.corner(18), Components.stroke(C.secondaryRim, 3) },
			Parent = body,
		})
		Components.setParts(sortBtn, {
			Words.sort,
			SORT_GLYPH[prefs.advSort],
			if prefs.advDesc then Components.icon.down else Components.icon.up,
		})
		sortBtn.Activated:Connect(function()
			sheetOpen = not sheetOpen
			render()
		end)

		-- 満杯のときだけ右上に警告の札（拡張 S-22 は M8-6 のギルドの画面で作る）
		local count = 0
		for _ in view.adventurers do
			count += 1
		end
		local cap = view.expansions.rosterSize
		if count >= cap then
			local chip = Components.chip(I.party, I.warn, C.warnDark)
			chip.Name = "RosterFull"
			chip.AnchorPoint = Vector2.new(1, 0)
			chip.Position = UDim2.new(1, -120, 0, band + 19)
			chip.ZIndex = 12
			chip.Parent = body
		end

		-- カードの並び（暗い木の面）
		local panel, content = Components.panel({
			size = UDim2.new(1, -80, 0, 492),
			position = UDim2.fromOffset(40, band + 98),
			dark = true,
		})
		panel.Name = "Adventurers"
		panel.Parent = body
		local scroll: ScrollingFrame = new("ScrollingFrame", {
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
					CellSize = UDim2.fromOffset(186, 206),
					CellPadding = UDim2.fromOffset(10, 10),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Components.padding(12, 8, 12, 8),
			},
			Parent = content,
		})
		local uids = Roster.list(view, line, stateFilter, prefs, master, deps)
		for i, uid in uids do
			card(view, view.adventurers[uid], i, function()
				api.open("AdvDetail", { uid = uid })
			end).Parent =
				scroll
		end
		-- 上限までの残りを点線の空き枠で（絞り込んでいないときだけ）
		if line == "all" and stateFilter == "all" then
			for k = 1, math.max(0, cap - count) do
				new("Frame", {
					Name = "Empty" .. k,
					LayoutOrder = #uids + k,
					BackgroundColor3 = C.ch17,
					BackgroundTransparency = 0.75,
					ZIndex = 8,
					[CHILDREN] = { Components.corner(10), Components.stroke(C.ch28, 3) },
					Parent = scroll,
				})
			end
		end

		-- 並べ方・状態の面
		if sheetOpen then
			local sheet, sc = Components.panel({
				size = UDim2.fromOffset(620, 250),
				position = UDim2.fromOffset(40 + 8 + 74 + 4 * 96 + 4 * 4 + 28, band + 92),
			})
			sheet.Name = "SortSheet"
			sheet.ZIndex = 30
			sheet.Parent = body
			new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sc })
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
					Parent = sc,
				})
				for i, o in opts do
					local b: TextButton = new("TextButton", {
						Name = "Opt_" .. o.id,
						LayoutOrder = i,
						Text = o.text,
						TextSize = 25,
						FontFace = Tokens.font.number,
						TextColor3 = if o.on then C.inkDark else C.inkLight,
						AutoButtonColor = false,
						Size = UDim2.new(1 / #opts, -4, 0, 66),
						BackgroundColor3 = if o.on then C.selAmber else C.ch28,
						ZIndex = 33,
						[CHILDREN] = { Components.corner(33) },
						Parent = r,
					})
					Components.setText(b, o.text) -- アイコンなら絵に
					b.Activated:Connect(function()
						onPick(o.id)
					end)
				end
			end
			local sorts = {}
			for _, id in { "level", "attack", "maxHp", "hired", "rebirths" } do
				table.insert(sorts, { id = id, text = SORT_GLYPH[id], on = prefs.advSort == id })
			end
			table.insert(sorts, { id = "dir", text = if prefs.advDesc then "▼" else "▲", on = false })
			row(1, sorts, function(id)
				if busy then
					return
				end
				if id == "dir" then
					send({ type = "SetListPrefs", advDesc = not prefs.advDesc })
				else
					send({ type = "SetListPrefs", advSort = id })
				end
			end)
			local states = {}
			for _, id in Roster.STATES do
				table.insert(states, { id = id, text = STATE_GLYPH[id], on = stateFilter == id })
			end
			row(2, states, function(id)
				stateFilter = id
				render()
			end)
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

Nav.register("AdvList", build)

return {}
