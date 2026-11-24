--!strict
-- メイン画面 S-10（T0 ハブ。D-211〜D-216・D-225）。ほかの画面はこの上に Nav で重ねる。
--   - マップが主役：画面より広く、ドラッグでスクロールする。一覧の行を触るとカメラがその馬車に寄って追う（D-212）。
--   - 常に出すもの：左のパーティ一覧、右下の宝箱ボタン（唯一の金）、右上のゴールドとその下のフレンド（D-213 ⑯・D-225）。
--   - 部品はすべて Roblox の帯より下に置く（D-219・D-225 ①）。
-- マップの絵とダンジョンの位置は仮（MapLayout。D-214 ⑪）。

local RunService = game:GetService("RunService")

local Components = require("../ui/Components")
local Create = require("../ui/Create")
local HubState = require("../hub/HubState")
local MapLayout = require("../hub/MapLayout")
local Nav = require("../ui/Nav")
local Root = require("../ui/Root")
local Session = require("../Session")
local Tokens = require("../ui/Tokens")
local master = require("../Master")

local C = Tokens.color
local I = Components.icon
local new = Create.new
local CHILDREN = Create.Children

local Hub = {}

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV" }
local STATE_GLYPH = { moving = "▶", exploring = "●", returning = "◀", waiting = "⌂" }

local layer: Frame
local map: ScrollingFrame
local mapContent: Frame
local listFrame: Frame
local wagons: { [number]: Frame } = {}
local rows: { [number]: { button: TextButton, glyph: TextLabel, pinch: Frame, ring: UIStroke } } = {}
local markers: { [string]: TextButton } = {}
local goldText: TextLabel
local chestCount: TextLabel
local chestNotice: Frame

---------------------------------------------------------------------------
-- マップ

local function placeAt(inst: GuiObject, p: MapLayout.Point)
	inst.AnchorPoint = Vector2.new(0.5, 0.5)
	inst.Position = UDim2.fromOffset(p.x, p.y)
end

