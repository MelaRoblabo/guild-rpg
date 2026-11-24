--!strict
-- S-21e 採用（D-220・D-226 ③）。採用を表すスタンプを押す演出のあと、決まった能力と
-- パーティ編成（金。S-12 は M8-6）・メイン画面（茶）へのボタンを出す。「もう一度呼ぶ」は出さない。

local TweenService = game:GetService("TweenService")

local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local HireCommon = require("./HireCommon")
local Nav = require("../../ui/Nav")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")

local C = Tokens.color
local I = Components.icon
local new = Create.new
local CHILDREN = Create.Children

local function build(params: any?, api: Nav.Api): Nav.Built
	local view = Session.view
	local uid = params and (params :: any).uid
	local adv = view and uid and view.adventurers[uid]
	local frame = HireCommon.scene("HireDone")
	HireCommon.closeTopRight(frame, api.home)
	if not adv then
		return { frame = frame, scrim = 1 }
	end
	local candidate = {
		kind = if adv.uniqueId then "unique" else "general",
		name = adv.name,
		jobId = adv.jobId,
		giftIds = adv.giftIds,
	}
	local portrait = HireCommon.portrait(frame, candidate)
	local panel = HireCommon.statPanel(frame, candidate, adv.baseStats, nil)
	panel.frame.Visible = false

	-- 1拍目：スタンプ（仮の短い動き。本番の演出は M8-FX）
	local stamp: Frame = new("Frame", {
		Name = "Stamp",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(320, 320),
		Rotation = -12,
		BackgroundTransparency = 1,
		ZIndex = 30,
		[CHILDREN] = {
			Components.corner(160),
			Components.stroke(C.warn, 10),
		},
		Parent = portrait,
	})
	local word = Components.text({ text = "HIRED", size = 40, color = C.warn, font = Tokens.font.display })
	word.AutomaticSize = Enum.AutomaticSize.None
	word.Size = UDim2.fromScale(1, 1)
	word.ZIndex = 31
	word.Parent = stamp
	local scale = new("UIScale", { Scale = 2.2, Parent = stamp })
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()

	-- 2拍目：決まった能力と行き先のボタン
	local actions = HireCommon.actionRow(frame)
	actions.Visible = false
	local home = Components.button({
		kind = "brown",
		width = 120,
		height = 66,
		icon = I.home,
		name = "Home",
		glyph = "X",
		onClick = api.home,
	})
	home.LayoutOrder = 1
	home.Parent = actions
	local party = Components.button({
		kind = "gold",
		width = 200,
		icon = I.party,
		name = "Party",
		glyph = "A",
		onClick = function()
			-- パーティ編成（S-12）は M8-6。それまではメイン画面へ戻る
			api.home()
		end,
	})
	party.LayoutOrder = 2
	party.Parent = actions
	task.delay(0.9, function()
		if frame.Parent then
			TweenService:Create(stamp, TweenInfo.new(0.3), { Size = UDim2.fromOffset(110, 110) }):Play()
			stamp.Position = UDim2.new(1, -70, 1, -70)
			panel.frame.Visible = true
			actions.Visible = true
		end
	end)
	return { frame = frame, scrim = 1 }
end

Nav.register("HireDone", build)

return {}
