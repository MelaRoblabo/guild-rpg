--!strict
-- メイン画面 S-10（T0 ハブ。D-211〜D-216・D-225）。ほかの画面はこの上に Nav で重ねる。
--   - マップが主役：テーブルの上の 3D の地図（World3D・MapCamera：D-270）。カメラは自由に動かせ、
--     パーティ・ダンジョン・ギルドを選ぶとその物へ寄ってゆっくり旋回する。
--   - 常に出すもの：左のパーティ一覧（リーダーのアイコン：D-271）、右下の宝箱ボタン（唯一の金）、右上のゴールドとその下のフレンド（D-213 ⑯・D-225）。
--   - 部品はすべて Roblox の帯より下に置く（D-219・D-225 ①）。

local RunService = game:GetService("RunService")

local Game = require("@game/ReplicatedStorage/Core/Game")
local Components = require("../ui/Components")
local Create = require("../ui/Create")
local Art = require("../ui/Art")
local HubState = require("../hub/HubState")
local Motion = require("../ui/Motion")
local Portrait = require("../ui/Portrait")
local PartyIcon = require("../ui/PartyIcon")
local MapCamera = require("../hub/MapCamera")
local World3D = require("../hub/World3D")
local Nav = require("../ui/Nav")
local EventMarker = require("../hub/EventMarker")
local Guide = require("../hub/Guide")
local LevelUpMarks = require("../hub/LevelUpMarks")
local PickMode = require("../hub/PickMode")
local LoginSequence = require("../hub/LoginSequence")
local ReturnToast = require("../hub/ReturnToast")
local Root = require("../ui/Root")
local ChestCommon = require("./chest/ChestCommon")
local Session = require("../Session")
local Tokens = require("../ui/Tokens")
local Words = require("../ui/Words")
local master = require("../Master")

local C = Tokens.color
local I = Components.icon
local new = Create.new
local CHILDREN = Create.Children

local Hub = {}

local layer: Frame
local listFrame: Frame
-- 左の一覧の行：リーダーのアイコン（右上に動く状態の印）と名前（D-271）
local rows: {
	[number]: { button: TextButton, icon: Frame, name: TextLabel, pinch: Frame, ring: UIStroke, haul: TextButton },
} =
	{}
local newFaceBoard: BillboardGui? = nil -- ギルドの上の、全員が冒険中に雇った人の NEW の顔（D-265 ②）
local goldText: TextLabel
local chestCount: TextLabel
local levelUpBadge: TextLabel? = nil -- Adventurers のボタンの ▲（D-269 ③）
local lastChestTotal: number? = nil -- 前に見た宝箱の数（増えたら馬車から宝箱が飛ぶ：D-268 ①）
local chestNotice: Frame
local chestButton: Frame
local questButton: TextButton -- 誘導の最後の段で光らせる（D-246 ②）
local questBadge: TextLabel -- 受け取れるクエストの数（D-286）
local hopHaul: (t: number) -> () -- 吹き出しの宝箱を跳ねさせる（下で定義）

---------------------------------------------------------------------------
-- 3D マップ（D-270）

-- マップの横に出す面（パーティの面・ダンジョンの面・行き先の一覧）だけを上から閉じる。
-- 別の物を選んだとき、前の面（古い行き先の一覧など）を下に残さないため。ログインの流れ（カレンダーなど）は閉じない
local MAP_PANELS = { PartyPanel = true, DungeonPanel = true, DungeonPick = true }
local function closeMapPanels()
	while true do
		local id = Nav.topId()
		if id == nil or not MAP_PANELS[id] then
			return
		end
		Nav.close()
	end
end

-- パーティを選ぶ：パーティの面を開く（面がカメラをそのパーティへ寄せて旋回させる：D-270 ⑤）
local function openParty(partyIndex: number)
	HubState.selected = partyIndex
	PickMode.stop() -- 行き先を選ぶのをやめる
	-- 前に選んだパーティの面・行き先の一覧（DungeonPick）を下に残さない（古い一覧が残っていた）
	closeMapPanels()
	Nav.open("PartyPanel", { partyIndex = partyIndex })
end

