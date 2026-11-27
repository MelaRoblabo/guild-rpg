--!strict
-- 初回の誘導（D-244 ①・D-124・D-162 ③）。初めての人にだけ「今やること」を1つずつ光らせ、指で示す。
--   段：wagon（馬車＝パーティの面を開く）→ go（パーティの面の Go）→ chests（帰還のあとの宝箱ボタン）
--       → openAll（宝箱の一覧の Open All）→ equip（明かす画面・結果の Equip）→ quests（右上の Quests。D-246 ②）。
--   済んだ段の数は SetGuideStep でサーバーに保存する（設定と一緒：D-117）。要約の guideStep で読む。
--   光るのは同時に1つだけ。ほかの所は暗くしない。光り方は琥珀の輪が約1秒で脈打つ形（見本：D-244）。

local TweenService = game:GetService("TweenService")

local Create = require("../ui/Create")
local Session = require("../Session")
local Signal = require("../ui/Signal")
local Tokens = require("../ui/Tokens")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local Guide = {}

Guide.STEPS = { "wagon", "go", "chests", "openAll", "equip", "quests" }
-- ログインボーナスのカレンダーを出してよくなる段（この段が済んだら出す。D-289）。
-- 誘導はまだ変わるので、出す時機はここ1か所で変える（nil にすると誘導を全部終えたら）
Guide.CALENDAR_AFTER = nil :: string?
Guide.changed = Signal.new() :: Signal.Signal<boolean>

local localDone = 0 -- サーバーへ送った分（要約が届くまでの間も先へ進めるため）

local function doneCount(): number
	local view = Session.view
	local saved = if view then view.guideStep or 0 else 0
	return math.max(saved, localDone)
end

-- 今光らせる段（全部済んでいれば nil）
function Guide.current(): string?
	return Guide.STEPS[doneCount() + 1]
end

-- ログインボーナスのカレンダーを出してよいか（D-289）
function Guide.calendarReady(): boolean
	local after = Guide.CALENDAR_AFTER
	local need = if after then table.find(Guide.STEPS, after) or #Guide.STEPS else #Guide.STEPS
	return doneCount() >= need
end

function Guide.is(key: string): boolean
	return Guide.current() == key
end

-- その段が済んだ。後の段が先に済んだときは前の段も済んだ扱い（マップから直接出発したときなど）
function Guide.done(key: string)
	local idx = table.find(Guide.STEPS, key)
	if idx == nil or idx <= doneCount() then
		return
	end
	localDone = idx
	Session.send({ type = "SetGuideStep", step = idx })
	Guide.changed:fire(true)
end

-- 出発したら Go までは済んだ扱い（どの画面から出発しても）
function Guide.mount()
	Session.changed:connect(function(view: any)
		if view and next(view.expeditions or {}) ~= nil then
			Guide.done("go")
		end
	end)
end

local Root = require("../ui/Root")

local function pulse(stroke: UIStroke)
	local info = TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(stroke, info, { Thickness = 7, Transparency = 0.15 }):Play()
end

-- target に光る輪と指を付ける／外す。radius は輪の角の丸み（ボタンの角に合わせる）。
-- above：指を上から下へ向けて出す（画面の下端のボタン用）
function Guide.mark(target: GuiObject?, on: boolean, radius: number?, above: boolean?)
	if target == nil then
		return
	end
	local glow = target:FindFirstChild("GuideGlow")
	local finger = target:FindFirstChild("GuideFinger")
	if not on then
		if glow then
			glow:Destroy()
		end
		if finger then
			finger:Destroy()
		end
		return
	end
	if glow then
		return
	end
	local ring: Frame = new("Frame", {
		Name = "GuideGlow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 14, 1, 14),
		BackgroundTransparency = 1,
		ZIndex = 0, -- ボタンの後ろ（上に重ねると押せなくなる）。一回り大きいので縁は見える
		[CHILDREN] = {
			new("UICorner", { CornerRadius = UDim.new(0, (radius or 18) + 7) }),
		},
		Parent = target,
	})
	local stroke: UIStroke = new("UIStroke", {
		Color = C.selAmber,
		Thickness = 4,
		Transparency = 0.35,
		Parent = ring,
	})
	pulse(stroke)
	-- 指（初回の誘導の間だけ。下から上を指す。画像がそろうまでは絵文字）
	local from = if above then UDim2.new(0.75, 0, 0, -6) else UDim2.new(0.75, 0, 1, 6)
	local to = if above then UDim2.new(0.75, 0, 0, 6) else UDim2.new(0.75, 0, 1, -6)
	local f: TextLabel = new("TextLabel", {
		Name = "GuideFinger",
		Text = if above then "👇" else "👆",
		TextSize = 56,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, if above then 1 else 0),
		Position = from,
		Size = UDim2.fromOffset(64, 64),
		ZIndex = 61,
		Parent = target,
	})
	TweenService:Create(f, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Position = to,
	}):Play()
end

-- 並べる仕組み（UIListLayout）の中のボタン用：輪と指を overlay（並べない面）に置き、target の位置に合わせる。
-- 呼ぶたびに位置を合わせ直す（target の大きさが語で変わるため）。輪は overlay の中で target より奥の ZIndex に置く
local overlays: { [GuiObject]: { ring: Frame, finger: TextLabel } } = {}

function Guide.markOver(target: GuiObject?, on: boolean, radius: number?, overlay: GuiObject, zIndex: number)
	if target == nil then
		return
	end
	local o = overlays[target]
	if not on then
		if o then
			o.ring:Destroy()
			o.finger:Destroy()
			overlays[target] = nil
		end
		return
	end
	if o == nil then
		local ring: Frame = new("Frame", {
			Name = "GuideGlow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = zIndex,
			[CHILDREN] = {
				new("UICorner", { CornerRadius = UDim.new(0, (radius or 18) + 7) }),
			},
			Parent = overlay,
		})
		local stroke: UIStroke = new("UIStroke", {
			Color = C.selAmber,
			Thickness = 4,
			Transparency = 0.35,
			Parent = ring,
		})
		pulse(stroke)
		local f: TextLabel = new("TextLabel", {
			Name = "GuideFinger",
			Text = "👆",
			TextSize = 56,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(64, 64),
			ZIndex = 61,
			Parent = overlay,
		})
		o = { ring = ring, finger = f }
		overlays[target] = o
	end
	assert(o, "輪を作れなかった")
	-- 画面の座標から overlay の中の座標へ（キャンバスは UIScale で縮む）
	local scale = math.max(Root.frame.scale, 0.01)
	local rel = (target.AbsolutePosition - overlay.AbsolutePosition) / scale
	local size = target.AbsoluteSize / scale
	o.ring.Position = UDim2.fromOffset(rel.X + size.X / 2, rel.Y + size.Y / 2)
	o.ring.Size = UDim2.fromOffset(size.X + 14, size.Y + 14)
	-- 指は下から上を指す（揺れは位置を直接動かすので、輪の下の端に置いて小さく上下させる）
	local bob = (math.sin(os.clock() * 7) + 1) * 6
	o.finger.Position = UDim2.fromOffset(rel.X + size.X * 0.75, rel.Y + size.Y + 6 - bob)
end

return Guide
