--!strict
-- S-21c 面接（D-220）。全自動で、能力の棒が上から順に素早く決まる。プレイヤーは介入しない（Stop なし）。
-- 良い値はその行が光り、最大値は金の光（仮の短い動き。本番の演出は M8-FX）。触ると速まる。
-- 終わったら S-21d（引き直し）へ進む。引き直しのあとも、ここを通って新しい値を見せる。

local TweenService = game:GetService("TweenService")

local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local HireCommon = require("./HireCommon")
local Nav = require("../../ui/Nav")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")

local C = Tokens.color
local new = Create.new

local STEP = 0.25 -- 1行あたりの秒（D-220 の S-21c。本番の値は M8-FX で決めてマスターデータへ）

local function build(_params: any?, api: Nav.Api): Nav.Built
	local view = Session.view
	local h = view and view.hireSession
	local frame = HireCommon.scene("HireInterview")
	if not (h and h.pickedIndex and h.currentRoll) then
		task.defer(api.close)
		return { frame = frame, scrim = 1 }
	end
	local candidate = h.candidates[h.pickedIndex]
	HireCommon.portrait(frame, candidate)
	local panel = HireCommon.statPanel(frame, candidate, h.currentRoll, nil)
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
		end,
	}
end

Nav.register("HireInterview", build)

return {}