-- 帰還の獲得の吹き出しを押した（D-287・D-302）：獲得の画面 → Open で、パーティが持ち帰った宝箱を山へ移して開ける。
-- × で閉じたら何も受け取らない（吹き出しは残る）。持ち帰った宝箱は右下の Chests には入っていない
local function openHaul(partyIndex: number)
	local view = Session.view
	local party = nil
	for _, p in (view and view.parties) or {} do
		if p.index == partyIndex then
			party = p
		end
	end
	local h = party and party.haul
	if h == nil then
		return
	end
	local chests, piles, counts = 0, {}, {}
	for pileKey, n in h.chests or {} do
		if n > 0 then
			chests += n
			counts[pileKey] = n
			table.insert(piles, pileKey)
		end
	end
	table.sort(piles)
	local tiles = {}
	if (h.gold or 0) > 0 then
		table.insert(tiles, { kind = "gold", n = h.gold })
	end
	if chests > 0 then
		table.insert(tiles, { kind = "chest", n = chests })
	end
	local function claim(): boolean
		local ok, r = pcall(Session.sendAndWait, { type = "ClaimHaul", partyIndex = partyIndex })
		return ok and r ~= nil and r.ok == true
	end
	local primary
	if chests > 0 then
		primary = {
			icon = "@chest",
			label = Words.open,
			onClick = function(api: Nav.Api)
				if not claim() then
					api.close()
					return
				end
				-- 持ち帰った宝箱だけを開ける。初回は演出をフルで（D-267 ④）
				local first = Guide.is("chests") or Guide.is("openAll")
				Guide.done("openAll")
				local batch = ChestCommon.open(piles, false, counts)
				if batch then
					batch.first = first
					api.replace("ChestOpening", { batch = batch })
				else
					api.close()
				end
			end,
		}
	else
		-- 宝箱がない（ゴールドだけ）：OK で記録を消す
		primary = {
			icon = "✔",
			label = Words.ok,
			onClick = function(api: Nav.Api)
				claim()
				api.close()
			end,
		}
	end
	Nav.open("RewardGet", { title = PartyIcon.name(view, partyIndex), tiles = tiles, primary = primary })
end

