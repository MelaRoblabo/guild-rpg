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
local EventMarker = require("../hub/EventMarker")
local Guide = require("../hub/Guide")
local PickMode = require("../hub/PickMode")
local LoginSequence = require("../hub/LoginSequence")
local ReturnToast = require("../hub/ReturnToast")
local WorldCarts = require("../hub/WorldCarts")
local Root = require("../ui/Root")
local Session = require("../Session")
local Tokens = require("../ui/Tokens")
local Words = require("../ui/Words")
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
local rows: { [number]: { button: TextButton, glyph: TextLabel, pinch: Frame, ring: UIStroke, timer: TextLabel } } = {}
local markers: { [string]: TextButton } = {}
local goldText: TextLabel
local chestCount: TextLabel
local chestNotice: Frame
local chestButton: Frame
local questButton: TextButton -- 誘導の最後の段で光らせる（D-246 ②）

---------------------------------------------------------------------------
-- マップ

local PROGRESS_DOTS = 12 -- 進みの輪の点の数（D-249 ②。見た目の分け方でゲームの数値ではない）

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
		-- 探索の進みの輪（D-249 ②）：丸の周りに点を並べ、進みに合わせて明るくする。探索中のときだけ見せる
		local ring: Frame = new("Frame", {
			Name = "Progress",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = m,
		})
		for k = 1, PROGRESS_DOTS do
			local a = math.rad(-90 + (k - 1) * 360 / PROGRESS_DOTS)
			new("Frame", {
				Name = "Dot" .. k,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, math.cos(a) * 54, 0.5, math.sin(a) * 54),
				Size = UDim2.fromOffset(10, 10),
				BackgroundColor3 = C.ch45,
				ZIndex = 4,
				[CHILDREN] = { Components.corner(5) },
				Parent = ring,
			})
		end
	end
	-- 行き先を選ぶ形（D-231 ⑦）：選べるダンジョンは琥珀の輪
	local function showPickMode()
		local view = Session.view
		for id, mk in markers do
			local stroke = mk:FindFirstChildOfClass("UIStroke")
			local open = view ~= nil and view.unlockedDungeons ~= nil and view.unlockedDungeons[id] == true
			if stroke then
				stroke.Color = if PickMode.partyIndex and open then C.selAmber else C.bronze
				stroke.Thickness = if PickMode.partyIndex and open then 5 else 3
			end
		end
	end
	PickMode.changed:connect(showPickMode)
	EventMarker.mount(mapContent) -- マップイベントの印（M8-6）
	WorldCarts.mount(mapContent) -- 他のプレイヤーの馬車（M8-7、D-108・D-151）
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
	-- 戦いの間の吹き出し（D-249 ②）
	new("TextLabel", {
		Name = "Battle",
		Text = "⚔",
		TextSize = 25,
		FontFace = Tokens.font.number,
		TextColor3 = C.inkLight,
		BackgroundColor3 = C.ch10,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -4),
		Size = UDim2.fromOffset(38, 34),
		ZIndex = 8,
		Visible = false,
		[CHILDREN] = { Components.corner(17), Components.stroke(C.bronze, 2) },
		Parent = w,
	})
	-- 馬車を触ってもパーティの面を開く（D-212。一覧の行と同じ）
	local tap: TextButton = new("TextButton", {
		Name = "Tap",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 9,
		Parent = w,
	})
	tap.Activated:Connect(function()
		HubState.selected = partyIndex
		HubState.following = true
		PickMode.stop()
		Nav.open("PartyPanel", { partyIndex = partyIndex })
	end)
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
	glyph.Position = UDim2.fromOffset(76, 33)
	glyph.ZIndex = 22
	glyph.Parent = button
	-- 帰るまでの残り（出ている間だけ。状態の印は上へ寄せる：D-249 ①）
	local timer = Components.text({ text = "", size = 21, color = C.inkLight, font = Tokens.font.number })
	timer.Name = "Timer"
	timer.AnchorPoint = Vector2.new(0.5, 0.5)
	timer.Position = UDim2.fromOffset(76, 48)
	timer.ZIndex = 22
	timer.Visible = false
	timer.Parent = button
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
		PickMode.stop() -- 行き先を選ぶのをやめる
		Nav.open("PartyPanel", { partyIndex = partyIndex })
	end)
	r = { button = button, glyph = glyph, pinch = pinch, ring = ring, timer = timer }
	rows[partyIndex] = r
	return r
