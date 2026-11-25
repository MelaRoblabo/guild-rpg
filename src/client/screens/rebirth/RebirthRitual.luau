--!strict
-- S-43a 転生の儀式（D-224）。左に大きなバストアップ、右に能力の面（引き継ぐ分＋加算分が入る余地）。
--   - 面の下に「上限レベル」と「経験値の倍率」の前→後の札2つ。
--   - 右下に金の Rebirth（語あり：取り消せない操作。費用はボタンの中）。押すと確認（D-230）を1枚はさむ。
--   - 転生できないとき（探索中・上限レベル未満・ゴールド不足）は押せない色にし、左に理由の札を1つ。

local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local HubState = require("../../hub/HubState")
local Nav = require("../../ui/Nav")
local Root = require("../../ui/Root")
local RebirthCommon = require("./RebirthCommon")
local Screen = require("../Screen")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

-- 前→後の札（アイコン・前・▶・後）
local function fromTo(icon: string, from: string, to: string): Frame
	local chip: Frame = new("Frame", {
		Size = UDim2.fromOffset(0, 52),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ch10,
		[CHILDREN] = {
			Components.corner(26),
			Components.padding(0, 16, 0, 16),
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	})
	for i, t in { { icon, C.bronzeHi }, { from, C.inkLight }, { "▶", C.ch45 }, { to, C.numHi } } do
		local l = Components.text({ text = t[1], size = 25, color = t[2], font = Tokens.font.number })
		l.LayoutOrder = i
		l.Parent = chip
	end
	return chip
end

local function build(params: any?, api: Nav.Api): Nav.Built
	local view = Session.view
	local uid = params and (params :: any).uid
	local adv = view and uid and view.adventurers[uid]
	local frame = Screen.scene("RebirthRitual")
	Screen.closeTopRight(frame, api.close)
	if not adv then
		return { frame = frame, scrim = 1 }
	end
	local K = master.K
	RebirthCommon.portrait(
		frame,
		{ kind = if adv.uniqueId then "unique" else "general", appearanceId = adv.appearanceId }
	)
	local data = RebirthCommon.preview(adv)
	local panel = RebirthCommon.statPanel(frame, adv, data, nil, nil)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12),
		Parent = panel.footer,
	})
	local nextCap = math.min(adv.levelCap + K.levelCapPerRebirth, K.levelCapMax)
	fromTo("Lv", tostring(adv.levelCap), tostring(nextCap)).Parent = panel.footer
	local mult = function(n: number): string
		return string.format("×%.1f", 1 + K.rebirthExpBonusPerCount * n)
	end
	fromTo("XP", mult(adv.rebirthCount), mult(adv.rebirthCount + 1)).Parent = panel.footer

	local actions = Screen.actionRow(frame)
	local reason = RebirthCommon.blockReason(view, adv)
	if reason then
		-- 理由の札を1つ（表示だけ。直す画面へは飛ばない：v3 の決め事）
		local icon, text, color = "⚠", "", C.warnDark
		if reason == "BUSY" then
			icon, text = "▶", ""
		elseif reason == "LEVEL_NOT_AT_CAP" then
			icon, text = "Lv", tostring(adv.level) .. " ▶ " .. tostring(adv.levelCap)
		elseif reason == "NOT_ENOUGH_GOLD" then
			icon, text = "G", HubState.formatNumber(view.gold)
		elseif reason == "MAX_REBIRTH" then
			icon, text = "Lv", tostring(adv.levelCap)
		end
		local warn = Components.chip(icon, text, color)
		Components.stroke(C.warnDark, 2).Parent = warn
		warn.Name = "Blocked"
		warn.LayoutOrder = 1
		warn.Parent = actions
	end
	local rebirth = Components.button({
		kind = if reason then "disabled" else "gold",
		width = 360,
		icon = RebirthCommon.icon.rebirth,
		label = "Rebirth",
		cost = HubState.formatNumber(RebirthCommon.cost(adv)),
		name = "Rebirth",
		glyph = "A",
		onClick = function()
			api.open("RebirthConfirm", { uid = adv.uid })
		end,
	})
	rebirth.LayoutOrder = 2
	rebirth.Parent = actions
	return { frame = frame, scrim = 1 }
end

-- 取り消せない操作の確認（D-230。11章 §5）：費用と「Lv が 1 に戻る」をアイコンと数字で見せる
local function buildConfirm(params: any?, api: Nav.Api): Nav.Built
	local view = Session.view
	local adv = view and params and view.adventurers[(params :: any).uid]
	local frame: Frame = new("Frame", {
		Name = "RebirthConfirm",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	if not adv then
		task.defer(api.close)
		return { frame = frame }
	end
	local band = Root.bandBottom()
	local panel, content = Components.panel({
		size = UDim2.fromOffset(560, 300),
		position = UDim2.new(0.5, 0, 0, band + 160),
		anchor = Vector2.new(0.5, 0),
		title = adv.name,
	})
	panel.Parent = frame
	local close = Components.closeButton(api.close)
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(1, -8, 0, 8)
	close.Parent = panel
	local rowFrame: Frame = new("Frame", {
		Size = UDim2.new(1, 0, 0, 60),
		Position = UDim2.fromOffset(0, 24),
		BackgroundTransparency = 1,
		[CHILDREN] = {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 16),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = content,
	})
	local lv = fromTo("Lv", tostring(adv.level), "1")
	lv.LayoutOrder = 1
	lv.Parent = rowFrame
	local cost = Components.chip("G", "-" .. HubState.formatNumber(RebirthCommon.cost(adv)))
	cost.LayoutOrder = 2
	cost.Parent = rowFrame
	local busy = false
	local go = Components.button({
		kind = "gold",
		width = 300,
		icon = RebirthCommon.icon.rebirth,
		label = "Rebirth",
		name = "Confirm",
		glyph = "A",
		onClick = function()
			if busy then
				return
			end
			busy = true
			local r = Session.sendAndWait({ type = "RebirthStart", adventurerUid = adv.uid })
			busy = false
			if r and r.ok then
				api.close() -- 確認を閉じ
				api.replace("RebirthCharge") -- 儀式を加算分のチャージに替える
			end
		end,
	})
	go.AnchorPoint = Vector2.new(0.5, 1)
	go.Position = UDim2.fromScale(0.5, 1)
	go.Parent = content
	return { frame = frame }
end

Nav.register("RebirthRitual", build)
Nav.register("RebirthConfirm", buildConfirm)

return {}
