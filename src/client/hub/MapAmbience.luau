--!strict
-- 3D マップの空気感（D-270）：古い家のテーブルに広げた地図。
--   - 光：窓から差す夕方の低い日差し。Guild UI の茶色に合わせて少しセピア寄り（彩度を少し落とし、暖色を薄く足す）。
--   - 部屋：テーブルのまわりに薄暗い木の部屋（床・壁・天井）を置き、青空を見せない。壁と天井は影を落とさない
--     （窓から日が差しているように、地図には日が当たる）。暖かい靄（Atmosphere）で奥をかすませ、画面の四隅を少し暗くする。
--   - 被写界深度：一眼レフのように、カメラの注目点にピントを合わせ、手前と奥をぼかす（毎フレーム合わせる）。
--   - 埃：注目点のまわりに、光を受けてゆっくり漂う細かい埃。窓からの光の筋。
--   ここの値は見た目の調整用（ゲームの数値ではない）。強すぎるときはここを下げる。

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MapCamera = require("./MapCamera")

local MapAmbience = {}

-- 光
local LIGHT = {
	Brightness = 2.2,
	ClockTime = 16.6, -- 夕方の低い日差し（窓から斜めに入る）
	GeographicLatitude = 38,
	Ambient = Color3.fromRGB(92, 72, 54),
	OutdoorAmbient = Color3.fromRGB(110, 88, 66),
	ColorShift_Top = Color3.fromRGB(255, 214, 160), -- 日の当たる面を暖色に
	ColorShift_Bottom = Color3.fromRGB(40, 28, 18),
	EnvironmentDiffuseScale = 0.35,
	EnvironmentSpecularScale = 0.45,
	ShadowSoftness = 0.35,
	ExposureCompensation = 0.1,
	GlobalShadows = true,
}

-- 色（少しセピア：やりすぎない）
local GRADE = {
	Saturation = -0.36,
	Contrast = 0.12,
	Brightness = 0.01,
	TintColor = Color3.fromRGB(255, 232, 198),
}

local BLOOM = { Intensity = 0.55, Size = 28, Threshold = 1.35 }
local RAYS = { Intensity = 0.035, Spread = 0.55 }

-- 部屋の空気（青空を暖かい靄で隠す）
local AIR = {
	Density = 0.75,
	Offset = 0.9, -- 空の上の方まで靄をかける（青空を見せない）
	Color = Color3.fromRGB(132, 102, 74),
	Decay = Color3.fromRGB(78, 56, 38),
	Glare = 0.1,
	Haze = 2.6,
}

-- 部屋（テーブルの天板の高さからの位置。カメラが届く範囲より外に置く）
local ROOM_HALF = 380 -- 壁までの距離
local ROOM_FLOOR = -105 -- 床（テーブルの脚が立つ所）
local ROOM_CEIL = 300 -- 天井
local ROOM_WALL = Color3.fromRGB(74, 54, 38)
local ROOM_FLOOR_COLOR = Color3.fromRGB(56, 38, 26)
local ROOM_CEIL_COLOR = Color3.fromRGB(42, 30, 21)

-- 被写界深度（ピントは毎フレーム、カメラから注目点までの距離に合わせる）
local DOF_NEAR = 0.6
local DOF_FAR = 0.5
local DOF_RADIUS = 0.18 -- ピントが合う幅（カメラの距離に対する割合）

-- 埃
local DUST_BOX = Vector3.new(70, 22, 70) -- 注目点のまわりの、埃が出る範囲
local DUST_COLOR = Color3.fromRGB(255, 232, 196)

-- 周辺減光（画面の端を少し暗く）
local VIGNETTE = 0.55 -- 端の暗さ（0＝なし、1＝真っ黒）
local VIGNETTE_WIDTH = 0.22 -- 暗くなり始める幅（画面に対する割合）

local dof: DepthOfFieldEffect? = nil
local dustPart: Part? = nil

