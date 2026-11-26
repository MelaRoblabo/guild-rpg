--!strict
-- 3D マップのカメラ（D-270 ④⑤）。
--   1本指／右ドラッグ＝注目点の周りを回る、2本指／左ドラッグ＝地図の上を滑らせる、ピンチ／ホイール＝寄る。地図の外へは出ない。
--   右ドラッグで向きを変えるのは Shift+P のフリーカメラに合わせた（D-270 ④）。
--   MapCamera.focus(pos) でその物へ移り、移ったあとは俯瞰でゆっくり旋回する。自分で動かしたら旋回をやめる。
--   タップ（動かさずに離した）は onTap に画面の位置を渡す（3D の物を選ぶのは World3D）。
--   キーボード（PC。Shift+P のフリーカメラと同じ感じ）：W・A・S・D＝地図の上を前後左右に動く、E・Q＝上げる・下げる、
--   Shift を押している間は速く。マップを見ているとき（keysAllowed が true）だけ効く（Q・E はほかの画面ではタブ：D-139）。
--   ゲームパッド（D-273）：左スティック＝地図の上を動く、右スティック＝回る、R2・L2＝寄る・離れる（倒した量・押し込んだ量で速さ）。
--   左スティックはマップが一番上のとき（mapOnTop）だけ。面を開いているときは面の操作に使うので、右スティックと R2・L2 だけ効く。
--   画面の部品の上で始まった入力（gameProcessed）はカメラに使わない。

local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local MapCamera = {}

-- 画面の動きの値（ゲームの数値ではない）
local PITCH_MIN, PITCH_MAX = math.rad(22), math.rad(85)
local DIST_MIN, DIST_MAX = 18, 170
local FOCUS_DIST = 26 -- 物へ寄ったときの距離
local FOCUS_PITCH = math.rad(50)
local FOCUS_TIME = 0.8 -- 物へ移る秒
local ORBIT_SPEED = 0.04 -- 旋回の速さ（ラジアン／秒）
local ROTATE_SPEED = 0.006
local KEY_PAN = 0.6 -- W・A・S・D で1秒に動く量（今の距離に対する割合）
local KEY_ZOOM = 1.6 -- E・Q で1秒に変わる距離の倍率
local KEY_FAST = 2.5 -- Shift を押している間の速さの倍率
local PAD_DEAD = 0.18 -- スティックの遊び（これより小さい傾きは無視）
local PAD_ROTATE = 1.6 -- 右スティックを倒しきったときの回る速さ（ラジアン／秒）
local PAD_ZOOM = 1.5 -- R2・L2 を押しきったときの寄る速さ（E・Q に対する倍率）
local TAP_MOVE = 10 -- これより動いたらタップではない（画素）
local TAP_TIME = 0.45

local focus = Vector3.zero
local yaw, pitch, dist = math.rad(200), math.rad(58), 130
local bounds = { minX = -90, maxX = 90, minZ = -90, maxZ = 90, y = 5 }
local orbiting = false
local tween: { t: number, from: { f: Vector3, d: number, p: number }, to: { f: Vector3, d: number, p: number } }? = nil
local enabled = false
local follow: (() -> Vector3?)? = nil -- 寄った物が動くとき（馬車）、その位置を毎フレーム返す

MapCamera.onTap = nil :: ((Vector2) -> ())?
MapCamera.keysAllowed = nil :: (() -> boolean)? -- キーボードで動かしてよいか（面を開いていないときなど）
MapCamera.mapOnTop = nil :: (() -> boolean)? -- マップが一番上か（ゲームパッドの左スティック・照準・A：D-273 ⑥）

-- 最後に触ったのがゲームパッドか（照準を出すかどうか：D-273 ④）
local padMode = false
local function isPad(t: Enum.UserInputType): boolean
	return t.Name:sub(1, 7) == "Gamepad"
end
UserInputService.LastInputTypeChanged:Connect(function(t)
	if isPad(t) then
		padMode = true
	elseif t ~= Enum.UserInputType.Focus and t ~= Enum.UserInputType.None then
		padMode = false
	end
end)
padMode = isPad(UserInputService:GetLastInputType())

function MapCamera.padMode(): boolean
	return padMode
end

-- マップが一番上で、画面の部品がゲームパッドで選ばれていないとき（左スティック・照準・A をマップに使う）
function MapCamera.mapAimAllowed(): boolean
	local top = MapCamera.mapOnTop == nil or (MapCamera.mapOnTop :: () -> boolean)()
	return enabled and top and GuiService.SelectedObject == nil
end

local function clampFocus(p: Vector3): Vector3
	return Vector3.new(math.clamp(p.X, bounds.minX, bounds.maxX), bounds.y, math.clamp(p.Z, bounds.minZ, bounds.maxZ))
end

local function stopAuto()
	orbiting = false
	tween = nil
	follow = nil
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

-- その物へ移って旋回する。getPos を渡すと、移ったあともその位置を追う（動く馬車）
function MapCamera.focus(pos: Vector3, getPos: (() -> Vector3?)?)
	tween = {
		t = 0,
		from = { f = focus, d = dist, p = pitch },
		to = { f = clampFocus(pos), d = FOCUS_DIST, p = FOCUS_PITCH },
	}
	orbiting = false
	follow = getPos