local function mount3D()
	World3D.mount({
		onDungeon = function(id: string)
			closeMapPanels() -- 前の面（パーティの面・行き先の一覧）を下に残さない
			Nav.open("DungeonPanel", { dungeonId = id }) -- 面がカメラをそのダンジョンへ寄せる
		end,
		onGuild = function()
			World3D.focusGuild()
			Nav.open("HireDesk") -- ギルド（S-20＝受付の広間：D-122・D-231 ③）
		end,
		onParty = openParty,
		-- レイドボス（D-275）：出発できる間は出発の面
		onRaid = function(slot: number)
			local cur = Game.query.mapEvent(Session.now(), master).current
			if Session.view and cur.kind == "raid" and cur.eventSlot == slot and cur.open then
				PickMode.stop()
				Nav.open("EventDepart", { slot = slot })
			end
		end,
		-- 旅の商人（D-274）：向かうパーティを待っているなら出発の面、向かっている・着いているなら商人の面
		onMerchant = function(slot: number)
			local view = Session.view
			if view == nil then
				return
			end
			for _, p in Game.query.merchantPresence(view, Session.now(), master) do
				if p.eventSlot == slot then
					PickMode.stop()
					if p.phase == "open" then
						Nav.open("EventDepart", { slot = slot })
					else
						Nav.open("Merchant", { slot = slot })
					end
					return
				end
			end
		end,
	})
	-- キーボードでカメラを動かすのは、マップを見ているときだけ（面がない・パーティやダンジョンの面だけ）
	MapCamera.keysAllowed = function(): boolean
		return Nav.depth() == 0 or Nav.topPassThrough()
	end
	-- ゲームパッドの左スティック・照準・A は、面を開いていないときだけ（面を開いているときは面の操作：D-273 ⑥）
	MapCamera.mapOnTop = function(): boolean
		return Nav.depth() == 0
	end
	-- 雇った人のカードが飛び込む先（画面の上のギルドの位置：D-265 ②）
	HubState.guildPoint = function(): Vector2?
		return World3D.screenPoint(World3D.guild())
	end
	local pg = (game:GetService("Players").LocalPlayer :: Player):WaitForChild("PlayerGui")
	local boards = pg -- 板は PlayerGui の直下
	EventMarker.mount(World3D.eventPlace, boards) -- マップイベントの印（D-270 ⑦）
	-- ギルドの上の NEW の顔（全員が冒険中に雇った人：D-265 ②）
	local guild = World3D.guild()
	if guild then
		local b: BillboardGui = new("BillboardGui", {
			Name = "NewcomerBoard",
			Adornee = guild,
			AlwaysOnTop = true,
			Enabled = false,
			Size = UDim2.fromOffset(80, 92),
			StudsOffsetWorldSpace = Vector3.new(0, guild.Size.Y / 2 + 12, 0),
			Parent = boards,
		})
		local face: Frame = new("Frame", {
			Name = "NewFace",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(64, 64),
			BackgroundColor3 = C.ch13,
			[CHILDREN] = { Components.corner(32), Components.stroke(C.okGreen, 3) },
			Parent = b,
		})
		new("TextLabel", {
			Name = "New",
			Text = "NEW",
			TextSize = 18,
			FontFace = Tokens.font.number,
			TextColor3 = C.inkDark,
			BackgroundColor3 = C.okGreen,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromOffset(52, 24),
			ZIndex = 3,
			[CHILDREN] = { Components.corner(12) },
			Parent = face,
		})
		newFaceBoard = b
	end
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
	-- リーダーのアイコン（番号の代わり：D-271 ③）。右上に動く状態の印（D-271 ④）。帰るまでの時間は出さない（D-271 ⑤）
	local icon = PartyIcon.make(50)
	icon.Position = UDim2.fromOffset(8, 8)
	icon.ZIndex = 22
	for _, d in icon:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 23
		end
	end
	icon.Parent = button
	local name = Components.text({
		text = "",
		size = 21,
		color = C.inkLight,
		font = Tokens.font.display,
		xAlign = Enum.TextXAlignment.Left,
	})
	name.AutomaticSize = Enum.AutomaticSize.None
	name.Position = UDim2.fromOffset(68, 20)
	name.Size = UDim2.fromOffset(72, 26)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 22
	name.Parent = button
	local pinch: Frame = new("TextLabel", {
		Name = "Pinch",
		Text = "♥",
		TextSize = 21,
		FontFace = Tokens.font.number,
		TextColor3 = C.warnDark,
		BackgroundColor3 = C.ch10,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -4, 1, -4),
		Size = UDim2.fromOffset(28, 28),
		ZIndex = 24,
		Visible = false,
		[CHILDREN] = { Components.corner(14), Components.stroke(C.warnDark, 2) },
		Parent = button,
	})
	button.Activated:Connect(function()
		-- 触るとカメラがそのパーティへ寄って旋回し、パーティの面を開く（D-270 ⑤）
		openParty(partyIndex)
	end)
	-- 帰還の獲得の吹き出し（D-287）：ギルドで待つパーティに持ち帰った物があれば、行の右に宝箱の吹き出し
	local haul: TextButton = new("TextButton", {
		Name = "Haul",
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 14, 0.5, 0),
		Size = UDim2.fromOffset(66, 58),
		BackgroundColor3 = C.ch75,
		Visible = false,
		ZIndex = 24,
		[CHILDREN] = { Components.corner(14), Components.stroke(C.selAmber, 3) },
		Parent = button,
	})
	-- 吹き出しの尾（行の方を指す）
	new("Frame", {
		Name = "Tail",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(16, 16),
		Rotation = 45,
		BackgroundColor3 = C.ch75,
		BorderSizePixel = 0,
		ZIndex = 23,
		Parent = haul,
	})
	local chestPic: Frame = new("Frame", {
		Name = "Pic",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(46, 46),
		BackgroundTransparency = 1,
		ZIndex = 25,
		Parent = haul,
	})
	if not Art.put(chestPic, Art.chest(1, false)) then
		local g = Components.text({ text = "@chest", size = 34, color = C.inkDark, font = Tokens.font.number })
		g.AutomaticSize = Enum.AutomaticSize.None
		g.Size = UDim2.fromScale(1, 1)
		g.ZIndex = 25
		g.Parent = chestPic
	end
	for _, d in chestPic:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 25
		end
	end
	haul.Activated:Connect(function()
		openHaul(partyIndex)
	end)
	r = { button = button, icon = icon, name = name, pinch = pinch, ring = ring, haul = haul }
	rows[partyIndex] = r
	return r
end

---------------------------------------------------------------------------
-- 縁の部品

