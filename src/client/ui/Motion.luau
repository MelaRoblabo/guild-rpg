--!strict
-- 共通の動きの部品（D-269 ⑤、Guild UI「動きの部品」）。画面ごとに作り分けない。
--   Fly          物のアイコンが弧を描いて A から B へ飛び、着いた所が小さく弾む
--   CountUp      数字がカウントアップし、「+N」が浮かんで消える
--   Pulse        押せる・落とせる物がゆっくり脈打つ
--   Stamp        ハンコを押す（Hired・Closed など）
--   ReasonBubble 押せない理由の吹き出し（2秒）。操作を止めるときは中央に出すアラート（D-265 ②）
-- 1つの動きは 0.3〜0.6 秒。続けて操作したら残りの動きは早送りする（D-269 ⑤）。
-- 「点滅を減らす」がオンなら、飛ぶ・弾むは短く弱くする（D-145）。
-- M8-FX の演出エンジン（D-147）とは別の、UI の小さな動き。

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Game = require("@game/ReplicatedStorage/Core/Game")
local Components = require("./Components")
local Create = require("./Create")
local Root = require("./Root")
local Session = require("../Session")
local Tokens = require("./Tokens")
local master = require("../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local Motion = {}

-- 長さ（秒）。D-269 ⑤：1つ 0.3〜0.6 秒
Motion.T = { fly = 0.55, bump = 0.3, count = 0.6, float = 0.9, stamp = 0.3, pulse = 0.6, bubble = 2 }

-- 進行中の動き（早送りで終わらせる）
local running: { [any]: () -> () } = {}

-- 「点滅を減らす」（D-145）
function Motion.reduced(): boolean
	local view = Session.view
	if view == nil then
		return false
	end
	local ok, prefs = pcall(Game.query.preferences, view, master)
	return ok and prefs ~= nil and prefs.lessFlashing == true
end

local function dur(t: number): number
	return if Motion.reduced() then t * 0.5 else t
end

-- 動きを描く層（Canvas のいちばん上。押せない）
local layer: Frame? = nil
function Motion.layer(): Frame
	if layer == nil or layer.Parent == nil then
		layer = new("Frame", {
			Name = "MotionLayer",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 900,
			Active = false,
			Parent = Root.canvas,
		})
	end
	return layer :: Frame
end

-- 画面の部品の中心を、Canvas の単位（基準の 1280×720）で
function Motion.center(g: GuiObject): Vector2
	local scale = Root.frame.scale
	if scale <= 0 then
		scale = 1
	end
	local origin = Root.canvas.AbsolutePosition
	return (g.AbsolutePosition + g.AbsoluteSize / 2 - origin) / scale
end

local function point(p: GuiObject | Vector2): Vector2
	if typeof(p) == "Vector2" then
		return p
	end
	return Motion.center(p :: GuiObject)
end

local function scaleOf(g: GuiObject): UIScale
	local s = g:FindFirstChild("MotionScale")
	if s and s:IsA("UIScale") then
		return s
	end
	return new("UIScale", { Name = "MotionScale", Parent = g })
end

-- 着いた所が小さく弾む
function Motion.bump(g: GuiObject, amount: number?)
	if g.Parent == nil then
		return
	end
	local s = scaleOf(g)
	local peak = 1 + (if Motion.reduced() then 0.06 else (amount or 0.15))
	local t = dur(Motion.T.bump) / 2
	local up =
		TweenService:Create(s, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = peak })
	up.Completed:Once(function()
		TweenService:Create(s, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 1 }):Play()
	end)
	up:Play()
end

export type FlyOpts = {
	from: GuiObject | Vector2,
	to: GuiObject | Vector2,
	visual: GuiObject?, -- 飛ばす物（なければ icon から作る）。層に移して、着いたら消す
	icon: string?, -- 「@キー」か記号
	size: number?, -- 飛ぶ物の大きさ（基準の単位）
	endSize: number?, -- 着く時の大きさ（既定は size の半分）
	duration: number?,
	delay: number?,
	arc: number?, -- 弧の高さ（基準の単位）
	keep: boolean?, -- 着いても消さない
	onArrive: (() -> ())?,
}

