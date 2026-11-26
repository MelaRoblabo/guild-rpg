--!strict
-- 3D マップ（D-270）。テーブルの上の地図（Workspace.MAP）と、その上のミニチュア（Workspace["MAP Object"]）。
--   - Guild・Dungeon01〜12・EventPlace01〜14 の位置は Studio で動かす。ここは名前で探して位置を読む。
--   - ダンジョン：解放済みは表示、次に解放するものは Highlight で半透明の黒、その先は出さない（D-270 ③）。
--   - 馬車：移動中・帰り道だけ地図の上を動く。速さは距離に関係なく探索の移動秒数で往復（D-270 ②）。目的地へ Beam の点線。
--   - ギルド・ダンジョンの中のパーティは、その物の上に BillboardGui でリーダーのアイコン（D-270 ⑥・D-271）。
--   - ゲームパッドのときは画面の中央に照準。重なった物の縁を光らせて名前の札を出し、A で開く（D-273 ④）。
--   - タップした物（ダンジョン・ギルド・馬車）は handlers に渡す。画面の変更はすべてこの端末の中だけ（サーバーへは送らない）。

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Expedition = require("@game/ReplicatedStorage/Core/Expedition")
local Game = require("@game/ReplicatedStorage/Core/Game")
local Components = require("../ui/Components")
local Create = require("../ui/Create")
local HubState = require("./HubState")
local MapAmbience = require("./MapAmbience")
local MapCamera = require("./MapCamera")
local EventWorld = require("./EventWorld")
local PartyIcon = require("../ui/PartyIcon")
local Root = require("../ui/Root")
local Session = require("../Session")
local Tokens = require("../ui/Tokens")
local Words = require("../ui/Words")
local master = require("../Master")

local new = Create.new
local CHILDREN = Create.Children

local World3D = {}

export type Handlers = {
	onDungeon: (dungeonId: string) -> (),
	onGuild: () -> (),
	onParty: (partyIndex: number) -> (),
	onMerchant: (eventSlot: number) -> (), -- 旅の商人（D-274）
	onRaid: (eventSlot: number) -> (), -- レイドボス（D-275）
}

local DOT_TEXTURE = "rbxasset://textures/ui/traildot.png" -- Beam の点線（D-270 ②）
local CART_LIFT = 0.7 -- 地図の上から馬車の中心までの高さ
local ICON_SIZE = 54 -- ギルド・ダンジョンの上のリーダーのアイコン

local mapPart: BasePart? = nil
local folder: Instance? = nil
local guildObj: BasePart? = nil
local dungeonObjs: { [string]: BasePart } = {} -- dungeonId → 物（Dungeon01〜）
local eventPlaces: { BasePart } = {}
local hidden: { [BasePart]: boolean } = {}
local highlights: { [BasePart]: { Highlight } } = {}
local carts: { [number]: Model } = {}
local beams: { [number]: Beam } = {}
local destAttach: { [BasePart]: Attachment } = {}
local boards: { [BasePart]: BillboardGui } = {}
local topAttach: { [BasePart]: Attachment } = {} -- 物の真上（板を付ける所）
local handlers: Handlers? = nil
local cartFolder: Folder? = nil
local boardFolder: Instance? = nil
local lastStatus: { [number]: any } = {}

-- ゲームパッドの照準（D-273 ④）
type Target = { kind: string, id: string?, index: number?, model: Instance }
local reticle: ScreenGui? = nil
local aimLabel: TextLabel? = nil
local aimLight: Highlight? = nil
local aimed: Target? = nil
local makeReticle: (parent: Instance) -> ()
local updateAim: () -> ()

local function topY(): number
	local m = mapPart
	return if m then m.Position.Y + m.Size.Y / 2 else 5
end

-- 物の見えている形（中の模型を含む）の範囲。外側の箱と模型の中心がずれていても、模型の真ん中を使う。
-- 模型の Part が多い（数百）ので、物ごとに一度だけ計算して覚える（プレイ中は物を動かさない）
local boundsCache: { [BasePart]: { Vector3 } } = {}
local function boundsOf(obj: BasePart): (Vector3, Vector3)
	local cached = boundsCache[obj]
	if cached then
		return cached[1], cached[2]
	end
	local minV, maxV = nil :: Vector3?, nil :: Vector3?
	local function add(part: BasePart)
		local half = part.Size / 2
		local cf = part.CFrame
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local c = cf:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
					minV = if minV then minV:Min(c) else c
					maxV = if maxV then maxV:Max(c) else c
				end
			end
		end
	end
	local any = false
	for _, d in obj:GetDescendants() do
		if d:IsA("BasePart") then
			add(d)
			any = true
		end
	end
	if not any then
		add(obj) -- 仮の Part（中に模型がない）
	end
	boundsCache[obj] = { minV :: Vector3, maxV :: Vector3 }
	return minV :: Vector3, maxV :: Vector3