end

-- 今の注目点とカメラまでの距離（被写界深度のピント合わせに使う）
function MapCamera.state(): (Vector3, number)
	return focus, dist
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
local lastPos: Vector2? = nil

-- ドラッグの間はマウスをその場に固定する（Roblox のカメラの右ドラッグと同じ）。
-- 固定しないと動いた量（Delta）が 0 のまま届くことがあり、ドラッグしてもカメラが動かなかった
local function endDrag()
	mouseMode = nil
	downAt = nil
	lastPos = nil
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

UserInputService.InputBegan:Connect(function(input, gp)
	if not enabled or gp then
		return
	end
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 then
		mouseMode = if t == Enum.UserInputType.MouseButton2 then "rotate" else "pan"
		downAt = Vector2.new(input.Position.X, input.Position.Y)
		downTime = os.clock()
		moved = 0
		lastPos = downAt
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
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
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if d.Magnitude == 0 and lastPos then
			d = pos - lastPos -- 固定できなかったときは位置の差で動かす
		end
		lastPos = pos
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
		endDrag()
		if wasTap and at and MapCamera.onTap then
			MapCamera.onTap(at)
		end
	end
end)

-- ウィンドウの外でボタンを離したとき
UserInputService.WindowFocusReleased:Connect(function()
	if mouseMode then
		endDrag()
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
	-- 動く物を追うときは、行き先をその物の今の位置にする
	local target = if follow then follow() else nil
	if tw then
		tw.t += dt
		if target then
			tw.to.f = clampFocus(target)
		end
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
		if target then
			focus = clampFocus(target)
		elseif follow then
			follow = nil -- 追っていた物がなくなった（ギルド・ダンジョンに入った）
		end
	end
	-- キーボード（W・A・S・D・E・Q、Shift で速く）
	local allowed = MapCamera.keysAllowed == nil or (MapCamera.keysAllowed :: () -> boolean)()
	if allowed and UserInputService:GetFocusedTextBox() == nil then
		local function down(k: Enum.KeyCode): number
			return if UserInputService:IsKeyDown(k) then 1 else 0
		end
		local fwd = down(Enum.KeyCode.W) - down(Enum.KeyCode.S)
		local side = down(Enum.KeyCode.D) - down(Enum.KeyCode.A)
		local up = down(Enum.KeyCode.E) - down(Enum.KeyCode.Q)
		if fwd ~= 0 or side ~= 0 or up ~= 0 then
			stopAuto()
			local fast = if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
					or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
				then KEY_FAST
				else 1
			local right = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
			local forward = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
			local step = dist * KEY_PAN * fast * dt
			focus = clampFocus(focus + forward * fwd * step + right * side * step)
			if up ~= 0 then
				zoom(KEY_ZOOM ^ (up * fast * dt))
			end
		end
	end
	-- ゲームパッド（D-273）
	if allowed and UserInputService.GamepadEnabled then
		local ls, rs, r2, l2 = Vector2.zero, Vector2.zero, 0, 0
		for _, io in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			local k = io.KeyCode
			if k == Enum.KeyCode.Thumbstick1 then
				ls = Vector2.new(io.Position.X, io.Position.Y)
			elseif k == Enum.KeyCode.Thumbstick2 then
				rs = Vector2.new(io.Position.X, io.Position.Y)
			elseif k == Enum.KeyCode.ButtonR2 then
				r2 = io.Position.Z
			elseif k == Enum.KeyCode.ButtonL2 then
				l2 = io.Position.Z
			end
		end
		local function dead(v: Vector2): Vector2
			local m = v.Magnitude
			if m < PAD_DEAD then
				return Vector2.zero
			end
			return v.Unit * math.min(1, (m - PAD_DEAD) / (1 - PAD_DEAD))
		end
		ls = if MapCamera.mapAimAllowed() then dead(ls) else Vector2.zero
		rs = dead(rs)
		local zin = (if r2 > PAD_DEAD then r2 else 0) - (if l2 > PAD_DEAD then l2 else 0)
		if ls ~= Vector2.zero or rs ~= Vector2.zero or zin ~= 0 then
			stopAuto()
			local right = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
			local forward = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
			local step = dist * KEY_PAN * dt
			focus = clampFocus(focus + forward * ls.Y * step + right * ls.X * step)
			yaw -= rs.X * PAD_ROTATE * dt
			pitch = math.clamp(pitch - rs.Y * PAD_ROTATE * 0.6 * dt, PITCH_MIN, PITCH_MAX)
			if zin ~= 0 then
				zoom(KEY_ZOOM ^ (-zin * PAD_ZOOM * dt))
			end
		end
	end
	cam.CameraType = Enum.CameraType.Scriptable
	local offset = Vector3.new(math.cos(pitch) * math.sin(yaw), math.sin(pitch), math.cos(pitch) * math.cos(yaw)) * dist
	cam.CFrame = CFrame.lookAt(focus + offset, focus)
end)

return MapCamera