-- 物のアイコンが弧を描いて A から B へ飛ぶ。B が部品なら着いたときに弾む
function Motion.fly(o: FlyOpts)
	local a, b = point(o.from), point(o.to)
	local size = o.size or 72
	local endSize = o.endSize or size * 0.5
	local g: GuiObject
	if o.visual then
		g = o.visual
	else
		local t = Components.text({ text = o.icon or "•", size = math.floor(size * 0.8), color = C.inkLight })
		t.AutomaticSize = Enum.AutomaticSize.None
		g = t
	end
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Size = UDim2.fromOffset(size, size)
	g.Position = UDim2.fromOffset(a.X, a.Y)
	g.ZIndex = 901
	for _, d in g:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 902
		end
	end
	g.Parent = Motion.layer()
	local total = dur(o.duration or Motion.T.fly)
	local arc = o.arc or math.clamp((b - a).Magnitude * 0.25, 40, 200)
	local key = {}
	local elapsed = -(o.delay or 0)
	local conn: RBXScriptConnection
	local function finish()
		if running[key] == nil then
			return
		end
		running[key] = nil
		conn:Disconnect()
		g.Position = UDim2.fromOffset(b.X, b.Y)
		g.Size = UDim2.fromOffset(endSize, endSize)
		if not o.keep then
			g:Destroy()
		end
		if typeof(o.to) ~= "Vector2" then
			Motion.bump(o.to :: GuiObject)
		end
		if o.onArrive then
			task.spawn(o.onArrive)
		end
	end
	g.Visible = elapsed >= 0
	conn = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		if elapsed < 0 then
			return
		end
		g.Visible = true
		local t = math.clamp(elapsed / total, 0, 1)
		local e = TweenService:GetValue(t, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		local p = a:Lerp(b, e) - Vector2.new(0, math.sin(math.pi * e) * arc)
		local s = size + (endSize - size) * e
		g.Position = UDim2.fromOffset(p.X, p.Y)
		g.Size = UDim2.fromOffset(s, s)
		if t >= 1 then
			finish()
		end
	end)
	running[key] = finish
end

-- 浮かんで消える文字（「+4」など）
function Motion.floatText(at: GuiObject | Vector2, text: string, color: Color3?)
	local p = point(at)
	local t = Components.text({
		text = text,
		size = Tokens.text.title,
		color = color or C.numHi,
		font = Tokens.font.number,
		stroke = true,
	})
	t.AnchorPoint = Vector2.new(0.5, 1)
	t.Position = UDim2.fromOffset(p.X, p.Y)
	t.ZIndex = 903
	t.Parent = Motion.layer()
	local d = dur(Motion.T.float)
	local tw = TweenService:Create(
		t,
		TweenInfo.new(d, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(p.X, p.Y - 48), TextTransparency = 1 }
	)
	local stroke = t:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(d), { Transparency = 1 }):Play()
	end
	tw.Completed:Once(function()
		t:Destroy()
	end)
	tw:Play()
end

export type CountOpts = {
	prefix: string?,
	suffix: string?,
	duration: number?,
	float: boolean?,
	format: ((number) -> string)?,
}

-- 数字のカウントアップ。from と to が違えば「+N」を浮かべる
function Motion.countUp(label: TextLabel, from: number, to: number, o: CountOpts?)
	local opts: CountOpts = o or {}
	local fmt = opts.format or function(n: number): string
		return tostring(n)
	end
	local function show(n: number)
		label.Text = (opts.prefix or "") .. fmt(n) .. (opts.suffix or "")
	end
	if from == to then
		show(to)
		return
	end
	local total = dur(opts.duration or Motion.T.count)
	local key = {}
	local elapsed = 0
	local conn: RBXScriptConnection
	local function finish()
		if running[key] == nil then
			return
		end
		running[key] = nil
		conn:Disconnect()
		show(to)
		Motion.bump(label, 0.1)
	end
	conn = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local t = math.clamp(elapsed / total, 0, 1)
		show(math.floor(from + (to - from) * t + 0.5))
		if t >= 1 then
			finish()
		end
	end)
	running[key] = finish
	if opts.float ~= false then
		local diff = to - from
		Motion.floatText(label, (if diff > 0 then "+" else "") .. fmt(diff), if diff > 0 then C.up else C.warn)
	end
end

-- 押せる・落とせる物がゆっくり脈打つ。戻り値で止める。
-- 縁（UIStroke）があれば縁を琥珀にして太さを脈打たせる（並べた中で大きさを変えると隣を押し出すため）。
-- 縁がなければ大きさを少しだけ脈打たせる
function Motion.pulse(g: GuiObject): () -> ()
	local stroke = g:FindFirstChildOfClass("UIStroke")
	if stroke then
		local color, thick = stroke.Color, stroke.Thickness
		stroke.Color = C.selAmber
		local tw = TweenService:Create(
			stroke,
			TweenInfo.new(Motion.T.pulse, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Thickness = if Motion.reduced() then thick + 2 else thick + 4 }
		)
		tw:Play()
		return function()
			tw:Cancel()
			if stroke.Parent then
				stroke.Color = color
				stroke.Thickness = thick
			end
		end
	end
	local s = scaleOf(g)
	local peak = if Motion.reduced() then 1.03 else 1.07
	local tw = TweenService:Create(
		s,
		TweenInfo.new(Motion.T.pulse, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = peak }
	)
	tw:Play()
	return function()
		tw:Cancel()
		s.Scale = 1
	end