end

-- 物の地図の上の位置（模型の真ん中の足もと）
local function groundOf(obj: BasePart): Vector3
	local minV, maxV = boundsOf(obj)
	local c = (minV + maxV) / 2
	return Vector3.new(c.X, topY(), c.Z)
end

-- 物の真上（模型のいちばん上の少し上）に置いた Attachment。板（BillboardGui）をここに付ける
local function topOf(obj: BasePart): Attachment
	local a = topAttach[obj]
	if a and a.Parent then
		return a
	end
	local minV, maxV = boundsOf(obj)
	local c = (minV + maxV) / 2
	local att = new("Attachment", { Name = "BoardAnchor", Parent = obj }) :: Attachment
	att.WorldPosition = Vector3.new(c.X, maxV.Y + 2.5, c.Z)
	topAttach[obj] = att
	return att
end

-- 中に模型（子の Part）がある物は、外側の箱を見えなくする（位置と当たり判定のために残す）
local function hideShell(obj: BasePart)
	for _, d in obj:GetDescendants() do
		if d:IsA("BasePart") then
			obj.Transparency = 1
			return
		end
	end
end

-- 馬車の模型（仮。Part で組む）
local function makeCart(partyIndex: number): Model
	local m = new("Model", { Name = "Cart" .. partyIndex }) :: Model
	local body = new("Part", {
		Name = "Body",
		Size = Vector3.new(2.6, 1, 1.6),
		Color = Color3.fromRGB(120, 78, 44),
		Material = Enum.Material.Wood,
		Anchored = true,
		CanCollide = false,
		Parent = m,
	}) :: Part
	new("Part", {
		Name = "Cover",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.4, 1.7, 1.7),
		Color = Color3.fromRGB(236, 226, 205),
		Material = Enum.Material.Fabric,
		Anchored = true,
		CanCollide = false,
		CFrame = body.CFrame * CFrame.new(0, 0.55, 0),
		Parent = m,
	})
	for _, off in
		{
			Vector3.new(0.85, -0.45, 0.85),
			Vector3.new(-0.85, -0.45, 0.85),
			Vector3.new(0.85, -0.45, -0.85),
			Vector3.new(-0.85, -0.45, -0.85),
		}
	do
		new("Part", {
			Name = "Wheel",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.25, 0.9, 0.9),
			Color = Color3.fromRGB(45, 32, 22),
			Anchored = true,
			CanCollide = false,
			CFrame = body.CFrame * CFrame.new(off) * CFrame.Angles(0, math.rad(90), 0),
			Parent = m,
		})
	end
	m.PrimaryPart = body
	new("Attachment", { Name = "BeamFrom", Position = Vector3.new(0, 0.3, 0), Parent = body })
	return m
end

local function attachmentOn(obj: BasePart): Attachment
	local a = destAttach[obj]
	if a == nil or a.Parent == nil then
		-- 先に親を決めてから世界の位置を入れる（親より先に入れると物の中心からの位置になり、宙に浮いた）
		local att = new("Attachment", { Name = "CartTarget", Parent = obj }) :: Attachment
		att.WorldPosition = groundOf(obj) + Vector3.new(0, 0.3, 0) -- 物の下（地図の上）
		destAttach[obj] = att
		a = att
	end
	return a :: Attachment
end

