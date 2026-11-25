--!strict
-- S-43d 転生完了（D-224・D-230）。雇用の S-21e と同じ形の3拍。
--   1拍目：シルエット（自動で進む）。
--   2拍目：新しい見た目（光）。金の Nice＝この見た目にする／水色＝見た目維持ポーションで前の姿に戻す（個数つき、
--          0個は「+」で購入の導線。購入は M9）。見た目を決めるのはここの1回だけ（D-230）。ユニークは見た目固定なので飛ばす。
--   3拍目：転生後の能力と、ギフトが増えた回は +1 の札。右下の金は Train（S-41 は M8-6。それまではメイン画面へ）。

local TweenService = game:GetService("TweenService")

local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Nav = require("../../ui/Nav")
local RebirthCommon = require("./RebirthCommon")
local Root = require("../../ui/Root")
local Screen = require("../Screen")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local Words = require("../../ui/Words")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local SILHOUETTE = 0.9 -- 1拍目の秒（仮。本番は M8-FX）

local function build(params: any?, api: Nav.Api): Nav.Built
	local p = (params or {}) :: any
	local view = Session.view
	local adv = view and p.uid and view.adventurers[p.uid]
	local frame = Screen.scene("RebirthDone")
	Screen.closeTopRight(frame, api.home)
	if not adv then
		return { frame = frame, scrim = 1 }
	end
	local band = Root.bandBottom()
	local portrait = RebirthCommon.portrait(
		frame,
		{ kind = if adv.uniqueId then "unique" else "general", appearanceId = adv.appearanceId }
	)
	-- 光（2拍目）
	local rays: Frame = new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(380, 380),
		BackgroundColor3 = C.rewardGlow,
		BackgroundTransparency = 1,
		ZIndex = 10, -- 面の中身より手前（薄い光なので仮の絵は透けて見える）
		[CHILDREN] = { Components.corner(190) },
		Parent = portrait,
	})
	-- バストアップの画像があるときは、光を顔の後ろへ回す（顔に色がかぶらないように）
	local bust = portrait:FindFirstChild("Bust", true)
	if bust and bust:IsA("GuiObject") and bust.Parent then
		rays.Parent = bust.Parent
		rays.ZIndex = bust.ZIndex - 1
	end
	-- シルエット（1拍目）
	local shadow: Frame = new("Frame", {
		Name = "Silhouette",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.ch05,
		ZIndex = 20,
		[CHILDREN] = { Components.corner(Tokens.radius.radiusPanel) },
		Parent = portrait,
	})
	local q = Components.text({ text = "?", size = 40, color = C.ch28, font = Tokens.font.display })
	q.AutomaticSize = Enum.AutomaticSize.None
	q.Size = UDim2.fromScale(1, 1)
	q.ZIndex = 21
	q.Parent = shadow

	local actions = Screen.actionRow(frame)
	local busy = false

	-- 3拍目：転生後の能力と Train
	local function showSummary()
		actions:ClearAllChildren()
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 16),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = actions,
		})
		local now = Session.view.adventurers[adv.uid] or adv
		if p.scale then
			-- 比べた画面と同じ尺度（引き継ぐ分＋加算分／上限）
			RebirthCommon.statPanel(frame, now, p.scale, p.scale.bonus, nil)
		else
			-- 途中から開いた（尺度が残っていない）：今の値だけ
			local zero = { str = 0, mag = 0, agi = 0, dex = 0, hp = 0 }
			RebirthCommon.statPanel(frame, now, { inherited = now.baseStats, bonusMax = zero }, nil, nil)
		end
		if p.gift then
			local gift = master.gifts[p.gift]
			local chip = Components.chip("◆", "+1", C.numHi)
			chip.Name = "GiftAdded"
			chip.AnchorPoint = Vector2.new(1, 0)
			chip.Position = UDim2.new(1, -120, 0, band + 19)
			chip.ZIndex = 12
			chip.Parent = frame
			if gift then
				chip:SetAttribute("GiftName", gift.nameEn)
			end
		end
		local train = Components.button({
			kind = "gold",
			width = 200,
			icon = RebirthCommon.icon.train,
			label = Words.train,
			name = "Train",
			glyph = "A",
			onClick = function()
				-- トレーニング（S-41）は M8-6。それまではメイン画面へ
				api.home()
			end,
		})
		train.LayoutOrder = 2
		train.Parent = actions
	end

	-- 2拍目：新しい見た目と、決める2つのボタン
	local function showLook()
		TweenService:Create(rays, TweenInfo.new(0.4), { BackgroundTransparency = 0.75 }):Play()
		local keep = (view.items and view.items.itm_potion_appearance_keep) or 0
		local potion = Components.button({
			kind = "blue",
			width = 300,
			icon = RebirthCommon.icon.keep,
			label = Words.keepLook,
			cost = if keep > 0 then tostring(keep) else Components.icon.plus,
			costIcon = "",
			name = "KeepLook",
			glyph = "X",
			onClick = function()
				if busy then
					return
				end
				if keep <= 0 then
					-- ポーションを買う（Roblox の購入画面を重ね、閉じるとこの画面に戻る：D-226 ④。購入処理は M9）
					return
				end
				busy = true
				local r = Session.sendAndWait({ type = "RebirthAppearanceChoose", which = "previous" })
				busy = false
				if r and r.ok then
					showSummary()
				end
			end,
		})
		potion.LayoutOrder = 1
		potion.Parent = actions
		local nice = Components.button({
			kind = "gold",
			width = 300,
			icon = "✓",
			label = "Nice",
			name = "Nice",
			glyph = "A",
			onClick = function()
				if busy then
					return
				end
				busy = true
				local r = Session.sendAndWait({ type = "RebirthAppearanceChoose", which = "current" })
				busy = false
				if r and r.ok then
					showSummary()
				end
			end,
		})
		nice.LayoutOrder = 2
		nice.Parent = actions
	end

	local pending = view.rebirthAppearance and view.rebirthAppearance.adventurerUid == adv.uid
	local alive = true
	task.delay(if p.resume then 0 else SILHOUETTE, function()
		if not alive then
			return
		end
		TweenService:Create(shadow, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(q, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		if pending then
			showLook()
		else
			showSummary() -- ユニーク（見た目固定）・旧版のセッションは見た目を選ばない
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

Nav.register("RebirthDone", build)

return {}