local function buildMap(parent: Frame)
	local n = #master.dungeonList
	local width = MapLayout.width(n)
	map = new("ScrollingFrame", {
		Name = "Map",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.ch13,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		CanvasSize = UDim2.fromOffset(width, 0),
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Parent = parent,
	})
	-- 仮の地面（暖かい暗い茶の濃淡）
	new("Frame", {
		Name = "Ground",
		Size = UDim2.new(0, width, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		[CHILDREN] = { Components.gradient(C.ch16, C.ch13) },
		Parent = map,
	})
	mapContent = new("Frame", {
		Name = "Content",
		Size = UDim2.new(0, width, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = map,
	})
	-- ギルド（街）
	local guild: TextButton = new("TextButton", {
		Name = "Guild",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(110, 110),
		BackgroundColor3 = C.ch28,
		ZIndex = 3,
		[CHILDREN] = {
			Components.corner(18),
			Components.stroke(C.bronze, 3),
			(function()
				local t = Components.text({ text = I.home, size = 54, color = C.inkLight, font = Tokens.font.number })
				t.AutomaticSize = Enum.AutomaticSize.None
				t.Size = UDim2.fromScale(1, 1)
				t.ZIndex = 4
				return t
			end)(),
		},
		Parent = mapContent,
	})
	placeAt(guild, MapLayout.guild())
	-- ダンジョン
	for i, d in master.dungeonList do
		local m: TextButton = new("TextButton", {
			Name = d.id,
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.fromOffset(84, 84),
			BackgroundColor3 = C.ch16,
			ZIndex = 3,
			[CHILDREN] = {
				Components.corner(42),
				Components.stroke(C.bronze, 3),
				(function()
					local t = Components.text({
						text = ROMAN[i] or tostring(i),
						size = 30,
						color = C.inkLight,
						font = Tokens.font.display,
					})
					t.AutomaticSize = Enum.AutomaticSize.None
					t.Size = UDim2.fromScale(1, 1)
					t.ZIndex = 4
					t.Name = "Numeral"
					return t
				end)(),
			},
			Parent = mapContent,
		})
		placeAt(m, MapLayout.dungeon(i))
		m.Activated:Connect(function()
			Nav.open("DungeonPanel", { dungeonId = d.id })
		end)
		markers[d.id] = m
	end
	-- 自分でスクロールしたら追うのをやめる（D-214 ⑧）
	map.InputBegan:Connect(function(io: InputObject)
		if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
			HubState.following = false
		end
	end)
	map.InputChanged:Connect(function(io: InputObject)
		if io.UserInputType == Enum.UserInputType.MouseWheel then
			HubState.following = false
		end
	end)
end

local function wagonFor(partyIndex: number): Frame
	local w = wagons[partyIndex]
	if w then
		return w
	end
	w = new("Frame", {
		Name = "Wagon" .. partyIndex,
		Size = UDim2.fromOffset(66, 50),
		BackgroundColor3 = C.ch28,
		ZIndex = 6,
		[CHILDREN] = {
			Components.corner(10),
			Components.stroke(C.ch05, 2),
			(function()
				local t = Components.text({
					text = tostring(partyIndex),
					size = 25,
					color = C.inkLight,
					font = Tokens.font.display,
				})
				t.AutomaticSize = Enum.AutomaticSize.None
				t.Size = UDim2.fromScale(1, 1)
				t.ZIndex = 7
				return t
			end)(),
		},
		Parent = mapContent,
	})
	-- 指示待ちの吹き出しの「！」（D-215 ⑦）
	new("TextLabel", {
		Name = "Waiting",
		Text = "!",
		TextSize = 25,
		FontFace = Tokens.font.number,
		TextColor3 = C.inkWhite,
		BackgroundColor3 = C.notice,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -4),
		Size = UDim2.fromOffset(34, 34),
		ZIndex = 8,
		Visible = false,
		[CHILDREN] = { Components.corner(17), Components.stroke(C.ch75, 2) },
		Parent = w,
	})
	-- ピンチの印（ひびの入ったハートの仮。D-214 ③）
	new("TextLabel", {
		Name = "Pinch",
		Text = "♥",
		TextSize = 21,
		FontFace = Tokens.font.number,
		TextColor3 = C.warnDark,
		BackgroundColor3 = C.ch10,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 10, 0, -10),
		Size = UDim2.fromOffset(30, 30),
		ZIndex = 8,
		Visible = false,
		[CHILDREN] = { Components.corner(15), Components.stroke(C.warnDark, 2) },
		Parent = w,
	})
	wagons[partyIndex] = w
	return w
end

---------------------------------------------------------------------------
-- 左のパーティ一覧（D-212：状態とピンチだけ）

