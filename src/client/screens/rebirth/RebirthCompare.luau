--!strict
-- S-43c 比較・引き直し（D-224・D-226 ②）。雇用の S-21d と同じ形。
--   - 今回の値に、前回の位置の目盛りと加算分の ▲▼。前回の表は並べない。
--   - 右下：Choose（水色）と Reroll（金）を同じ大きさで並べる。Reroll は無料の残り → スロットチケット → 0 なら「+」。
--   - Cancel（面の下の中央）：今回を捨てて前回に戻す（D-086）。戻したあとの引き直しは止める（雇用と同じ。HireRevert の Q）。

local Components = require("../../ui/Components")
local Nav = require("../../ui/Nav")
local RebirthCommon = require("./RebirthCommon")
local Screen = require("../Screen")
local Session = require("../../Session")

local I = Components.icon

local function build(params: any?, api: Nav.Api): Nav.Built
	local view = Session.view
	local r = view and view.rebirthSession
	local frame = Screen.scene("RebirthCompare")
	if not r then
		task.defer(api.close)
		return { frame = frame, scrim = 1 }
	end
	local adv = view.adventurers[r.adventurerUid]
	local showingPrevious = params ~= nil and (params :: any).previous == true and r.previousBonus ~= nil
	local bonus = if showingPrevious then r.previousBonus else r.currentBonus
	local prev = if showingPrevious then nil else r.previousBonus
	RebirthCommon.portrait(
		frame,
		{ kind = if adv.uniqueId then "unique" else "general", appearanceId = adv.appearanceId }
	)
	local panel = RebirthCommon.statPanel(frame, adv, r, bonus, prev)
	Screen.closeTopRight(frame, api.close)

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
				api.replace("RebirthCompare", { previous = true })
			end,
		})
		cancel.AnchorPoint = Vector2.new(0.5, 1)
		cancel.Position = UDim2.fromScale(0.5, 1)
		cancel.Parent = panel.footer
	end

	local actions = Screen.actionRow(frame)
	local busy = false
	local choose = Components.button({
		kind = "blue",
		width = 300,
		icon = I.check,
		label = "Choose",
		name = "Choose",
		glyph = "A",
		onClick = function()
			if busy then
				return
			end
			busy = true
			local res = Session.sendAndWait({
				type = "RebirthChoose",
				which = if showingPrevious then "previous" else "current",
			})
			busy = false
			if res and res.ok then
				local ev = (res.events or {})[1] or {}
				-- 3拍目の棒に使う尺度（確定するとセッションは消える）
				api.replace("RebirthDone", {
					uid = adv.uid,
					gift = ev.giftAdded,
					scale = { inherited = r.inherited, bonusMax = r.bonusMax, bonus = bonus },
				})
			end
		end,
	})
	choose.LayoutOrder = 1
	choose.Parent = actions

	local tickets = (view.items and view.items.itm_slot_ticket) or 0
	local kind: Components.ButtonKind = "gold"
	local costText: string? = nil
	if showingPrevious then
		kind = "disabled"
	elseif r.freeRerollsLeft > 0 then
		costText = "Free ×" .. r.freeRerollsLeft
	elseif tickets > 0 then
		costText = Components.plain(I.ticket) .. " " .. tickets
	else
		costText = Components.plain(I.ticket) .. " " .. I.plus
	end
	local reroll = Components.button({
		kind = kind,
		width = 300,
		icon = I.reroll,
		label = "Reroll",
		cost = costText,
		costIcon = "",
		name = "Reroll",
		glyph = "X",
		onClick = function()
			if busy then
				return
			end
			if r.freeRerollsLeft <= 0 and tickets <= 0 then
				-- チケットを買う（Roblox の購入画面を重ね、閉じるとこの画面に戻る：D-226 ④。購入処理は M9）
				return
			end
			busy = true
			local res = Session.sendAndWait({ type = "RebirthReroll" })
			busy = false
			if res and res.ok then
				api.replace("RebirthCharge")
			end
		end,
	})
	reroll.LayoutOrder = 2
	reroll.Parent = actions
	return { frame = frame, scrim = 1 }
end

Nav.register("RebirthCompare", build)

return {}