end

-- ハンコ（Hired・Closed など）。parent の中央に押す
function Motion.stamp(parent: GuiObject, text: string, color: Color3?, size: number?): Frame
	local sz = size or 320
	local col = color or C.warn
	local stamp: Frame = new("Frame", {
		Name = "Stamp",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(sz, sz),
		Rotation = -12,
		BackgroundTransparency = 1,
		ZIndex = 30,
		[CHILDREN] = {
			Components.corner(sz / 2),
			Components.stroke(col, math.max(4, math.floor(sz / 32))),
		},
		Parent = parent,
	})
	local word = Components.text({
		text = text,
		size = math.clamp(math.floor(sz / 8), 21, 40),
		color = col,
		font = Tokens.font.display,
	})
	word.AutomaticSize = Enum.AutomaticSize.None
	word.Size = UDim2.fromScale(1, 1)
	word.ZIndex = 31
	word.Parent = stamp
	local s = new("UIScale", { Scale = if Motion.reduced() then 1.3 else 2.2, Parent = stamp })
	TweenService
		:Create(s, TweenInfo.new(dur(Motion.T.stamp), Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	return stamp
end

-- 吹き出し（1行。12語まで：D-264 ③）
local function bubble(text: string, big: boolean): Frame
	local b: Frame = new("Frame", {
		Name = if big then "Alert" else "Reason",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(0, if big then 72 else 52),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ch75,
		ZIndex = 950,
		[CHILDREN] = {
			Components.corner(if big then 16 else 12),
			Components.stroke(C.ch16, if big then 3 else 2),
			Components.padding(0, 20, 0, 20),
		},
		Parent = Motion.layer(),
	})
	local t = Components.text({
		text = text,
		size = if big then Tokens.text.body else Tokens.text.label,
		color = C.inkDark,
	})
	t.AnchorPoint = Vector2.new(0, 0.5)
	t.Position = UDim2.fromScale(0, 0.5)
	t.ZIndex = 951
	t.Parent = b
	return b
end

local function fadeOut(b: Frame, after: number)
	task.delay(after, function()
		if b.Parent == nil then
			return
		end
		local d = 0.25
		TweenService:Create(b, TweenInfo.new(d), { BackgroundTransparency = 1 }):Play()
		for _, x in b:GetDescendants() do
			if x:IsA("TextLabel") then
				TweenService:Create(x, TweenInfo.new(d), { TextTransparency = 1 }):Play()
			elseif x:IsA("UIStroke") then
				TweenService:Create(x, TweenInfo.new(d), { Transparency = 1 }):Play()
			end
		end
		task.delay(d, function()
			b:Destroy()
		end)
	end)
end

local currentReason: Frame? = nil

-- 押せない理由の吹き出し：押した所の上に1行、2秒（D-264 ②）
function Motion.reason(anchor: GuiObject, text: string)
	if currentReason then
		currentReason:Destroy()
	end
	local b = bubble(text, false)
	currentReason = b
	local scale = math.max(Root.frame.scale, 0.01)
	local top = (anchor.AbsolutePosition - Root.canvas.AbsolutePosition) / scale
	local cx = top.X + anchor.AbsoluteSize.X / scale / 2
	local w = Root.canvas.AbsoluteSize.X / scale
	b.Position = UDim2.fromOffset(math.clamp(cx, 160, w - 160), math.max(top.Y - 10, Root.bandBottom() + 60))
	Motion.bump(b, 0.08)
	fadeOut(b, Motion.T.bubble)
end

-- 操作を止めるときのアラート：画面の中央に出す（D-265 ②「Can't add to a party on an adventure」）
function Motion.alert(text: string)
	if currentReason then
		currentReason:Destroy()
	end
	local b = bubble(text, true)
	currentReason = b
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.fromScale(0.5, 0.42)
	Motion.bump(b, 0.08)
	fadeOut(b, Motion.T.bubble)
end

-- 残りの動きを早送りで終わらせる
function Motion.finishAll()
	local list = {}
	for _, f in running do
		table.insert(list, f)
	end
	for _, f in list do
		f()
	end
end

-- 続けて操作したら残りは早送り（D-269 ⑤）
UserInputService.InputBegan:Connect(function(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		task.defer(Motion.finishAll)
	end
end)

return Motion