local function buildList(parent: Frame)
	local band = Root.bandBottom()
	listFrame = new("Frame", {
		Name = "PartyList",
		Position = UDim2.fromOffset(16, band + 12),
		Size = UDim2.fromOffset(168, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.ch10,
		ZIndex = 20,
		[CHILDREN] = {
			Components.corner(Tokens.radius.radiusMd),
			Components.stroke(C.ch16, 3),
			Components.padding(8, 8, 8, 8),
			new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		},
		Parent = parent,
	})
end

local function rowFor(partyIndex: number)
	local r = rows[partyIndex]
	if r then
		return r
	end
	local ring = Components.stroke(C.selAmber, 3, 1)
	local button: TextButton = new("TextButton", {
		Name = "Party" .. partyIndex,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = partyIndex,
		Size = UDim2.fromOffset(152, 66),
		BackgroundColor3 = C.ch17,
		ZIndex = 21,
		[CHILDREN] = { Components.corner(8), ring },
		Parent = listFrame,
	})
	local num =
		Components.text({ text = tostring(partyIndex), size = 30, color = C.inkLight, font = Tokens.font.display })
	num.Position = UDim2.fromOffset(12, 18)
	num.ZIndex = 22
	num.Parent = button
	local glyph = Components.text({ text = "", size = 30, color = C.ch75, font = Tokens.font.number })
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromOffset(80, 33)
	glyph.ZIndex = 22
	glyph.Parent = button
	local pinch: Frame = new("TextLabel", {
		Name = "Pinch",
		Text = "♥",
		TextSize = 21,
		FontFace = Tokens.font.number,
		TextColor3 = C.warnDark,
		BackgroundColor3 = C.ch10,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(32, 32),
		ZIndex = 22,
		Visible = false,
		[CHILDREN] = { Components.corner(16), Components.stroke(C.warnDark, 2) },
		Parent = button,
	})
	button.Activated:Connect(function()
		-- 触るとカメラが寄って追い、パーティの面を開く（D-212）
		HubState.selected = partyIndex
		HubState.following = true
		Nav.open("PartyPanel", { partyIndex = partyIndex })
	end)
	r = { button = button, glyph = glyph, pinch = pinch, ring = ring }
	rows[partyIndex] = r
	return r
end

---------------------------------------------------------------------------
-- 縁の部品

local function roundButton(icon: string, size: number): TextButton
	return new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = C.ch28,
		ZIndex = 20,
		[CHILDREN] = {
			Components.corner(size / 2),
			Components.stroke(C.bronze, 3),
			(function()
				local t = Components.text({ text = icon, size = 30, color = C.inkLight, font = Tokens.font.number })
				t.AutomaticSize = Enum.AutomaticSize.None
				t.Size = UDim2.fromScale(1, 1)
				t.ZIndex = 21
				return t
			end)(),
		},
	})
end

local function buildEdges(parent: Frame)
	local band = Root.bandBottom()
	-- 右上：クエスト・設定（小さなアイコン。D-215 ⑥⑦）とゴールド（常に出す：D-225 ④）
	local topRight: Frame = new("Frame", {
		Name = "TopRight",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -40, 0, band + 12),
		Size = UDim2.fromOffset(0, 66),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		ZIndex = 20,
		[CHILDREN] = {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 12),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = parent,
	})
	local quest = roundButton("✔", 66)
	quest.LayoutOrder = 1
	quest.Parent = topRight
	local gear = roundButton("⚙", 66)
	gear.LayoutOrder = 2
	gear.Parent = topRight
	local gold = Components.chip(I.coin, "0")
	gold.LayoutOrder = 3
	gold.ZIndex = 20
	gold.Parent = topRight
	for _, d in gold:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "0" then
			goldText = d
		end
	end
	-- ゴールドの下：フレンドボタン（D-213 ⑯）
	local friend = roundButton("♟", 66)
	friend.AnchorPoint = Vector2.new(1, 0)
	friend.Position = UDim2.new(1, -40, 0, band + 12 + 66 + 12)
	friend.Parent = parent

	-- 右下：宝箱ボタン（唯一の金：D-225 ②）
	local chest = Components.button({ kind = "gold", width = 260, icon = "▣", glyph = "A" })
	chest.AnchorPoint = Vector2.new(1, 1)
	chest.Position = UDim2.new(1, -40, 1, -24)
	chest.ZIndex = 20
	chest.Parent = parent
	local face = chest:FindFirstChild("Face") :: TextButton
	chestCount = Components.text({ text = "0", size = 40, color = C.inkDark, font = Tokens.font.number })
	chestCount.LayoutOrder = 5
	chestCount.ZIndex = 3
	chestCount.Parent = face
	chestNotice = new("TextLabel", {
		Name = "InboxNotice",
		Text = "!",
		TextSize = 25,
		FontFace = Tokens.font.number,
		TextColor3 = C.inkWhite,
		BackgroundColor3 = C.notice,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(34, 34),
		ZIndex = 9,
		Visible = false,
		[CHILDREN] = { Components.corner(17), Components.stroke(C.ch75, 2) },
		Parent = chest, -- 並びの外に置く（ボタンの右上の角）
	})
	chestNotice.Position = UDim2.new(1, -6, 0, 6)

	-- 左下：下メニュー（ギルド・冒険者・倉庫。アイコンだけ：D-213 ⑩）。画面は M8-3・M8-6 でつなぐ
	local menu: Frame = new("Frame", {
		Name = "BottomMenu",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -24),
		Size = UDim2.fromOffset(0, 66),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		ZIndex = 20,
		[CHILDREN] = {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 12),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = parent,
	})
	for i, icon in { I.home, I.party, "▤" } do
		local b = roundButton(icon, 66)
		b.LayoutOrder = i
		b.Parent = menu
		if i == 1 then
			-- ギルド（S-20 は M8-6）。それまでは雇用の受付（S-21a）を直接開く
			b.Activated:Connect(function()
				Nav.open("HireDesk")
			end)
		end
	end