end

---------------------------------------------------------------------------
-- 縁の部品

-- 縁のボタン：アイコン＋語（D-245。アイコンだけでは分からないので、大きさを変えて語を入れる）
local function edgeButton(icon: string, word: string): TextButton
	return new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(0, 66),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ch28,
		ZIndex = 20,
		[CHILDREN] = {
			Components.corner(33),
			Components.stroke(C.bronze, 3),
			Components.padding(0, 20, 0, 16),
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			(function()
				local t = Components.text({ text = icon, size = 28, color = C.inkLight, font = Tokens.font.number })
				t.LayoutOrder = 1
				t.ZIndex = 21
				return t
			end)(),
			(function()
				local t = Components.text({ text = word, size = 21, color = C.inkLight, font = Tokens.font.display })
				t.Name = "Word"
				t.LayoutOrder = 2
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
	local quest = edgeButton("✔", Words.quests)
	quest.LayoutOrder = 1
	quest.Parent = topRight
	questButton = quest
	quest.Activated:Connect(function()
		Nav.open("Quests") -- D-233（M8-6）
	end)
	local gear = edgeButton("⚙", Words.settings)
	gear.LayoutOrder = 2
	gear.Parent = topRight
	gear.Activated:Connect(function()
		Nav.open("Settings") -- S-61（M8-6）
	end)
	local gold = Components.chip(I.coin, "0")
	gold.LayoutOrder = 3
	gold.ZIndex = 20
	gold.Parent = topRight
	for _, d in gold:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "0" then
			goldText = d
		end
	end
	-- ゴールドを触るとショップ（S-60、D-213 ②）
	-- （札の中に全面のボタンを置くと自動の幅が伸びるので、札そのものの入力で開く）
	gold.Active = true
	gold.InputEnded:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			Nav.open("Shop")
		end
	end)
	-- ゴールドの下：フレンドボタン（D-213 ⑯）
	local friend = edgeButton("♟", Words.friends)
	friend.AnchorPoint = Vector2.new(1, 0)
	friend.Position = UDim2.new(1, -40, 0, band + 12 + 66 + 12)
	friend.Parent = parent

	-- 右下：宝箱ボタン（唯一の金：D-225 ②）
	local chest = Components.button({
		kind = "gold",
		width = 300,
		icon = "▣",
		label = Words.chests,
		glyph = "A",
		name = "ChestButton",
		onClick = function()
			Nav.open("ChestList") -- S-30（D-164・D-223）
		end,
	})
	chest.AnchorPoint = Vector2.new(1, 1)
	chest.Position = UDim2.new(1, -40, 1, -24)
	chest.ZIndex = 20
	chest.Parent = parent
	chestButton = chest
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

	-- 左下：下メニュー（ギルド・冒険者・倉庫。アイコン＋語：D-245。D-213 ⑩の「アイコンだけ」を置き換え）
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
	local words = { Words.guild, Words.adventurers, Words.warehouse }
	for i, icon in { I.home, I.party, "▤" } do
		local b = edgeButton(icon, words[i])
		b.Name = ({ "Guild", "Adventurers", "Warehouse" })[i]
		b.LayoutOrder = i
		b.Parent = menu
		if i == 1 then
			-- ギルド（S-20 は M8-6）。それまでは雇用の受付（S-21a）を直接開く
			b.Activated:Connect(function()
				Nav.open("HireDesk")
			end)
		end
		if i == 3 then
			-- 倉庫（S-50、M8-6）
			b.Activated:Connect(function()
				Nav.open("Warehouse")
			end)
		end
		if i == 2 then
			-- 冒険者（S-40、M8-6）
			b.Activated:Connect(function()
				Nav.open("AdvList")
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
	-- 宝箱が0個のときは茶、あるときだけ金（D-250 ②。押せるのは同じ）
	local kind = if total > 0 then "gold" else "brown"
	if chestButton:GetAttribute("Kind") ~= kind then
		chestButton:SetAttribute("Kind", kind)
		Components.setButtonKind(chestButton, kind)
	end
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

-- 初回の誘導（D-244 ①）：馬車（待機の最初のパーティ）→ 帰還のあとの宝箱ボタン
local function refreshGuide(view: any)
	local first = view.parties and view.parties[1]
	local wagonOn = false
	-- 重ねた画面（ログインのまとめなど）があるときは光らせない。
	-- Go の段でパーティの面を閉じたときも、戻る道として馬車を光らせ続ける（Open All の段の宝箱ボタンも同じ）
	if first and (Guide.is("wagon") or Guide.is("go")) and Nav.depth() == 0 then
		wagonOn = HubState.status(view, first.index).state == "waiting"
	end
	if first then
		Guide.mark(wagons[first.index], wagonOn, 10)
	end
	local total = 0
	for _, c in view.chests or {} do
		total += c.count
	end
	Guide.mark(chestButton, (Guide.is("chests") or Guide.is("openAll")) and total > 0 and Nav.depth() == 0, 18, true)
	-- 最後の段：右上の Quests（並べる仕組みの中なので、輪と指はメイン画面の面に重ねる：D-246 ②）
	Guide.markOver(questButton, Guide.is("quests") and Nav.depth() == 0, 33, layer, 19)
end

local function refreshMoving(view: any)
	EventMarker.refresh(view)
	WorldCarts.refresh(view)
	if view == nil then
		return
	end
	refreshGuide(view)
	local exploring: { [string]: number } = {} -- ダンジョンごとの探索の進み（D-249 ②）
	for _, party in view.parties or {} do
		local i = party.index
		local s = HubState.status(view, i)
		local r = rowFor(i)
		r.glyph.Text = STATE_GLYPH[s.state]
		-- 帰るまでの残り（D-249 ①）：出ている間は印を上に、時計を下に
		local out = s.remaining ~= nil and s.state ~= "waiting"
		r.timer.Visible = out
		r.glyph.Position = UDim2.fromOffset(76, if out then 20 else 33)
		if out then
			r.timer.Text = "🕒" .. HubState.clock(s.remaining :: number)
		end
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
		-- 戦いの間は馬車が小さく揺れ、⚔ の吹き出し（D-249 ②）
		local battle = w:FindFirstChild("Battle") :: GuiObject
		battle.Visible = s.inBattle
		if s.inBattle then
			w.Rotation = math.sin(os.clock() * 18) * 4
		else
			w.Rotation = 0
		end
		if s.state == "exploring" and s.dungeonId and s.exploreRatio then
			exploring[s.dungeonId] = math.max(exploring[s.dungeonId] or 0, s.exploreRatio)
		end
		local pinch = w:FindFirstChild("Pinch") :: GuiObject
		pinch.Visible = s.pinch
		if HubState.following and HubState.selected == i then
			local viewW = map.AbsoluteSize.X / math.max(Root.frame.scale, 0.01)
			local target = MapLayout.cameraX(w.Position.X.Offset, viewW, MapLayout.width(#master.dungeonList))
			map.CanvasPosition = Vector2.new(target, 0)
		end
	end
	-- 探索の進みの輪（D-249 ②）
	for id, m in markers do
		local ring = m:FindFirstChild("Progress") :: Frame?
		if ring then
			local ratio = exploring[id]
			ring.Visible = ratio ~= nil
			if ratio then
				local lit = math.floor(ratio * PROGRESS_DOTS + 0.5)
				for k = 1, PROGRESS_DOTS do
					local dot = ring:FindFirstChild("Dot" .. k) :: Frame?
					if dot then
						dot.BackgroundColor3 = if k <= lit then C.numHi else C.ch45
					end
				end
			end
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
	ReturnToast.mount() -- 帰還のトースト（11章 §5、M8-6）
	LoginSequence.mount() -- ログイン時のまとめ・カットイン・カレンダー（D-132・D-208、M8-6）
	Guide.mount() -- 初回の誘導（D-244 ①）
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
require("./chest/ChestList")
require("./chest/ChestOpening")
require("./chest/ChestReveal")
require("./chest/ChestResults")
require("./rebirth/RebirthRitual")
require("./rebirth/RebirthCharge")
require("./rebirth/RebirthCompare")
require("./rebirth/RebirthDone")
require("./warehouse/Warehouse")
require("./warehouse/AutoSell")
require("./adventurers/AdvList")
require("./adventurers/AdvDetail")
require("./adventurers/EquipSelect")
require("./adventurers/LookChange")
require("./party/PartyMenu")
require("./guild/Expand")
require("./guild/Settings")
require("./guild/Shop")
require("./event/Quests")
require("./event/EventDepart")
require("./event/Merchant")
require("./login/LoginSummary")
require("./login/CutIn")
require("./login/LoginCalendar")
require("./world/OtherParty")

return Hub
