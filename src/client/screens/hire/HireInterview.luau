--!strict
-- S-21c 面接（D-220）。全自動で、能力の棒が上から順に素早く決まる。プレイヤーは介入しない（Stop なし）。
-- 良い値はその行が光り、最大値は金の光（仮の短い動き。本番の演出は M8-FX）。触ると速まる。
-- 最後に Total（HP を除く4項目の合計：Q-006）がカウントアップし、hireTotalGreat・hireTotalAmazing 以上なら
-- 特別な演出（ハンコ・光の輪・光の筋・金の行が脈打つ。Amazing はさらに画面の閃光と大きなハンコ：D-283）。
-- 終わったら S-21d（引き直し）へ進む。引き直しのあとも、ここを通って新しい値を見せる。

local TweenService = game:GetService("TweenService")

local Hiring = require("@game/ReplicatedStorage/Core/Hiring")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local HireCommon = require("./HireCommon")
local Motion = require("../../ui/Motion")
local Nav = require("../../ui/Nav")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local Words = require("../../ui/Words")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local STEP = 0.25 -- 1行あたりの秒（D-220 の S-21c。本番の値は M8-FX で決めてマスターデータへ）
-- Total の段ごとの演出の強さ（見た目の大きさと秒。ゲームの数値ではない）
type Fx = { stamp: number, rays: number, reach: number, hold: number, color: Color3, flash: boolean }
local FX: { [string]: Fx } = {
	great = { stamp = 260, rays = 12, reach = 150, hold = 1.2, color = C.ctaGoldLow, flash = false },
	amazing = { stamp = 360, rays = 24, reach = 260, hold = 1.8, color = C.rewardGlow, flash = true },
}

-- 広がって消える光の輪（Motion の層に描く）
local function ring(at: Vector2, reach: number, color: Color3, delay: number)
	local r: Frame = new("Frame", {
		Name = "TotalRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(at.X, at.Y),
		Size = UDim2.fromOffset(40, 40),
		BackgroundTransparency = 1,
		ZIndex = 905,
		[CHILDREN] = { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) },
		Parent = Motion.layer(),
	})
	local stroke = Components.stroke(color, 6)
	stroke.Parent = r
	local info = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay)
	TweenService:Create(r, info, { Size = UDim2.fromOffset(reach * 2, reach * 2) }):Play()
	local fade = TweenService:Create(stroke, info, { Transparency = 1 })
	fade.Completed:Once(function()
		r:Destroy()
	end)
	fade:Play()
end

-- 数字から外へ飛び散る光の筋
local function rays(at: Vector2, count: number, reach: number, color: Color3)
	for i = 1, count do
		local a = (i / count) * math.pi * 2
		local dir = Vector2.new(math.cos(a), math.sin(a))
		local p0 = at + dir * 30
		local p1 = at + dir * reach
		local ray: Frame = new("Frame", {
			Name = "TotalRay",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(p0.X, p0.Y),
			Size = UDim2.fromOffset(8, 30),
			Rotation = math.deg(a) + 90,
			BackgroundColor3 = color,
			ZIndex = 906,
			[CHILDREN] = { Components.corner(4) },
			Parent = Motion.layer(),
		})
		local tw = TweenService:Create(
			ray,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(p1.X, p1.Y), BackgroundTransparency = 1, Size = UDim2.fromOffset(4, 18) }
		)
		tw.Completed:Once(function()
			ray:Destroy()
		end)
		tw:Play()
	end
end

-- 画面の閃光（Amazing だけ。「点滅を減らす」なら出さない：D-145）
local function flash()
	local f: Frame = new("Frame", {
		Name = "TotalFlash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.rewardGlow,
		BackgroundTransparency = 0.35,
		ZIndex = 904,
		Parent = Motion.layer(),
	})
	local tw = TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
	tw.Completed:Once(function()
		f:Destroy()
	end)
	tw:Play()
end

