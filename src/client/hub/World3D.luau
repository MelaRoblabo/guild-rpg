--!strict
-- 3D マップ（D-270）。テーブルの上の地図（Workspace.MAP）と、その上のミニチュア（Workspace["MAP Object"]）。
--   - Guild・Dungeon01〜12・EventPlace01〜04 の位置は Studio で動かす。ここは名前で探して位置を読む。
--   - ダンジョン：解放済みは表示、次に解放するものは Highlight で半透明の黒、その先は出さない（D-270 ③）。
--   - 馬車：移動中・帰り道だけ地図の上を動く。速さは距離に関係なく探索の移動秒数で往復（D-270 ②）。目的地へ Beam の点線。
--   - ギルド・ダンジョンの中のパーティは、その物の上に BillboardGui でリーダーのアイコン（D-270 ⑥・D-271）。
--   - タップした物（ダンジョン・ギルド・馬車）は handlers に渡す。画面の変更はすべてこの端末の中だけ（サーバーへは送らない）。

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Create = require("../ui/Create")
local HubState = require("./HubState")
local MapCamera = require("./MapCamera")
local PartyIcon = require("../ui/PartyIcon")
local Root = require("../ui/Root")
local Session = require("../Session")
local master = require("../Master")

local new = Create.new
local CHILDREN = Create.Children

local World3D = {}

export type Handlers = {
	onDungeon: (dungeonId: string) -> (),
	onGuild: () -> (),
	onParty: (partyIndex: number) -> (),
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
local highlights: { [BasePart]: Highlight } = {}
local carts: { [number]: Model } = {}
local beams: { [number]: Beam } = {}
local destAttach: { [BasePart]: Attachment } = {}
local boards: { [BasePart]: BillboardGui } = {}
local handlers: Handlers? = nil
local cartFolder: Folder? = nil
local boardFolder: Instance? = nil
local lastStatus: { [number]: any } = {}

local function topY(): number
	local m = mapPart
	return if m then m.Position.Y + m.Size.Y / 2 else 5
end

-- 物の地図の上の位置（足もと）
local function groundOf(obj: BasePart): Vector3
	return Vector3.new(obj.Position.X, topY(), obj.Position.Z)
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
		a = new("Attachment", {
			Name = "CartTarget",
			WorldPosition = groundOf(obj) + Vector3.new(0, 0.3, 0),
			Parent = obj,
		}) :: Attachment
		destAttach[obj] = a
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
		Adornee = obj,
		AlwaysOnTop = true,
		Active = true,
		Size = UDim2.fromOffset(ICON_SIZE * 4 + 30, ICON_SIZE + 16),
		StudsOffsetWorldSpace = Vector3.new(0, obj.Size.Y / 2 + 5, 0),
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
		for i = 1, 8 do
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
	RunService.RenderStepped:Connect(World3D.step)
end

-- マップイベントの場所（Studio の EventPlace01〜）
function World3D.eventPlace(index: number): BasePart?
	return eventPlaces[((index - 1) % math.max(1, #eventPlaces)) + 1]
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
		MapCamera.focus(cart.PrimaryPart.Position)
		return
	end
	local s = lastStatus[partyIndex]
	if s and s.state == "exploring" and s.dungeonId then
		World3D.focusDungeon(s.dungeonId)
	else
		World3D.focusGuild()
	end
end

-- タップした物を選ぶ
function World3D.pick(at: Vector2)
	local cam = Workspace.CurrentCamera
	if cam == nil or handlers == nil then
		return
	end
	local ray = cam:ScreenPointToRay(at.X, at.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local list: { Instance } = {}
	if folder then
		table.insert(list, folder :: Instance)
	end
	if cartFolder then
		table.insert(list, cartFolder :: Instance)
	end
	params.FilterDescendantsInstances = list
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	if hit == nil then
		return
	end
	local inst: Instance? = hit.Instance
	-- 馬車
	for i, c in carts do
		if inst and inst:IsDescendantOf(c) then
			handlers.onParty(i)
			return
		end
	end
	-- ダンジョン・ギルド（物の直下の箱まで上る）
	while inst and inst.Parent ~= folder do
		inst = inst.Parent
	end
	if inst == nil then
		return
	end
	if inst == guildObj then
		handlers.onGuild()
		return
	end
	for id, obj in dungeonObjs do
		if obj == inst and not hidden[obj] then
			handlers.onDungeon(id)
			return
		end
	end
end

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
			local hl = highlights[obj]
			if dark and hl == nil then
				highlights[obj] = new("Highlight", {
					Name = "NextDungeon",
					FillColor = Color3.new(0, 0, 0),
					FillTransparency = 0.45,
					OutlineTransparency = 1,
					DepthMode = Enum.HighlightDepthMode.Occluded,
					Adornee = obj,
					Parent = obj,
				}) :: Highlight
			elseif not dark and hl then
				hl:Destroy()
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
		elseif s.state == "exploring" and s.dungeonId then
			place = dungeonObjs[s.dungeonId]
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
			local dest = if s.state == "moving" then dungeonObjs[s.dungeonId] else guildObj
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
end

-- 毎フレーム：馬車を道の上で動かす（行きはギルド→ダンジョン、帰りはダンジョン→ギルド。along で位置）
function World3D.step()
	local view = Session.view
	if view == nil or guildObj == nil then
		return
	end
	for i, cart in carts do
		if cart.Parent and cart.PrimaryPart then
			local s = HubState.status(view, i)
			local d = if s.dungeonId then dungeonObjs[s.dungeonId] else nil
			if d then
				local g = groundOf(guildObj :: BasePart)
				local p = groundOf(d)
				local pos = g:Lerp(p, math.clamp(s.along, 0, 1)) + Vector3.new(0, CART_LIFT, 0)
				local toward = if s.state == "returning" then g else p
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