-- 縁のボタン：アイコン＋語（D-245。アイコンだけでは分からないので、大きさを変えて語を入れる）
local function edgeButton(icon: string, word: string, uiKey: string?): TextButton
	-- UIアイコンの絵があれば記号の代わりに使う（白1色を文字の色で塗る：D-149）
	local iconImage = if uiKey then Art.ui(uiKey) else nil
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
			(function(): GuiObject
				local img = Art.icon(iconImage, 30, 1, C.inkLight, 21)
				if img then
					return img
				end
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
	local quest = edgeButton("✔", Words.quests, "quest")
	quest.LayoutOrder = 1
	quest.Parent = topRight
	questButton = quest
	quest.Activated:Connect(function()
		Nav.open("Quests") -- D-233（M8-6）
	end)
	-- 受け取れるクエストの数の札（D-286）。並びの中に入れず、大きさの決まったアイコンに付けてボタンの左上の角に重ねる
	-- （語の札に付けると、札の自動の幅に札まで入って語がずれた）
	questBadge = new("TextLabel", {
		Name = "Claimable",
		Text = "",
		TextSize = 21,
		FontFace = Tokens.font.number,
		TextColor3 = C.inkWhite,
		BackgroundColor3 = C.notice,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(-14, -14),
		Size = UDim2.fromOffset(32, 32),
		Visible = false,
		ZIndex = 25,
		[CHILDREN] = { Components.corner(16), Components.stroke(C.ch75, 2) },
		Parent = quest:FindFirstChild("Icon") or quest:FindFirstChild("Word"),
	})
	local gear = edgeButton("⚙", Words.settings, "settings")
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
	local friend = edgeButton("♟", Words.friends, "friend")
	friend.AnchorPoint = Vector2.new(1, 0)
	friend.Position = UDim2.new(1, -40, 0, band + 12 + 66 + 12)
	friend.Parent = parent

	-- 右下：宝箱ボタン（唯一の金：D-225 ②）
	local chest = Components.button({
		kind = "gold",
		width = 300,
		icon = "@chest",
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
		local b = edgeButton(icon, words[i], ({ "guild", "roster", "warehouse" })[i])
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
			-- Lv が上がった人がいれば ▲ の札（一覧を開くまで残す：D-269 ③）
			local up: TextLabel = new("TextLabel", {
				Name = "LevelUp",
				Text = "",
				TextSize = 21,
				FontFace = Tokens.font.number,
				TextColor3 = C.inkDark,
				BackgroundColor3 = C.okGreen,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -6, 0, 6),
				Size = UDim2.fromOffset(32, 32),
				Visible = false,
				ZIndex = 8,
				[CHILDREN] = { Components.corner(16), Components.stroke(C.ch13, 2) },
				Parent = b,
			})
			Components.setText(up, "@up")
			levelUpBadge = up
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
	-- 受け取れるクエスト（達成して受け取っていない行とボーナス：D-286）
	local claimable = 0
	for _, period in { "daily", "weekly" } do
		local book = view.quests and view.quests[period]
		if book then
			for _, e in book.entries or {} do
				if e.done and not e.claimed then
					claimable += 1
				end
			end
			if book.bonusDone and not book.bonusClaimed then
				claimable += 1
			end
		end
	end
	if questBadge then
		if claimable > 0 and not questBadge.Visible then
			Motion.bump(questBadge)
		end
		questBadge.Visible = claimable > 0
		questBadge.Text = tostring(claimable)
	end
	local total = 0
	for _, c in view.chests or {} do
		total += c.count
	end
	-- 宝箱が増えたら（帰還など）、ギルドから宝箱が1つずつ宝箱ボタンへ飛び、数字が弾んで増える（D-268 ①・D-214 ⑨）
	local guildAt = HubState.guildPoint and HubState.guildPoint()
	if lastChestTotal ~= nil and total > lastChestTotal and Nav.depth() == 0 and guildAt then
		local from = lastChestTotal
		local n = math.min(total - from, 6)
		for k = 1, n do
			Motion.fly({
				from = guildAt,
				to = chestButton,
				icon = "@chest",
				size = 56,
				endSize = 36,
				delay = (k - 1) * 0.12,
			})
		end
		Motion.countUp(chestCount, from, total, { duration = 0.55 + (n - 1) * 0.12, float = false })
	else
		chestCount.Text = tostring(total)
	end
	lastChestTotal = total
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
	chestNotice.Visible = hasInbox and total > 0 -- 宝箱が 0 のときは出さない（2026-11-27 ユーザー指示）
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
	-- 全員が冒険中に雇った人がいて、パーティが帰ってきたら、その馬車を一度だけ光らせる（D-265 ②）
	local newcomerParty: number? = nil
	if not wagonOn and Nav.depth() == 0 and #HubState.pendingNewcomers(view) > 0 then
		for _, p in view.parties or {} do
			if HubState.status(view, p.index).state == "waiting" then
				newcomerParty = p.index
				break
			end
		end
	end
	-- 3D の馬車は GUI ではないので、誘導の輪は左の一覧の行に付ける（D-270）
	for i, r in rows do
		Guide.mark(r.button, (wagonOn and first ~= nil and i == first.index) or i == newcomerParty, 8)
	end
	local total = 0
	for _, c in view.chests or {} do
		total += c.count
	end
	-- 帰還の宝箱はパーティの横の吹き出しから開ける（D-302）。吹き出しが出ていればそちらを指す
	local haulRow: number? = nil
	for i, r in rows do
		if r.haul.Visible and haulRow == nil then
			haulRow = i
		end
	end
	local chestStep = (Guide.is("chests") or Guide.is("openAll")) and Nav.depth() == 0
	for i, r in rows do
		Guide.mark(r.haul, chestStep and i == haulRow, 14)
	end
	Guide.mark(chestButton, chestStep and haulRow == nil and total > 0, 18, true)
	-- 最後の段：右上の Quests（並べる仕組みの中なので、輪と指はメイン画面の面に重ねる：D-246 ②）
	Guide.markOver(questButton, Guide.is("quests") and Nav.depth() == 0, 33, layer, 19)
end

local function refreshMoving(view: any)
	EventMarker.refresh(view)
	if view == nil then
		return
	end
	World3D.refresh(view)
	refreshGuide(view)
	if levelUpBadge then
		levelUpBadge.Visible = LevelUpMarks.anyUnseen()
	end
	-- ギルドの上の NEW の顔（全員が冒険中に雇った人：D-265 ②。雇った直後にも出すので 0.1 秒ごとに見る）
	local b = newFaceBoard
	if b then
		local pending = HubState.pendingNewcomers(view)
		local first = pending[1] and view.adventurers[pending[1]]
		b.Enabled = first ~= nil
		local face = b:FindFirstChild("NewFace") :: Frame
		if first and face:GetAttribute("Uid") ~= pending[1] then
			face:SetAttribute("Uid", pending[1])
			Portrait.fill(face, first.appearanceId)
		end
	end
	for _, party in view.parties or {} do
		local i = party.index
		local s = HubState.status(view, i)
		local r = rowFor(i)
		PartyIcon.set(r.icon, view, i, s.state)
		local leaderName = PartyIcon.name(view, i)
		r.name.Text = (string.gsub(leaderName, "'s Party$", ""))
		r.pinch.Visible = s.pinch
		r.ring.Transparency = if HubState.selected == i then 0 else 1
		-- 待機（Zzz）になったら帰還の獲得の吹き出し（D-287）。自動再派遣の間は出さず、止まって帰ったときに合算で出す
		local showHaul = s.state == "waiting" and party.haul ~= nil
		if showHaul and not r.haul.Visible then
			Motion.bump(r.haul)
		end
		r.haul.Visible = showHaul
	end
end

-- 帰還の宝箱の吹き出しの中の宝箱を跳ねさせる（目を引くため：D-302）。
-- トンと高く跳ねて傾き、小さくもう1回跳ねて止まる、を HOP_CYCLE 秒ごとにくり返す（画面の動きの値。ゲームの数値ではない）
local HOP_CYCLE = 1.6
local HOP_HIGH, HOP_LOW = 12, 5 -- 跳ねる高さ（px）
hopHaul = function(t: number)
	for _, r in rows do
		local pic = r.haul.Visible and r.haul:FindFirstChild("Pic") :: Frame?
		if pic then
			local k = t % HOP_CYCLE
			local y, rot = 0, 0
			if k < 0.32 then
				local u = k / 0.32
				y = -math.sin(u * math.pi) * HOP_HIGH
				rot = math.sin(u * math.pi * 2) * 8
			elseif k < 0.52 then
				local u = (k - 0.32) / 0.2
				y = -math.sin(u * math.pi) * HOP_LOW
			end
			pic.Position = UDim2.new(0.5, 0, 0.5, y)
			pic.Rotation = rot
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
	mount3D()
	buildList(layer)
	buildEdges(layer)
	ReturnToast.mount() -- 帰還のトースト（11章 §5、M8-6）
	LoginSequence.mount() -- ログイン時のまとめ・カットイン・カレンダー（D-132・D-208、M8-6）
	Guide.mount() -- 初回の誘導（D-244 ①）
	Art.preloadChests() -- 開封の演出の箱の絵を先に読み込む（D-267）
	Session.changed:connect(function(view)
		refreshStatic(view)
		refreshMoving(view)
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		hopHaul(os.clock())
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
require("./chest/ChestFeature")
require("./chest/ChestReveal")
require("./chest/ChestResults")
require("./reward/RewardGet")
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
