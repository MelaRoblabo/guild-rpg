--!strict
-- 3D マップの日替わりダンジョンの目印（D-305。日替わりの特性は D-156、色と印は太陽・金：D-162）。
--   - 今日の特性が付いているダンジョン（帯ごとに1つ）の上空に、金の太陽のメダル（ReplicatedStorage.MapModels.DailySunMarker）を浮かべる。
--     ゆっくり回りながら上下に揺れる。高さはダンジョンの頭上の札（パーティの顔）より上。
--   - ダンジョン全体から金の光の粒と光の筋が立ちのぼり、足もとを暖かい光で照らす（模型を金に光らせる Highlight は使わない）。
--   - 地図に出ていないダンジョン（まだ先のもの）には出さない。日が変わったら付け替える。
--   - 「動きを減らす」（D-145）なら回さず揺らさず、光の粒も減らす。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Create = require("../ui/Create")
local Motion = require("../ui/Motion")

local new = Create.new

local DailyWorld = {}

local TEMPLATE = "DailySunMarker" -- ReplicatedStorage.MapModels の見本
local LIFT = 9 -- ダンジョンのいちばん上からメダルの中心までの高さ（頭上の札 +2.5 より上）
local BOB = 0.6 -- 上下の揺れの幅
local SPIN = 0.8 -- 回る速さ（ラジアン／秒）
local GOLD = Color3.fromRGB(255, 214, 120)
local GOLD_DEEP = Color3.fromRGB(255, 170, 70)
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

type Mark = { sun: Model, glow: Part, center: Vector3, phase: number }

local template: Model? = nil
local folder: Folder? = nil
local marks: { [string]: Mark } = {} -- dungeonId → 目印

function DailyWorld.mount()
	folder = new("Folder", { Name = "DailyMarks", Parent = Workspace }) :: Folder
	local store = ReplicatedStorage:WaitForChild("MapModels", 10)
	local tpl = store and store:FindFirstChild(TEMPLATE)
	if tpl and tpl:IsA("Model") then
		template = tpl
	end
	RunService.RenderStepped:Connect(function()
		local reduced = Motion.reduced()
		local t = os.clock()
		for _, m in marks do
			local y = if reduced then 0 else math.sin(t * 1.6 + m.phase) * BOB
			local a = if reduced then 0 else t * SPIN + m.phase
			m.sun:PivotTo(CFrame.new(m.center + Vector3.new(0, y, 0)) * CFrame.Angles(0, a, 0))
		end
	end)
end

-- ダンジョン全体から立ちのぼる金の光の粒と、足もとの暖かい光（minV・maxV：ダンジョンの模型の範囲）
local function makeGlow(minV: Vector3, maxV: Vector3, parent: Instance): Part
	local size = maxV - minV
	local c = (minV + maxV) / 2
	local p: Part = new("Part", {
		Name = "DailyGlow",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
		Size = Vector3.new(size.X, 0.2, size.Z),
		Position = Vector3.new(c.X, minV.Y + 0.2, c.Z),
		Parent = parent,
	})
	local reduced = Motion.reduced()
	local h = math.max(size.Y, 3)
	-- 小さな光の粒：ダンジョンの足もと全体から、ゆっくり上へ
	new("ParticleEmitter", {
		Name = "Motes",
		Texture = SPARK_TEXTURE,
		Color = ColorSequence.new(GOLD, GOLD_DEEP),
		LightEmission = 0.8,
		LightInfluence = 0,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(0.6, 0.55),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(0.2, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(1.8, 2.8),
		Rate = if reduced then 10 else 34,
		Speed = NumberRange.new(h * 0.45, h * 0.8),
		SpreadAngle = Vector2.new(8, 8),
		EmissionDirection = Enum.NormalId.Top,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Parent = p,
	})
	-- 細長い光の筋：ときどき足もとから立ちのぼる（「動きを減らす」なら出さない）
	if not reduced then
		new("ParticleEmitter", {
			Name = "Rays",
			Texture = SPARK_TEXTURE,
			Color = ColorSequence.new(GOLD),
			LightEmission = 1,
			LightInfluence = 0,
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.45),
				NumberSequenceKeypoint.new(1, 0.2),
			}),
			Squash = NumberSequence.new(-2.5),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.35),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(1.2, 1.8),
			Rate = 9,
			Speed = NumberRange.new(h * 0.9, h * 1.3),
			SpreadAngle = Vector2.new(2, 2),
			EmissionDirection = Enum.NormalId.Top,
			Shape = Enum.ParticleEmitterShape.Box,
			Parent = p,
		})
	end
	new("PointLight", {
		Color = GOLD,
		Range = math.max(size.X, size.Z) * 1.1,
		Brightness = 1.2,
		Parent = p,
	})
	return p
end

local function remove(id: string)
	local m = marks[id]
	if m then
		m.sun:Destroy()
		m.glow:Destroy()
		marks[id] = nil
	end
end

-- 0.1 秒ごと（World3D.refresh から）。shown：今日の日替わりのダンジョンのうち地図に出ているもの
--   { [dungeonId] = { minV, maxV } }（ダンジョンの模型の範囲）
export type Shown = { minV: Vector3, maxV: Vector3 }
function DailyWorld.refresh(shown: { [string]: Shown })
	local f, tpl = folder, template
	if f == nil or tpl == nil then
		return
	end
	for id in marks do
		if shown[id] == nil then
			remove(id)
		end
	end
	for id, b in shown do
		if marks[id] == nil then
			local minV, maxV = b.minV, b.maxV
			local c = (minV + maxV) / 2
			local sun = tpl:Clone()
			sun.Name = "DailySun_" .. id
			for _, d in sun:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
				end
			end
			local center = Vector3.new(c.X, maxV.Y + LIFT, c.Z)
			sun:PivotTo(CFrame.new(center))
			sun.Parent = f
			marks[id] = {
				sun = sun,
				glow = makeGlow(minV, maxV, f),
				center = center,
				phase = (#id % 7) * 0.9, -- ダンジョンごとに揺れをずらす
			}
		end
	end
end

return DailyWorld