-- ギルド・ダンジョンの上のリーダーのアイコンの板
local function boardOn(obj: BasePart): BillboardGui
	local b = boards[obj]
	if b and b.Parent then
		return b
	end
	b = new("BillboardGui", {
		Name = "Board_" .. obj.Name,
		Adornee = topOf(obj), -- 物の真上（模型の真ん中の上）
		AlwaysOnTop = true,
		Active = true,
		Size = UDim2.fromOffset(ICON_SIZE * 4 + 30, ICON_SIZE + 16),
		SizeOffset = Vector2.new(0, 0.5), -- 板の下の辺を物の真上に合わせる
		ResetOnSpawn = false,
		[CHILDREN] = {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = boardFolder,
	}) :: BillboardGui
	boards[obj] = b
	return b :: BillboardGui
end

-- 板の上のパーティのアイコン（押すとパーティの面）
local function iconButton(board: BillboardGui, partyIndex: number): Frame
	local name = "Party" .. partyIndex
	local holder = board:FindFirstChild(name) :: Frame?
	if holder then
		return holder
	end
	local h: Frame = new("Frame", {
		Name = name,
		LayoutOrder = partyIndex,
		Size = UDim2.fromOffset(ICON_SIZE + 8, ICON_SIZE + 8),
		BackgroundTransparency = 1,
		Parent = board,
	})
	local icon = PartyIcon.make(ICON_SIZE)
	icon.Position = UDim2.fromOffset(4, 6)
	icon.Parent = h
	local tap: TextButton = new("TextButton", {
		Name = "Tap",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = h,
	})
	tap.Activated:Connect(function()
		if handlers then
			handlers.onParty(partyIndex)
		end
	end)
	return h
end

function World3D.mount(h: Handlers)
	handlers = h
	-- 地図と物が届くまで少し待つ（Workspace.StreamingEnabled はオフにしている：D-270）
	mapPart = Workspace:WaitForChild("MAP", 10) :: BasePart?
	folder = Workspace:WaitForChild("MAP Object", 10)
	local f = folder
	if mapPart then
		MapCamera.setBounds(mapPart :: BasePart)
	end
	if f then
		guildObj = (f:FindFirstChild("Guild") or f:FindFirstChild("Guid")) :: BasePart?
		for i, d in master.dungeonList do
			local obj = f:FindFirstChild(string.format("Dungeon%02d", i)) :: BasePart?
			if obj then
				dungeonObjs[d.id] = obj
				hideShell(obj)
			end
		end
		for i = 1, #master.mapEventPlaces do -- マスターデータの場所の数だけ（D-276）
			local p = f:FindFirstChild(string.format("EventPlace%02d", i)) :: BasePart?
			if p then
				p.Transparency = 1
				table.insert(eventPlaces, p)
			end
		end
		if guildObj then
			hideShell(guildObj :: BasePart)
		end
	end
	cartFolder = new("Folder", { Name = "GuildCarts", Parent = Workspace }) :: Folder
	-- 板（BillboardGui）は PlayerGui の直下に置く（フォルダの中だと押せない・出ないことがある）
	boardFolder = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	MapCamera.onTap = World3D.pick
	MapCamera.enable()
	MapAmbience.mount(mapPart) -- 光・色・被写界深度・埃
	makeReticle(boardFolder :: Instance)
	RunService.RenderStepped:Connect(World3D.step)
	RunService.RenderStepped:Connect(updateAim)
	-- 旅の商人（D-274）・レイドボス（D-275）：ReplicatedStorage.MapModels の模型を見本に、出ている間だけ場所に置く
	EventWorld.mount(
		World3D.placeOf,
		topY,
		function(): Vector3?
			return if guildObj then groundOf(guildObj :: BasePart) else nil
		end,
		boardFolder :: Instance,
		function(kind: string, slot: number)
			local hd = handlers
			if hd == nil then
				return
			end
			if kind == "raid" then
				hd.onRaid(slot)
			else
				hd.onMerchant(slot)
			end
		end
	)
end

-- マップイベントの場所（Studio の EventPlace01〜）
function World3D.eventPlace(index: number): BasePart?
	return eventPlaces[((index - 1) % math.max(1, #eventPlaces)) + 1]
end

-- マップイベントの場所の id → 地図の上の Part
function World3D.placeOf(placeId: string): BasePart?
	for i, pl in master.mapEventPlaces do
		if pl.id == placeId then
			return World3D.eventPlace(i)
		end
	end
	return nil
end

-- 探索の行き先の物（商人へ向かうパーティは商人の場所：D-274。ほかはダンジョン）
local function destOf(e: any): BasePart?
	if e == nil then
		return nil
	end
	if e.merchant then
		return World3D.placeOf(e.placeId)
	end
	if e.raidDamage and e.eventSlot then
		return World3D.placeOf(Game.query.mapEventAt(e.eventSlot, master).placeId) -- レイドボスの場所（D-275）
	end
	return dungeonObjs[e.dungeonId]
end

function World3D.dungeonObject(id: string): BasePart?
	return dungeonObjs[id]
end

function World3D.guild(): BasePart?
	return guildObj
end

-- 画面の位置（基準の単位）。飛ばす動き（Motion.fly）の行き先に使う
function World3D.screenPoint(obj: BasePart?): Vector2?
	local cam = Workspace.CurrentCamera
	if obj == nil or cam == nil then
		return nil
	end
	local v, onScreen = cam:WorldToViewportPoint(obj.Position)
	if not onScreen then
		return nil
	end
	local inset = game:GetService("GuiService"):GetGuiInset()
	local scale = math.max(Root.frame.scale, 0.01)
	local origin = Root.canvas.AbsolutePosition
	return (Vector2.new(v.X, v.Y) - inset - origin) / scale
end

function World3D.focusGuild()
	if guildObj then
		MapCamera.focus(groundOf(guildObj :: BasePart))
	end
end

function World3D.focusDungeon(id: string)
	local obj = dungeonObjs[id]
	if obj then
		MapCamera.focus(groundOf(obj))
	end
end

-- パーティのいる所（馬車か、ギルド・ダンジョン）へ
function World3D.focusParty(partyIndex: number)
	local cart = carts[partyIndex]
	if cart and cart.Parent and cart.PrimaryPart then
		-- 動く馬車は、寄ったあとも追う（ギルド・ダンジョンに入ったら止まる）
		MapCamera.focus(cart.PrimaryPart.Position, function(): Vector3?
			local c = carts[partyIndex]
			if c and c.Parent and c.PrimaryPart then
				return (c.PrimaryPart :: BasePart).Position
			end
			return nil
		end)
		return
	end
	local s = lastStatus[partyIndex]
	if s and s.state == "exploring" and s.merchant then
		local dest = destOf(Game.query.expeditionOf(Session.view, partyIndex))
		if dest then
			MapCamera.focus(groundOf(dest))
		end
	elseif s and s.state == "exploring" and s.dungeonId then
		World3D.focusDungeon(s.dungeonId)
	else
		World3D.focusGuild()
	end
end

-- 光線が当たった物（馬車・ギルド・ダンジョン）
local function hitBy(ray: Ray): Target?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local list: { Instance } = {}
	if folder then
		table.insert(list, folder :: Instance)
	end
	if cartFolder then
		table.insert(list, cartFolder :: Instance)
	end
	local mf = EventWorld.folder()
	if mf then
		table.insert(list, mf :: Instance)
	end
	params.FilterDescendantsInstances = list
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	if hit == nil then
		return nil
	end
	local inst: Instance? = hit.Instance
	-- 旅の商人（D-274）・レイドボス（D-275）
	local evKind, slot = EventWorld.hit(inst)
	if evKind and slot then
		return { kind = evKind, index = slot, model = EventWorld.model(evKind, slot) :: Model }
	end
	-- 馬車
	for i, c in carts do
		if inst and inst:IsDescendantOf(c) then
			return { kind = "party", index = i, model = c }
		end
	end
	-- ダンジョン・ギルド（物の直下の箱まで上る）
	while inst and inst.Parent ~= folder do
		inst = inst.Parent
	end
	if inst == nil then
		return nil
	end
	if inst == guildObj then
		return { kind = "guild", model = inst }
	end
	for id, obj in dungeonObjs do
		if obj == inst and not hidden[obj] then
			return { kind = "dungeon", id = id, model = obj }
		end
	end
	return nil
end

local function open(t: Target?)
	local h = handlers
	if t == nil or h == nil then
		return
	end
	if t.kind == "party" then
		h.onParty(t.index :: number)
	elseif t.kind == "guild" then
		h.onGuild()
	elseif t.kind == "merchant" then
		h.onMerchant(t.index :: number)
	elseif t.kind == "raid" then
		h.onRaid(t.index :: number)
	else
		h.onDungeon(t.id :: string)
	end
end

-- タップした物を選ぶ
function World3D.pick(at: Vector2)
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return
	end
	open(hitBy(cam:ScreenPointToRay(at.X, at.Y)))
end

-- 照準の札の名前
local function targetName(t: Target): string
	if t.kind == "party" then
		return PartyIcon.name(Session.view, t.index :: number)
	elseif t.kind == "guild" then
		return Words.guild
	elseif t.kind == "merchant" then
		return Words.merchant
	elseif t.kind == "raid" then
		return Words.raidBoss
	end
	local d = master.dungeons[t.id :: string]
	return if d then d.nameEn else ""
end

-- 縁を光らせる所：見えている模型（外側の箱は透明なので、子の Model・Part）
local function lightTarget(t: Target): Instance
	if t.kind == "party" or t.kind == "merchant" or t.kind == "raid" then
		return t.model
	end
	for _, c in t.model:GetChildren() do
		if c:IsA("Model") or c:IsA("BasePart") then
			return c
		end
	end
	return t.model
end

function makeReticle(parent: Instance)
	local C = Tokens.color
	local gui = new("ScreenGui", {
		Name = "MapReticle",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		Enabled = false,
		Parent = parent,
	}) :: ScreenGui
	local ring = new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(34, 34),
		BackgroundTransparency = 1,
		[CHILDREN] = {
			Components.corner(17),
			new("UIStroke", { Color = C.inkLight, Thickness = 3, Transparency = 0.15 }),
		},
		Parent = gui,
	})
	new("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = C.inkLight,
		[CHILDREN] = { Components.corner(3) },
		Parent = ring,
	})
	local label = Components.text({
		text = "",
		size = 24,
		color = C.inkLight,
		font = Tokens.font.display,
	})
	label.Name = "AimName"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0.5, 30)
	label.BackgroundColor3 = C.ch10
	label.BackgroundTransparency = 0.2
	label.Visible = false
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = label,
	})
	Components.corner(10).Parent = label
	label.Parent = gui
	reticle = gui
	aimLabel = label
	aimLight = new("Highlight", {
		Name = "Aim",
		FillTransparency = 1,
		OutlineColor = C.selAmber,
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		Enabled = false,
		Parent = cartFolder,
	}) :: Highlight
