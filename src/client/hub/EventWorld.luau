--!strict
-- 3D マップのイベントの物：旅の商人（D-274）とレイドボス（D-275）とレアダンジョンの水晶の祠（D-304）。
--   見本は Studio で作った模型（ReplicatedStorage.MapModels の MerchantCaravan・RaidBossShadow・RareCrystalShrine）。
--   出ている間だけ地図の上の場所に置く。
--   - 商人：Game.query.merchantPresence。頭上の札＝待っている「Leaves in 2:31」／向かっている＝パーティの顔＋「Arrives in 0:12」／
--     着いている＝パーティの顔＋「Shopping」。
--   - レイドボス：Game.query.raidPresence。頭上の札＝出発できる間「Leaves in 2:31」／3分間の後に向かっているパーティがいれば
--     その顔＋「Arrives in」。討伐したら去る。
--   - レアダンジョン（D-304）：出発できる3分間だけ。頭上の札＝「Leaves in 2:31」、出発したパーティがいればその顔。
--     祠のまわりの宝石（Orbit の Crystal1〜）は浮いてゆっくり回る。
--   - 残り30秒から警告の色。札か物を触ると開く（World3D の onMerchant・onRaid）。
--   - 出てくるとき・去るときは、煙がふわっと立ち、物が膨らんで現れる／しぼんで消える。
--     水晶の祠だけは別の動き（D-304）：地面に金の魔法陣が広がって祠がせり上がり、去るときは宝石が光の粒になって散って沈む。
--   マップの GUI の印（EventMarker）は商人・レイドボスには出さない。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Game = require("@game/ReplicatedStorage/Core/Game")
local Components = require("../ui/Components")
local Create = require("../ui/Create")
local Motion = require("../ui/Motion")
local PartyIcon = require("../ui/PartyIcon")
local Session = require("../Session")
local Tokens = require("../ui/Tokens")
local Words = require("../ui/Words")
local master = require("../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local EventWorld = {}

local POP_SECONDS = 0.45 -- 膨らんで現れる・しぼんで消える長さ
local MIN_SCALE = 0.05
local BOARD_LIFT = 2.5 -- 物のいちばん上から札までの高さ
local MODEL_NAME = { merchant = "MerchantCaravan", raid = "RaidBossShadow", rareDungeon = "RareCrystalShrine" } -- 見本の模型の名前
local RISE_SECONDS = 1.1 -- 水晶の祠がせり上がる長さ（D-304）
local SINK_SECONDS = 0.8 -- 水晶の祠が沈む長さ
local CIRCLE_SECONDS = 1.6 -- 魔法陣が広がって消えるまで
local ORBIT_SPEED = 0.6 -- 宝石が回る速さ（ラジアン／秒）
local GOLD = Color3.fromRGB(255, 214, 120) -- 魔法陣の金
local GEM = Color3.fromRGB(176, 150, 255) -- 宝石の光の粒
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local ENDING_SECONDS = master.K.mapEventEndingSeconds

type Crystal = { part: BasePart, angle: number, radius: number, height: number }

type Entry = {
	kind: string,
	slot: number,
	model: Model,
	board: BillboardGui,
	anchor: Part,
	phase: string,
	leaving: boolean,
	crystals: { Crystal }, -- 水晶の祠のまわりの宝石（D-304）。ほかの物は空
	core: BasePart?, -- 宝石が回る中心（水晶の祠の本体）
}

local templates: { [string]: Model } = {}
local folder: Folder? = nil
local boardParent: Instance? = nil
local placeFor: ((placeId: string) -> BasePart?)? = nil
local groundY: (() -> number)? = nil
local facing: (() -> Vector3?)? = nil
local onOpen: ((kind: string, eventSlot: number) -> ())? = nil
local entries: { [string]: Entry } = {} -- "種類:時間帯" → 物
local leavingCrystals: { { crystals: { Crystal }, core: BasePart, t0: number } } = {} -- 散っていく宝石（D-304）
local first = true -- 最初の表示（読み込んだときから出ている物）は演出なし

local function clock(s: number): string
	s = math.max(0, math.ceil(s))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- 煙をふわっと立てる（at：地図の上の足もと）
local function puff(at: Vector3, size: number)
	local f = folder
	if f == nil then
		return
	end
	local p: Part = new("Part", {
		Name = "MerchantPuff",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(size, 1, size),
		Position = at + Vector3.new(0, 0.5, 0),
		Parent = f,
	})
	local smoke: ParticleEmitter = new("ParticleEmitter", {
		Texture = SMOKE_TEXTURE,
		Enabled = false,
		Color = ColorSequence.new(Color3.fromRGB(226, 212, 188), Color3.fromRGB(170, 150, 124)),
		LightEmission = 0.05,
		LightInfluence = 0.6,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, size * 0.18),
			NumberSequenceKeypoint.new(1, size * 0.5),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.6, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(size * 0.25, size * 0.55),
		SpreadAngle = Vector2.new(180, 30),
		Acceleration = Vector3.new(0, size * 0.25, 0),
		Drag = 3,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
		EmissionDirection = Enum.NormalId.Top,
		Shape = Enum.ParticleEmitterShape.Disc,
		Parent = p,
	})
	local spark: ParticleEmitter = new("ParticleEmitter", {
		Texture = SPARK_TEXTURE,
		Enabled = false,
		Color = ColorSequence.new(Color3.fromRGB(255, 222, 150)),
		LightEmission = 0.7,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, size * 0.04),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(size * 0.3, size * 0.7),
		SpreadAngle = Vector2.new(180, 60),
		Acceleration = Vector3.new(0, -size * 0.2, 0),
		EmissionDirection = Enum.NormalId.Top,
		Parent = p,
	})
	local reduced = Motion.reduced()
	smoke:Emit(if reduced then 8 else 22)
	if not reduced then
		spark:Emit(10)
	end
	task.delay(2, function()
		p:Destroy()
	end)
