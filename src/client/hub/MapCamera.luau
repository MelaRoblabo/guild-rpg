--!strict
-- 3D マップのカメラ（D-270 ④⑤）。
--   1本指／左ドラッグ＝注目点の周りを回る、2本指／右ドラッグ＝地図の上を滑らせる、ピンチ／ホイール＝寄る。地図の外へは出ない。
--   MapCamera.focus(pos) でその物へ移り、移ったあとは俯瞰でゆっくり旋回する。自分で動かしたら旋回をやめる。
--   タップ（動かさずに離した）は onTap に画面の位置を渡す（3D の物を選ぶのは World3D）。
--   画面の部品の上で始まった入力（gameProcessed）はカメラに使わない。

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local MapCamera = {}

-- 画面の動きの値（ゲームの数値ではない）
local PITCH_MIN, PITCH_MAX = math.rad(22), math.rad(85)
local DIST_MIN, DIST_MAX = 18, 170
local FOCUS_DIST = 42 -- 物へ寄ったときの距離
local FOCUS_PITCH = math.rad(50)
local FOCUS_TIME = 0.8 -- 物へ移る秒
local ORBIT_SPEED = 0.12 -- 旋回の速さ（ラジアン／秒）
local ROTATE_SPEED = 0.006
local TAP_MOVE = 10 -- これより動いたらタップではない（画素）
local TAP_TIME = 0.45

local focus = Vector3.zero
local yaw, pitch, dist = math.rad(200), math.rad(58), 130
local bounds = { minX = -90, maxX = 90, minZ = -90, maxZ = 90, y = 5 }
local orbiting = false
local tween: { t: number, from: { f: Vector3, d: number, p: number }, to: { f: Vector3, d: number, p: number } }? = nil
local enabled = false

MapCamera.onTap = nil :: ((Vector2) -> ())?

local function clampFocus(p: Vector3): Vector3
	return Vector3.new(math.clamp(p.X, bounds.minX, bounds.maxX), bounds.y, math.clamp(p.Z, bounds.minZ, bounds.maxZ))
end

local function stopAuto()
	orbiting = false
	tween = nil
end

-- 地図の範囲（MAP の Part）を渡す
function MapCamera.setBounds(mapPart: BasePart)
	local half = mapPart.Size / 2
	local c = mapPart.Position
	bounds = {
		minX = c.X - half.X + 4,
		maxX = c.X + half.X - 4,
		minZ = c.Z - half.Z + 4,
		maxZ = c.Z + half.Z - 4,
		y = c.Y + half.Y,
	}
	focus = Vector3.new(c.X, bounds.y, c.Z)
end

-- その物へ移って旋回する
function MapCamera.focus(pos: Vector3)
	tween = {
		t = 0,
		from = { f = focus, d = dist, p = pitch },
		to = { f = clampFocus(pos), d = FOCUS_DIST, p = FOCUS_PITCH },
	}
	orbiting = false
end

function MapCamera.enable()
	enabled = true
end

-- 地図の上を滑らせる（画面の動きを地面の向きに直す）
local function pan(delta: Vector2)
	local right = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
	local forward = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local k = dist * 0.0028
	focus = clampFocus(focus - right * delta.X * k + forward * delta.Y * k)
end

local function rotate(delta: Vector2)
	yaw -= delta.X * ROTATE_SPEED
	pitch = math.clamp(pitch + delta.Y * ROTATE_SPEED * 0.8, PITCH_MIN, PITCH_MAX)
end

local function zoom(factor: number)
	dist = math.clamp(dist * factor, DIST_MIN, DIST_MAX)
end

-- マウス
local mouseMode: string? = nil
local downAt: Vector2? = nil
local downTime = 0
local moved = 0

UserInputService.InputBegan:Connect(function(input, gp)
	if not enabled or gp then
		return
	end
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 then
		mouseMode = if t == Enum.UserInputType.MouseButton1 then "rotate" else "pan"
		downAt = Vector2.new(input.Position.X, input.Position.Y)
		downTime = os.clock()
		moved = 0
	end
end)