end

-- 毎フレーム：照準の下の物を調べる
function updateAim()
	local gui, label, light = reticle, aimLabel, aimLight
	if gui == nil or label == nil or light == nil then
		return
	end
	local cam = Workspace.CurrentCamera
	local on = cam ~= nil and MapCamera.padMode() and MapCamera.mapAimAllowed()
	gui.Enabled = on
	local t: Target? = nil
	if on and cam then
		local vp = cam.ViewportSize
		t = hitBy(cam:ViewportPointToRay(vp.X / 2, vp.Y / 2))
	end
	aimed = t
	if t then
		light.Adornee = lightTarget(t)
		light.Enabled = true
		label.Text = targetName(t)
		label.Visible = true
	else
		light.Enabled = false
		light.Adornee = nil
		label.Visible = false
	end
end

-- A：照準の物を開く（D-273 ④）
UserInputService.InputBegan:Connect(function(input, gp)
	if gp or input.KeyCode ~= Enum.KeyCode.ButtonA then
		return
	end
	if aimed and MapCamera.padMode() and MapCamera.mapAimAllowed() then
		open(aimed)
	end
end)

-- 状態が変わったとき（0.1秒ごと）：ダンジョンの見え方とパーティの置き場所
function World3D.refresh(view: any)
	if view == nil or folder == nil then
		return
	end
	-- ダンジョン：解放済み＝表示、次＝黒の Highlight、その先＝出さない（D-270 ③）
	local nextFound = false
	for _, d in master.dungeonList do
		local obj = dungeonObjs[d.id]
		if obj then
			local unlocked = view.unlockedDungeons and view.unlockedDungeons[d.id] == true
			local show = unlocked or not nextFound
			local dark = not unlocked and not nextFound
			if not unlocked then
				nextFound = true
			end
			if show and hidden[obj] then
				obj.Parent = folder
				hidden[obj] = nil
			elseif not show and not hidden[obj] then
				obj.Parent = nil
				hidden[obj] = true
			end
			-- 黒の Highlight は、見えている模型（子の Model・Part）に付ける。外側の箱は透明なので、箱に付けても塗られない
			local hls = highlights[obj]
			if dark and hls == nil then
				local list: { Highlight } = {}
				local targets: { Instance } = {}
				for _, c in obj:GetChildren() do
					if c:IsA("Model") or c:IsA("BasePart") then
						table.insert(targets, c)
					end
				end
				if #targets == 0 then
					table.insert(targets, obj) -- 仮の Part
				end
				for _, t in targets do
					table.insert(
						list,
						new("Highlight", {
							Name = "NextDungeon",
							FillColor = Color3.new(0, 0, 0),
							FillTransparency = 0.35,
							OutlineTransparency = 1,
							DepthMode = Enum.HighlightDepthMode.Occluded,
							Adornee = t,
							Parent = obj,
						}) :: Highlight
					)
				end
				highlights[obj] = list
			elseif not dark and hls then
				for _, hl in hls do
					hl:Destroy()
				end
				highlights[obj] = nil
			end
		end
	end
	-- パーティ：ギルド・ダンジョンの中ならアイコン、移動中なら馬車
	local inPlace: { [BasePart]: { [number]: boolean } } = {}
	for _, party in view.parties or {} do
		local i = party.index
		local s = HubState.status(view, i)
		lastStatus[i] = s
		local place: BasePart? = nil
		if s.state == "waiting" then
			place = guildObj
		elseif s.state == "exploring" and s.dungeonId and not s.merchant then
			place = dungeonObjs[s.dungeonId] -- 商人のところにいるときは、商人の頭上の札に顔を出す（D-274）
		end
		if place then
			inPlace[place] = inPlace[place] or {}
			inPlace[place][i] = true
			local icon = iconButton(boardOn(place), i):FindFirstChild("PartyIcon") :: Frame
			PartyIcon.set(icon, view, i, s.state)
		end
		-- 馬車
		local moving = s.state == "moving" or s.state == "returning"
		local cart = carts[i]
		if moving and cart == nil then
			cart = makeCart(i)
			carts[i] = cart
		end
		if cart then
			cart.Parent = if moving then cartFolder else nil
		end
		-- 点線（馬車 → 目的地）
		local beam = beams[i]
		if moving and cart and s.dungeonId then
			local dest = if s.state == "moving" then destOf(Game.query.expeditionOf(view, i)) else guildObj
			if dest then
				if beam == nil then
					beam = new("Beam", {
						Name = "Route" .. i,
						Texture = DOT_TEXTURE,
						TextureMode = Enum.TextureMode.Static,
						TextureLength = 1.2,
						TextureSpeed = 0.6,
						Width0 = 0.6,
						Width1 = 0.6,
						FaceCamera = true,
						LightEmission = 0.6,
						Color = ColorSequence.new(Color3.fromRGB(255, 205, 90)),
						Transparency = NumberSequence.new(0.1),
						Segments = 1,
					}) :: Beam
					beams[i] = beam
				end
				local b = beam :: Beam
				b.Attachment0 = (cart.PrimaryPart :: BasePart):FindFirstChild("BeamFrom") :: Attachment
				b.Attachment1 = attachmentOn(dest)
				b.Parent = cart.PrimaryPart
			end
		elseif beam then
			beam.Parent = nil
		end
	end
	-- いなくなったパーティのアイコンを消す
	for obj, board in boards do
		for _, c in board:GetChildren() do
			if c:IsA("Frame") then
				local idx = tonumber(string.match(c.Name, "^Party(%d+)$"))
				if idx and not (inPlace[obj] and inPlace[obj][idx]) then
					c:Destroy()
				end
			end
		end
	end
	EventWorld.refresh(view)