end

-- 膨らむ／しぼむ（from → to の大きさ）。終わったら done
-- from・to は見本の大きさに対する割合（見本は Studio で拡大してあるので、ScaleTo には見本の倍率を掛ける）
local function scaleModel(model: Model, from: number, to: number, done: (() -> ())?)
	local t0 = os.clock()
	local base = model:GetAttribute("BaseScale") :: number?
	if base == nil then
		base = model:GetScale()
		model:SetAttribute("BaseScale", base)
	end
	local b = base :: number
	model:ScaleTo(b * math.max(from, MIN_SCALE))
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / POP_SECONDS, 0, 1)
		-- 現れるときは少し行き過ぎて戻る（back out）、消えるときはなめらかに
		local e = if to > from then 1 + 2.2 * (k - 1) ^ 3 + 1.2 * (k - 1) ^ 2 else k * k
		if model.Parent then
			model:ScaleTo(b * math.max(from + (to - from) * e, MIN_SCALE))
		end
		if k >= 1 then
			conn:Disconnect()
			if done then
				done()
			end
		end
	end)
end

-- 水晶の祠の足もとの金の魔法陣（D-304）：広がって回り、薄れて消える
local function magicCircle(at: Vector3, size: number)
	local f = folder
	if f == nil then
		return
	end
	local d = size * 1.25
	local p: Part = new("Part", {
		Name = "RareCircle",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(d, 0.05, d),
		Position = at + Vector3.new(0, 0.08, 0),
		Parent = f,
	})
	local gui: SurfaceGui = new("SurfaceGui", {
		Face = Enum.NormalId.Top,
		CanvasSize = Vector2.new(400, 400),
		LightInfluence = 0,
		Brightness = 2,
		Parent = p,
	})
	local BASE = { 0.94, 0.72, 0.52 } -- 外の輪・内の輪・菱形の大きさ
	local rings: { Frame } = {}
	for i, scale in BASE do
		local square = i == 3
		local children: { Instance } = { new("UIStroke", { Color = GOLD, Thickness = if i == 1 then 10 else 6 }) }
		if not square then
			table.insert(children, Components.corner(999))
		end
		rings[i] = new("Frame", {
			Name = "Ring" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(scale, scale),
			BackgroundTransparency = 1,
			Rotation = if square then 45 else 0,
			[CHILDREN] = children,
			Parent = gui,
		})
	end
	local reduced = Motion.reduced()
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / CIRCLE_SECONDS, 0, 1)
		local grow = math.clamp(k / 0.3, 0, 1)
		local scale = 1 - (1 - grow) ^ 3
		local fade = math.clamp((k - 0.55) / 0.45, 0, 1)
		for i, r in rings do
			r.Size = UDim2.fromScale(BASE[i] * scale, BASE[i] * scale)
			if not reduced then
				r.Rotation = (if i == 3 then 45 else 0) + (if i == 2 then -1 else 1) * k * 90
			end
			local st = r:FindFirstChildOfClass("UIStroke")
			if st then
				st.Transparency = fade
			end
		end
		if k >= 1 then
			conn:Disconnect()
			p:Destroy()
		end
	end)