local function effect<T>(className: string, name: string): T
	local e = Lighting:FindFirstChild(name)
	if e == nil or e.ClassName ~= className then
		if e then
			e:Destroy()
		end
		e = Instance.new(className);
		(e :: Instance).Name = name;
		(e :: Instance).Parent = Lighting
	end
	return e :: any
end

local function apply(inst: Instance, props: { [string]: any })
	for k, v in props do
		(inst :: any)[k] = v
	end
end

-- 画面の四辺を少し暗くする（UI より下に置く）
local function makeVignette()
	local pg = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	local old = pg:FindFirstChild("MapVignette")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MapVignette"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -10
	local edges = {
		{ size = UDim2.fromScale(1, VIGNETTE_WIDTH), pos = UDim2.fromScale(0, 0), rot = 90 },
		{ size = UDim2.fromScale(1, VIGNETTE_WIDTH), pos = UDim2.fromScale(0, 1 - VIGNETTE_WIDTH), rot = -90 },
		{ size = UDim2.fromScale(VIGNETTE_WIDTH, 1), pos = UDim2.fromScale(0, 0), rot = 0 },
		{ size = UDim2.fromScale(VIGNETTE_WIDTH, 1), pos = UDim2.fromScale(1 - VIGNETTE_WIDTH, 0), rot = 180 },
	}
	for i, e in edges do
		local f = Instance.new("Frame")
		f.Name = "Edge" .. i
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.fromRGB(20, 13, 8)
		f.Size = e.size
		f.Position = e.pos
		local g = Instance.new("UIGradient")
		g.Rotation = e.rot
		-- 外側ほど暗く、内側は透明（なめらかに消える）
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1 - VIGNETTE),
			NumberSequenceKeypoint.new(0.45, 1 - VIGNETTE * 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = f
		f.Parent = gui
	end
	gui.Parent = pg
end

-- 部屋：床・四方の壁・天井（影は落とさない）
local function makeRoom(topY: number)
	local old = Workspace:FindFirstChild("MapRoom")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "MapRoom"
	local h = ROOM_CEIL - ROOM_FLOOR
	local midY = topY + (ROOM_FLOOR + ROOM_CEIL) / 2
	local size = ROOM_HALF * 2
	local pieces = {
		{
			"Floor",
			Vector3.new(size, 2, size),
			Vector3.new(0, topY + ROOM_FLOOR - 1, 0),
			ROOM_FLOOR_COLOR,
			Enum.Material.WoodPlanks,
		},
		{
			"Ceiling",
			Vector3.new(size, 2, size),
			Vector3.new(0, topY + ROOM_CEIL + 1, 0),
			ROOM_CEIL_COLOR,
			Enum.Material.Wood,
		},
		{ "WallN", Vector3.new(size, h, 2), Vector3.new(0, midY, -ROOM_HALF - 1), ROOM_WALL, Enum.Material.WoodPlanks },
		{ "WallS", Vector3.new(size, h, 2), Vector3.new(0, midY, ROOM_HALF + 1), ROOM_WALL, Enum.Material.WoodPlanks },
		{ "WallW", Vector3.new(2, h, size), Vector3.new(-ROOM_HALF - 1, midY, 0), ROOM_WALL, Enum.Material.WoodPlanks },
		{ "WallE", Vector3.new(2, h, size), Vector3.new(ROOM_HALF + 1, midY, 0), ROOM_WALL, Enum.Material.WoodPlanks },
	}
	for _, d in pieces do
		local p = Instance.new("Part")
		p.Name = d[1]
		p.Size = d[2]
		p.Position = d[3]
		p.Color = d[4]
		p.Material = d[5]
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = folder
	end
	folder.Parent = Workspace
end

-- 埃：注目点のまわりの箱から、細かい粒がゆっくり漂う
local function makeDust(mapTopY: number)
	local p = Instance.new("Part")
	p.Name = "MapDust"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = DUST_BOX
	p.Position = Vector3.new(0, mapTopY + DUST_BOX.Y / 2, 0)

	-- 細かい埃（たくさん・小さい・光を受けて少し光る）
	local fine = Instance.new("ParticleEmitter")
	fine.Name = "Fine"
	fine.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	fine.Shape = Enum.ParticleEmitterShape.Box
	fine.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	fine.Rate = 22
	fine.Lifetime = NumberRange.new(9, 15)
	fine.Speed = NumberRange.new(0.05, 0.25)
	fine.SpreadAngle = Vector2.new(180, 180)
	fine.Acceleration = Vector3.new(0.02, -0.03, 0.01)
	fine.Drag = 0.4
	fine.RotSpeed = NumberRange.new(-20, 20)
	fine.Rotation = NumberRange.new(0, 360)
	fine.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.07),
		NumberSequenceKeypoint.new(0.5, 0.13),
		NumberSequenceKeypoint.new(1, 0.06),
	})
	fine.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.35),
		NumberSequenceKeypoint.new(0.8, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	fine.Color = ColorSequence.new(DUST_COLOR)
	fine.LightEmission = 0.5
	fine.LightInfluence = 0.6
	fine.Parent = p

	-- 大きめのふわっとした埃（少しだけ・ぼけて見える）
	local soft = Instance.new("ParticleEmitter")
	soft.Name = "Soft"
	soft.Texture = "rbxasset://textures/particles/smoke_main.dds"
	soft.Shape = Enum.ParticleEmitterShape.Box
	soft.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	soft.Rate = 2.5
	soft.Lifetime = NumberRange.new(10, 16)
	soft.Speed = NumberRange.new(0.05, 0.15)
	soft.SpreadAngle = Vector2.new(180, 180)
	soft.Acceleration = Vector3.new(0.015, -0.015, 0)
	soft.Drag = 0.5
	soft.RotSpeed = NumberRange.new(-8, 8)
	soft.Rotation = NumberRange.new(0, 360)
	soft.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 0.45),
	})
	soft.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.82),
		NumberSequenceKeypoint.new(0.7, 0.86),
		NumberSequenceKeypoint.new(1, 1),
	})
	soft.Color = ColorSequence.new(DUST_COLOR)
	soft.LightEmission = 0.3
	soft.LightInfluence = 0.7
	soft.Parent = p

	p.Parent = Workspace
	dustPart = p
