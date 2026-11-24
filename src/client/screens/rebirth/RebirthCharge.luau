--!strict
-- S-43b 加算分のチャージ（D-224）。雇用の面接 S-21c と同じ形：全自動、ボタンなし（触ると速まる）。
--   - 関係の薄い能力 → HP → 攻撃に使う能力の順に、加算分の棒が伸びて止まる（最後が山場）。
--   - 上限の statGoodRatio 以上は行が光り、rebirthGreatRatio 以上は金の光（仮の短い動き。本番は M8-FX）。
--   - 終わったら S-43c（比較・引き直し）へ。引き直しのあとも、ここを通って新しい値を見せる。

local TweenService = game:GetService("TweenService")

local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Nav = require("../../ui/Nav")
local RebirthCommon = require("./RebirthCommon")
local Screen = require("../Screen")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")

local C = Tokens.color
local new = Create.new

local STEP = 0.3 -- 1行あたりの秒（仮。本番の値は M8-FX で決めてマスターデータへ）

local function build(_params: any?, api: Nav.Api): Nav.Built
	local view = Session.view
	local r = view and view.rebirthSession
	local frame = Screen.scene("RebirthCharge")
	if not r then
		task.defer(api.close)
		return { frame = frame, scrim = 1 }
	end
	local adv = view.adventurers[r.adventurerUid]
	RebirthCommon.portrait(frame, { kind = if adv.uniqueId then "unique" else "general" })
	local panel = RebirthCommon.statPanel(frame, adv, r, r.currentBonus, nil)
	local close = Screen.closeTopRight(frame, api.close)
	close.BackgroundTransparency = 0.5 -- 進行中は薄く（介入しない）

	-- 加算分を空にしてから、決まる順に伸ばす
	for key, row in panel.rows do
		row.bonusFill:SetAttribute("Target", row.bonusFill.Size.X.Scale)
		row.bonusFill.Size = UDim2.new(0, 0, 1, -4)
		row.number.Text = tostring(r.inherited[key])
	end
	local speed = 1
	local tap: TextButton = new("TextButton", {
		Name = "SpeedUp",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Parent = frame,
	})
	tap.Activated:Connect(function()
		speed = 4
	end)
	local alive = true
	task.spawn(function()
		task.wait(0.3)
		for _, key in RebirthCommon.chargeOrder(adv.jobId) do
			if not alive then
				return
			end
			local row = panel.rows[key]
			local target = row.bonusFill:GetAttribute("Target") :: number
			TweenService:Create(
				row.bonusFill,
				TweenInfo.new(STEP / speed, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = UDim2.new(target, 0, 1, -4) }
			):Play()
			task.wait(STEP / speed)
			row.number.Text = tostring(r.inherited[key] + r.currentBonus[key])
			local q = RebirthCommon.quality(r.currentBonus[key], r.bonusMax[key])
			if q then
				row.frame.BackgroundColor3 = if q == "great" then C.rewardGlow else C.ch52
				Components.stroke(if q == "great" then C.ctaGoldLow else C.bronzeHi, 3).Parent = row.frame
				task.wait((if q == "great" then 0.5 else 0.2) / speed)
			end
		end
		task.wait(0.4 / speed)
		if alive then
			api.replace("RebirthCompare")
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

Nav.register("RebirthCharge", build)

return {}