end

-- 青紫の光の粒が弾ける（水晶の祠が去るとき：D-304）
local function shatter(at: Vector3, size: number)
	local f = folder
	if f == nil then
		return
	end
	local p: Part = new("Part", {
		Name = "RareShatter",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(size * 0.6, size * 0.6, size * 0.6),
		Position = at,
		Parent = f,
	})
	local spark: ParticleEmitter = new("ParticleEmitter", {
		Texture = SPARK_TEXTURE,
		Enabled = false,
		Color = ColorSequence.new(GEM, GOLD),
		LightEmission = 0.9,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, size * 0.07),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(size * 0.4, size * 0.9),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, size * 0.15, 0),
		Drag = 2,
		Shape = Enum.ParticleEmitterShape.Sphere,
		Parent = p,
	})
	spark:Emit(if Motion.reduced() then 12 else 40)
	task.delay(2, function()
		p:Destroy()
	end)
end

-- 模型を上下に動かす（from → to。1 が地面の上に立った位置、0 が depth だけ下）。終わったら done
local function slide(
	model: Model,
	rest: CFrame,
	depth: number,
	from: number,
	to: number,
	seconds: number,
	done: (() -> ())?
)
	local t0 = os.clock()
	model:PivotTo(rest - Vector3.new(0, depth * (1 - from), 0))
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / seconds, 0, 1)
		-- せり上がるときは少し行き過ぎて戻る、沈むときはだんだん速く
		local e = if to > from then 1 + 2.2 * (k - 1) ^ 3 + 1.2 * (k - 1) ^ 2 else k * k
		if model.Parent then
			model:PivotTo(rest - Vector3.new(0, depth * (1 - (from + (to - from) * e)), 0))
		end
		if k >= 1 then
			conn:Disconnect()
			if done then
				done()
			end
		end
	end)
end

-- 宝石を祠のまわりに回す（毎フレーム）。spread：散る割合（0＝回っているだけ、1＝散りきった）
local function placeCrystals(core: BasePart, crystals: { Crystal }, t: number, spread: number)
	local c = core.Position
	for i, cr in crystals do
		local a = cr.angle + t * ORBIT_SPEED
		local r = cr.radius * (1 + spread * 1.6)
		local h = cr.height + math.sin(t * 1.8 + i) * 0.3 + spread * 2
		cr.part.CFrame = CFrame.new(c.X + math.cos(a) * r, c.Y + h, c.Z + math.sin(a) * r)
			* CFrame.Angles(0, -a + t * 1.5, math.rad(12))
		cr.part.Transparency = 0.1 + 0.9 * spread
	end
end