end

-- 毎フレーム：馬車を道の上で動かす（行きはギルド→ダンジョン、帰りはダンジョン→ギルド。along で位置）
function World3D.step()
	local view = Session.view
	if view == nil or guildObj == nil then
		return
	end
	-- 秒より細かい今の時刻で位置を出す（Session.now は秒で切り捨てるので、馬車がカクついた）
	local now = Workspace:GetServerTimeNow()
	for i, cart in carts do
		if cart.Parent and cart.PrimaryPart then
			local e = Game.query.expeditionOf(view, i)
			local d = destOf(e)
			if e and e.log and d then
				local pr = Expedition.progressAt(e.log, now)
				local along = if pr.phase == "outbound"
					then pr.ratio
					elseif pr.phase == "inbound" then 1 - pr.ratio
					elseif pr.phase == "returned" then 0
					else 1
				local returning = pr.phase == "inbound" or pr.phase == "returned"
				local g = groundOf(guildObj :: BasePart)
				local p = groundOf(d)
				local pos = g:Lerp(p, math.clamp(along, 0, 1)) + Vector3.new(0, CART_LIFT, 0)
				local toward = if returning then g else p
				local dir = Vector3.new(toward.X - pos.X, 0, toward.Z - pos.Z)
				local cf = if dir.Magnitude > 0.01
					then CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, math.rad(90), 0)
					else CFrame.new(pos)
				cart:PivotTo(cf)
			end
		end
	end
end

return World3D