local function build(_params: any?, api: Nav.Api): Nav.Built
	local view = Session.view
	local h = view and view.hireSession
	local frame = HireCommon.scene("HireInterview")
	if not (h and h.pickedIndex and h.currentRoll) then
		task.defer(api.close)
		return { frame = frame, scrim = 1 }
	end
	local candidate = h.candidates[h.pickedIndex]
	local portrait = HireCommon.portrait(frame, candidate)
	local panel = HireCommon.statPanel(frame, candidate, h.currentRoll, nil, true) -- Total は最後に決める
	-- 進行中は × を薄くする（介入しない：D-220）
	local close = HireCommon.closeTopRight(frame, api.close)
	close.BackgroundTransparency = 0.5

	-- 棒を空にしてから、上から順に伸ばす
	local fills: { [string]: Frame } = {}
	local nums: { [string]: TextLabel } = {}
	for key, row in panel.rows do
		local bar = row:FindFirstChild("Bar") :: Frame
		local fill = bar:FindFirstChild("Fill") :: Frame
		fills[key] = fill
		for _, d in bar:GetChildren() do
			if d:IsA("TextLabel") then
				nums[key] = d
				d.Text = "?"
			end
		end
		fill:SetAttribute("Target", fill.Size.X.Scale)
		fill.Size = UDim2.new(0, 0, 1, -4)
	end
	local speed = 1
	local tap: TextButton = new("TextButton", {
		Name = "SpeedUp",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Parent = frame,
	})
	tap.Activated:Connect(function()
		speed = 4 -- 触ると速まる
	end)
	local alive = true
	local stopPulse: (() -> ())? = nil
	-- Total の段の演出（共通の動きの部品＋光の輪・筋・閃光：D-283・D-269 ⑤）
	local function celebrate(tier: string)
		local fx = FX[tier]
		local reduced = Motion.reduced()
		local at = Motion.center(panel.totalValue)
		if fx.flash and not reduced then
			flash()
		end
		ring(at, fx.reach, fx.color, 0)
		if tier == "amazing" then
			ring(at, fx.reach * 1.4, C.ctaGold, 0.15)
		end
		rays(at, if reduced then math.floor(fx.rays / 2) else fx.rays, fx.reach, fx.color)
		Motion.bump(panel.total, if tier == "amazing" then 0.25 else 0.15)
		stopPulse = Motion.pulse(panel.total)
		local word = string.upper(if tier == "amazing" then Words.amazing else Words.great) .. "!"
		Motion.stamp(portrait, word, fx.color, fx.stamp)
	end
	task.spawn(function()
		task.wait(0.3)
		for _, s in HireCommon.STATS do
			if not alive then
				return
			end
			local key = s.key
			local fill = fills[key]
			local target = fill:GetAttribute("Target") :: number
			local t = TweenService:Create(
				fill,
				TweenInfo.new(STEP / speed, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = UDim2.new(target, -4, 1, -4) }
			)
			t:Play()
			task.wait(STEP / speed)
			nums[key].Text = tostring(h.currentRoll[key])
			local q = HireCommon.quality(key, h.currentRoll[key])
			if q then
				local row = panel.rows[key]
				row.BackgroundColor3 = if q == "max" then C.rewardGlow else C.ch52
				Components.stroke(if q == "max" then C.ctaGoldLow else C.bronzeHi, 3).Parent = row
				task.wait((if q == "max" then 0.5 else 0.2) / speed)
			end
		end
		-- Total：カウントアップして段を見せる（D-283）
		task.wait(0.25 / speed)
		if not alive then
			return
		end
		local total = Hiring.total(h.currentRoll)
		Motion.countUp(panel.totalValue, 0, total, { float = false })
		task.wait(Motion.T.count / speed)
		if not alive then
			return
		end
		HireCommon.paintTotal(panel.total, total)
		local tier = HireCommon.totalTier(total)
		if tier then
			celebrate(tier)
			task.wait(FX[tier].hold / speed)
		end
		task.wait(0.4 / speed)
		if alive then
			api.replace("HireReroll")
		end
	end)
	return {
		frame = frame,
		scrim = 1,
		destroy = function()
			alive = false
			if stopPulse then
				stopPulse()
			end
		end,
	}
end

Nav.register("HireInterview", build)

return {}