-- 頭上の札（触ると開く）
local function makeBoard(anchor: Part, kind: string, eventSlot: number): BillboardGui
	local b: BillboardGui = new("BillboardGui", {
		Name = if kind == "raid" then "RaidBoard" elseif kind == "rareDungeon" then "RareBoard" else "MerchantBoard",
		Adornee = anchor,
		AlwaysOnTop = true,
		Active = true,
		Size = UDim2.fromOffset(280, 64),
		SizeOffset = Vector2.new(0, 0.5),
		Parent = boardParent,
	})
	local btn: TextButton = new("TextButton", {
		Name = "Open",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[CHILDREN] = {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = b,
	})
	btn.Activated:Connect(function()
		if onOpen then
			(onOpen :: (string, number) -> ())(kind, eventSlot)
		end
	end)
	local icon = PartyIcon.make(48)
	icon.LayoutOrder = 1
	icon.Visible = false
	icon.Parent = btn
	local chip = Components.chip("@time", "", C.bronzeHi)
	chip.Name = "Timer"
	chip.LayoutOrder = 2
	chip.Parent = btn
	return b
end

local function setChip(chip: Frame, icon: string, text: string, color: Color3?)
	local labels = {}
	for _, c in chip:GetChildren() do
		if c:IsA("TextLabel") then
			table.insert(labels, c)
		end
	end
	if labels[1] then
		Components.setText(labels[1], icon)
	end
	if labels[2] then
		labels[2].Text = text
		labels[2].TextColor3 = color or C.inkLight
	end
end

-- 地図の上に物を置く（足もとを地図の上に、ギルドの方を向く）
local function spawn(kind: string, p: any): Entry?
	local tpl, place = templates[kind], placeFor and (placeFor :: (string) -> BasePart?)(p.placeId)
	if tpl == nil or place == nil then
		return nil
	end
	local model = tpl:Clone()
	model.Name = MODEL_NAME[kind] .. "_" .. p.eventSlot
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	local cf, size = model:GetBoundingBox()
	local pivotToBottom = model:GetPivot().Position.Y - (cf.Position.Y - size.Y / 2)
	local y = if groundY then (groundY :: () -> number)() else place.Position.Y
	local base = Vector3.new(place.Position.X, y, place.Position.Z)
	local look = facing and (facing :: () -> Vector3?)()
	local dir = if look then Vector3.new(look.X - base.X, 0, look.Z - base.Z) else Vector3.zero
	local pos = base + Vector3.new(0, pivotToBottom, 0)
	local rot = if dir.Magnitude > 0.01 then CFrame.lookAt(pos, pos + dir) else CFrame.new(pos)
	model:PivotTo(rot)
	model.Parent = folder
	local anchor: Part = new("Part", {
		Name = "BoardAnchor",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(0.2, 0.2, 0.2),
		Position = base + Vector3.new(0, size.Y + BOARD_LIFT, 0),
		Parent = model,
	})
	local crystals: { Crystal } = {}
	local core = model.PrimaryPart
	local orbit = model:FindFirstChild("Orbit")
	if core and orbit then
		for _, c in orbit:GetChildren() do
			if c:IsA("BasePart") then
				local d = c.Position - core.Position
				table.insert(crystals, {
					part = c,
					angle = math.atan2(d.Z, d.X),
					radius = Vector3.new(d.X, 0, d.Z).Magnitude,
					height = d.Y,
				})
			end
		end
	end
	local entry: Entry = {
		kind = kind,
		slot = p.eventSlot,
		model = model,
		board = makeBoard(anchor, kind, p.eventSlot),
		anchor = anchor,
		phase = p.phase,
		leaving = false,
		crystals = crystals,
		core = core,
	}
	if not first then
		if kind == "rareDungeon" then
			-- 金の魔法陣が広がり、祠が下からせり上がる（D-304。地図より下は机に隠れて見えない）
			magicCircle(base, math.max(size.X, size.Z))
			if not Motion.reduced() then
				slide(model, rot, size.Y * 1.05, 0, 1, RISE_SECONDS)
			end
		else
			puff(base, math.max(size.X, size.Z))
			scaleModel(model, MIN_SCALE, 1)
		end
	end
	return entry
end

local function despawn(key: string, e: Entry)
	e.leaving = true
	e.board:Destroy()
	local cf, size = e.model:GetBoundingBox()
	if e.kind == "rareDungeon" then
		-- 宝石が光の粒になって散り、祠が沈む（D-304）
		local core = e.core
		shatter(cf.Position, math.max(size.X, size.Z))
		if core and #e.crystals > 0 then
			table.insert(leavingCrystals, { crystals = e.crystals, core = core, t0 = os.clock() })
		end
		slide(e.model, e.model:GetPivot(), size.Y * 1.05, 1, 0, SINK_SECONDS, function()
			e.model:Destroy()
		end)
		entries[key] = nil
		return
	end
	puff(Vector3.new(cf.Position.X, cf.Position.Y - size.Y / 2, cf.Position.Z), math.max(size.X, size.Z))
	scaleModel(e.model, 1, MIN_SCALE, function()
		e.model:Destroy()
	end)
	entries[key] = nil
end

-- getPlace：場所の id → 地図の上の Part（World3D の EventPlace01〜）。ground：地図の上の高さ。
-- face：物が向く所（ギルド）。open：物を触ったとき（種類と時間帯の番号）
function EventWorld.mount(
	getPlace: (placeId: string) -> BasePart?,
	ground: () -> number,
	face: () -> Vector3?,
	parentGui: Instance,
	open: (kind: string, eventSlot: number) -> ()
)
	placeFor, groundY, facing, boardParent, onOpen = getPlace, ground, face, parentGui, open
	folder = new("Folder", { Name = "MapEventObjects", Parent = Workspace }) :: Folder
	-- 水晶の祠のまわりの宝石を回す・散らす（D-304）。「動きを減らす」なら回さない（D-145）
	RunService.RenderStepped:Connect(function()
		local t = if Motion.reduced() then 0 else os.clock()
		for _, e in entries do
			local core = e.core
			if core and #e.crystals > 0 and not e.leaving then
				placeCrystals(core, e.crystals, t, 0)
			end
		end
		for i = #leavingCrystals, 1, -1 do
			local l = leavingCrystals[i]
			local k = math.clamp((os.clock() - l.t0) / SINK_SECONDS, 0, 1)
			if l.core.Parent then
				placeCrystals(l.core, l.crystals, t, k)
			end
			if k >= 1 then
				table.remove(leavingCrystals, i)
			end
		end
	end)
	-- 見本は ReplicatedStorage.MapModels（Studio で置いた模型）。Workspace に置いたままでも読む（その端末では地図から外す）
	local store = ReplicatedStorage:WaitForChild("MapModels", 10)
	for kind, name in MODEL_NAME do
		local tpl = (store and store:FindFirstChild(name)) or Workspace:FindFirstChild(name)
		if tpl and tpl:IsA("Model") then
			templates[kind] = tpl
			if tpl:IsDescendantOf(Workspace) then
				tpl.Parent = nil
			end
		end
	end
end

-- 光線が当たったら、その物の種類と時間帯の番号
function EventWorld.hit(inst: Instance?): (string?, number?)
	for _, e in entries do
		if inst and not e.leaving and inst:IsDescendantOf(e.model) then
			return e.kind, e.slot
		end
	end
	return nil, nil
end

function EventWorld.model(kind: string, eventSlot: number): Model?
	local e = entries[kind .. ":" .. eventSlot]
	return if e then e.model else nil
end

function EventWorld.folder(): Folder?
	return folder
end

local function timerText(left: number): (string, Color3?)
	return Words.leavesIn .. " " .. clock(left), if left <= ENDING_SECONDS then C.warn else nil
end

-- 0.1 秒ごと：出ている商人・レイドボス・水晶の祠をそろえ、頭上の札を更新する
function EventWorld.refresh(view: any)
	if view == nil or folder == nil then
		return
	end
	local now = Session.now()
	local seen: { [string]: boolean } = {}
	local function ensure(kind: string, p: any): Entry?
		local key = kind .. ":" .. p.eventSlot
		seen[key] = true
		local e = entries[key]
		if e == nil then
			e = spawn(kind, p)
			entries[key] = e
		end
		if e then
			e.phase = p.phase
		end
		return e
	end
	local function parts(e: Entry): (Frame, Frame)
		local btn = e.board:FindFirstChild("Open") :: TextButton
		return btn:FindFirstChild("PartyIcon") :: Frame, btn:FindFirstChild("Timer") :: Frame
	end
	for _, p in Game.query.merchantPresence(view, now, master) do
		local e = ensure("merchant", p)
		if e then
			local icon, chip = parts(e)
			if p.phase == "open" then
				icon.Visible = false
				local text, color = timerText(p.closesIn or 0)
				setChip(chip, "@time", text, color)
			else
				icon.Visible = true
				PartyIcon.set(icon, view, p.partyIndex, if p.phase == "coming" then "moving" else "exploring")
				if p.phase == "coming" then
					setChip(chip, "@time", Words.arrivesIn .. " " .. clock(p.arriveIn or 0))
				else
					setChip(chip, "@merchant", Words.shopping, C.okGreen)
				end
			end
		end
	end
	for _, p in Game.query.raidPresence(view, now, master) do
		local e = ensure("raid", p)
		if e then
			local icon, chip = parts(e)
			if p.phase == "open" then
				icon.Visible = false
				local text, color = timerText(p.closesIn or 0)
				setChip(chip, "@time", text, color)
			else
				icon.Visible = true
				PartyIcon.set(icon, view, p.coming[1], "moving")
				setChip(chip, "@time", Words.arrivesIn .. " " .. clock(p.arriveIn or 0))
			end
		end
	end
	-- レアダンジョン（D-304）：出発できる3分間だけ水晶の祠を出す。出発したパーティがいればその顔
	local cur = Game.query.mapEvent(now, master, view).current
	if cur and cur.open and cur.kind == "rareDungeon" then
		local e = ensure("rareDungeon", { eventSlot = cur.eventSlot, placeId = cur.placeId, phase = "open" })
		if e then
			local icon, chip = parts(e)
			local joined = Game.query.rareDungeon(view, cur.eventSlot, master).joined
			icon.Visible = #joined > 0
			if #joined > 0 then
				PartyIcon.set(icon, view, joined[1], "moving")
			end
			local text, color = timerText(cur.closesIn or 0)
			setChip(chip, "@time", text, color)
		end
	end
	for key, e in entries do
		if not seen[key] then
			despawn(key, e)
		end
	end
	first = false
end

return EventWorld