end

function MapAmbience.mount(mapPart: BasePart?)
	apply(Lighting, LIGHT)
	apply(effect("ColorCorrectionEffect", "MapGrade"), GRADE)
	apply(effect("BloomEffect", "MapBloom"), BLOOM)
	apply(effect("SunRaysEffect", "MapRays"), RAYS)
	apply(effect("Atmosphere", "Atmosphere"), AIR)
	local d = effect("DepthOfFieldEffect", "DepthOfField") :: DepthOfFieldEffect
	d.NearIntensity = DOF_NEAR
	d.FarIntensity = DOF_FAR
	d.Enabled = true
	dof = d
	makeVignette()
	local topY = if mapPart then mapPart.Position.Y + mapPart.Size.Y / 2 else 5
	makeRoom(topY)
	makeDust(topY)

	RunService.RenderStepped:Connect(function()
		local cam = Workspace.CurrentCamera
		local focus, dist = MapCamera.state()
		local e = dof
		if e and cam then
			-- 注目点にピント（カメラからの実際の距離）
			e.FocusDistance = (cam.CFrame.Position - focus).Magnitude
			e.InFocusRadius = dist * DOF_RADIUS
		end
		local dp = dustPart
		if dp then
			-- 埃は注目点のまわりに置く（どこを見ても少し漂っている）
			dp.Position = Vector3.new(focus.X, topY + DUST_BOX.Y / 2, focus.Z)
		end
	end)
end

return MapAmbience
