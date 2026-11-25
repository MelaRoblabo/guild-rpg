--!strict
-- S-21d 引き直し（D-220・D-226）。S-21c と同じ配置。
--   - 今回の値に、前回の位置の目盛りと ▲▼ の差。前回の表は並べない。
--   - 右下：Choose（水色）と Reroll（金）を同じ大きさで並べる（Reroll が一番右）。
--     Reroll は無料の残り回数 → チケットの数 → 0 なら「+」（Roblox の購入画面。購入処理は M9）。
--   - Cancel（能力の面の下の中央）：今回を捨てて前回に戻す（D-086 の二択）。

local Components = require("../../ui/Components")
local HireCommon = require("./HireCommon")
local Nav = require("../../ui/Nav")
local Session = require("../../Session")

local I = Components.icon

local function hiredUid(r: any): string?
	for _, e in r.events or {} do
		if e.type == "Hired" then
			return e.uid
		end
	end
	return nil
end

local function build(params: any?, api: Nav.Api): Nav.Built
	local view = Session.view
	local h = view and view.hireSession
	local frame = HireCommon.scene("HireReroll")
	if not (h and h.pickedIndex and h.currentRoll) then
		task.defer(api.close)
		return { frame = frame, scrim = 1 }
	end
	local candidate = h.candidates[h.pickedIndex]
	-- Cancel で前回に戻した状態（今回は捨てる）
	local showingPrevious = params ~= nil and (params :: any).previous == true and h.previousRoll ~= nil
	local roll = if showingPrevious then h.previousRoll else h.currentRoll
	local prev = if showingPrevious then nil else h.previousRoll
	HireCommon.portrait(frame, candidate)
	local panel = HireCommon.statPanel(frame, candidate, roll, prev)
	HireCommon.closeTopRight(frame, api.close)

	if prev then
		local cancel = Components.button({
			kind = "brown",
			width = 220,
			height = 66,
			icon = I.undo,
			label = "Cancel",
			name = "Cancel",
			glyph = "Y",
			onClick = function()
				api.replace("HireReroll", { previous = true })
			end,
		})
		cancel.AnchorPoint = Vector2.new(0.5, 1)
		cancel.Position = UDim2.fromScale(0.5, 1)
		cancel.Parent = panel.footer
	end

	local actions = HireCommon.actionRow(frame)
	local choose = Components.button({
		kind = "blue",
		width = 300,
		icon = I.check,
		label = "Choose",
		name = "Choose",
		glyph = "A",
		onClick = function()
			local r =
				Session.sendAndWait({ type = "HireChoose", which = if showingPrevious then "previous" else "current" })
			if r and r.ok then
				api.replace("HireDone", { uid = hiredUid(r) })
			end
		end,
	})
	choose.LayoutOrder = 1
	choose.Parent = actions

	local tickets = (view.items and view.items.itm_slot_ticket) or 0
	local unique = candidate.kind == "unique"
	local kind: Components.ButtonKind
	local costText: string?
	local costIcon = "" -- 費用の札のアイコン（チケットのときだけ）
	if unique or showingPrevious then
		-- ユニークは能力が決まっている。前回に戻したあとの引き直しは、捨てた今回が「前回」になるため止める（Q 候補）
		kind, costText = "disabled", nil
	elseif h.freeRerollsLeft > 0 then
		kind, costText = "gold", "Free ×" .. h.freeRerollsLeft
	elseif tickets > 0 then
		kind, costText, costIcon = "gold", tostring(tickets), I.ticket
	else
		kind, costText, costIcon = "gold", I.plus, I.ticket
	end
	local reroll = Components.button({
		kind = kind,
		width = 300,
		icon = I.reroll,
		label = "Reroll",
		name = "Reroll",
		cost = costText,
		costIcon = costIcon,
		glyph = "X",
		onClick = function()
			if h.freeRerollsLeft <= 0 and tickets <= 0 then
				-- チケットを買う（Roblox の購入画面を重ね、閉じるとこの画面に戻る：D-226 ④。購入処理は M9）
				return
			end
			local r = Session.sendAndWait({ type = "HireReroll" })
			if r and r.ok then
				api.replace("HireInterview")
			end
		end,
	})
	reroll.LayoutOrder = 2
	reroll.Parent = actions
	return { frame = frame, scrim = 1 }
end

Nav.register("HireReroll", build)

return {}