UserInputService.InputChanged:Connect(function(input, gp)
	if not enabled then
		return
	end
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseWheel and not gp then
		stopAuto()
		zoom(if input.Position.Z > 0 then 0.88 else 1.14)
	elseif t == Enum.UserInputType.MouseMovement and mouseMode then
		local d = Vector2.new(input.Delta.X, input.Delta.Y)
		moved += d.Magnitude
		if moved > TAP_MOVE then
			stopAuto()
			if mouseMode == "rotate" then
				rotate(d)
			else
				pan(d)
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local t = input.UserInputType
	if (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2) and mouseMode then
		local wasTap = t == Enum.UserInputType.MouseButton1 and moved <= TAP_MOVE and os.clock() - downTime <= TAP_TIME
		local at = downAt
		mouseMode = nil
		downAt = nil
		if wasTap and at and MapCamera.onTap then
			MapCamera.onTap(at)
		end
	end
end)

-- タッチ（1本＝回る、2本＝ピンチで寄る・滑らせる）
local touches: { [InputObject]: Vector2 } = {}
local touchStart: { at: Vector2, time: number, moved: number }? = nil
local lastPinch: number? = nil
local lastMid: Vector2? = nil

local function touchList(): { Vector2 }
	local out = {}
	for _, p in touches do
		table.insert(out, p)
	end
	return out
end

UserInputService.TouchStarted:Connect(function(input, gp)
	if not enabled or gp then
		return
	end
	local p = Vector2.new(input.Position.X, input.Position.Y)
	touches[input] = p
	local n = 0
	for _ in touches do
		n += 1
	end
	if n == 1 then
		touchStart = { at = p, time = os.clock(), moved = 0 }
	else
		touchStart = nil
		lastPinch, lastMid = nil, nil
	end
end)

UserInputService.TouchMoved:Connect(function(input)
	local prev = touches[input]
	if prev == nil then
		return
	end
	local p = Vector2.new(input.Position.X, input.Position.Y)
	touches[input] = p
	local list = touchList()
	if #list == 1 then
		local d = p - prev
		if touchStart then
			touchStart.moved += d.Magnitude
		end
		if touchStart == nil or touchStart.moved > TAP_MOVE then
			stopAuto()
			rotate(d)
		end
	elseif #list >= 2 then
		stopAuto()
		local a, b = list[1], list[2]
		local gap = (a - b).Magnitude
		local mid = (a + b) / 2
		if lastPinch and gap > 0 then
			zoom(lastPinch / gap)
		end
		if lastMid then
			pan(mid - lastMid)
		end
		lastPinch, lastMid = gap, mid
	end
end)

UserInputService.TouchEnded:Connect(function(input)
	if touches[input] == nil then
		return
	end
	touches[input] = nil
	local st = touchStart
	local empty = next(touches) == nil
	if empty then
		lastPinch, lastMid = nil, nil
		touchStart = nil
		if st and st.moved <= TAP_MOVE and os.clock() - st.time <= TAP_TIME and MapCamera.onTap then
			MapCamera.onTap(st.at)
		end
	end
end)

local function ease(x: number): number
	return 1 - (1 - x) ^ 3
end

RunService:BindToRenderStep("GuildMapCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not enabled then
		return
	end
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return
	end
	local tw = tween
	if tw then
		tw.t += dt
		local a = ease(math.clamp(tw.t / FOCUS_TIME, 0, 1))
		focus = tw.from.f:Lerp(tw.to.f, a)
		dist = tw.from.d + (tw.to.d - tw.from.d) * a
		pitch = tw.from.p + (tw.to.p - tw.from.p) * a
		if a >= 1 then
			tween = nil
			orbiting = true
		end
	elseif orbiting then
		yaw += dt * ORBIT_SPEED
	end
	cam.CameraType = Enum.CameraType.Scriptable
	local offset = Vector3.new(math.cos(pitch) * math.sin(yaw), math.sin(pitch), math.cos(pitch) * math.cos(yaw)) * dist
	cam.CFrame = CFrame.lookAt(focus + offset, focus)
end)

return MapCamera