end

---------------------------------------------------------------------------
-- 更新

local function refreshStatic(view: any)
	if view == nil then
		return
	end
	goldText.Text = HubState.formatNumber(view.gold or 0)
	local total = 0
	for _, c in view.chests or {} do
		total += c.count
	end
	chestCount.Text = tostring(total)
	local hasInbox = false
	for _ in view.inbox or {} do
		hasInbox = true
		break
	end
	chestNotice.Visible = hasInbox
	-- 未解放のダンジョンは暗くする
	for id, m in markers do
		local unlocked = view.unlockedDungeons and view.unlockedDungeons[id] == true
		m.BackgroundColor3 = if unlocked then C.ch16 else C.ch10
		local numeral = m:FindFirstChild("Numeral") :: TextLabel?
		if numeral then
			numeral.TextTransparency = if unlocked then 0 else 0.6
		end
	end
end

local function refreshMoving(view: any)
	if view == nil then
		return
	end
	for _, party in view.parties or {} do
		local i = party.index
		local s = HubState.status(view, i)
		local r = rowFor(i)
		r.glyph.Text = STATE_GLYPH[s.state]
		r.pinch.Visible = s.pinch
		r.ring.Transparency = if HubState.selected == i then 0 else 1
		local w = wagonFor(i)
		if s.state == "waiting" then
			-- 待機はギルドの横に並べる（D-214）
			local g = MapLayout.guild()
			placeAt(w, { x = g.x + 100, y = g.y - 110 + (i - 1) * 62 })
		else
			placeAt(w, MapLayout.wagon(HubState.dungeonIndex(s.dungeonId), s.along))
		end
		local waiting = w:FindFirstChild("Waiting") :: GuiObject
		waiting.Visible = s.state == "waiting"
		local pinch = w:FindFirstChild("Pinch") :: GuiObject
		pinch.Visible = s.pinch
		if HubState.following and HubState.selected == i then
			local viewW = map.AbsoluteSize.X / math.max(Root.frame.scale, 0.01)
			local target = MapLayout.cameraX(w.Position.X.Offset, viewW, MapLayout.width(#master.dungeonList))
			map.CanvasPosition = Vector2.new(target, 0)
		end
	end
end

function Hub.mount()
	layer = new("Frame", {
		Name = "Hub",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = Root.canvas,
	})
	buildMap(layer)
	buildList(layer)
	buildEdges(layer)
	Session.changed:connect(function(view)
		refreshStatic(view)
		refreshMoving(view)
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			refreshMoving(Session.view)
		end
	end)
end

-- 画面の登録（パーティの面・ダンジョンの面）
require("./PartyPanel")
require("./DungeonPanel")
require("./hire/HireDesk")
require("./hire/HirePostings")
require("./hire/HireInterview")
require("./hire/HireReroll")
require("./hire/HireDone")

return Hub
