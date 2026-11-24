--!strict
-- S-44 見た目の変更（D-051・D-053・D-224・D-231 ①）。入口は S-41 のポーション＋サイコロ（押すとすぐ1個使って抽選）。
--   - 転生 S-43d と同じ拍：1. シルエット（自動、ボタンなし）→ 2. 新しい見た目（光線）。
--   - 二択は雇用の引き直しにそろえる：新しい姿は左の大きな肖像、前の姿は右の面の中（少しくすませる）。
--     前に戻すのは面の下の中央の Cancel（茶・語あり）、新しい姿に決めるのは右下の金の Nice（D-224 の語）。
--   - 性別・職業の服の区分は変わらない。能力は変わらないので能力の面は出さない。
--   - 右上の × は選ぶのをあとにする（セッションは残り、S-41 から続きを開ける）。

local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local HireCommon = require("../hire/HireCommon")
local Nav = require("../../ui/Nav")
local Root = require("../../ui/Root")
local Screen = require("../Screen")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

-- シルエットの拍の長さ（仮。値は M8-FX でマスターデータへ）
local SILHOUETTE = 1.0

local function build(params: any?, api: Nav.Api): Nav.Built
	local uid = (params :: any).uid
	local band = Root.bandBottom()
	local frame = Screen.scene("LookChange")
	Screen.closeTopRight(frame, api.close)
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local beat = 1
	local busy = false
	local render: () -> ()

	local function choose(which: string)
		if busy then
			return
		end
		busy = true
		local r = Session.sendAndWait({ type = "ChangeAppearanceChoose", which = which })
		busy = false
		if r and r.ok then
			api.close()
		else
			render()
		end
	end

	render = function()
		body:ClearAllChildren()
		local view = Session.view
		if view == nil then
			return
		end
		local adv = view.adventurers[uid]
		local s = view.appearanceSession
		if adv == nil or s == nil or s.adventurerUid ~= uid then
			api.close()
			return
		end
		local job = master.jobs[adv.jobId]
		-- 左：新しい姿（仮の肖像。拍1はシルエット）
		local portrait = HireCommon.portrait(body, adv)
		local look = Components.text({
			text = if beat == 1 then "?" else s.currentId,
			size = if beat == 1 then 64 else 23,
			color = if beat == 1 then C.ch05 else C.rewardGlow,
			font = Tokens.font.number,
		})
		look.Name = "NewLook"
		look.AnchorPoint = Vector2.new(0.5, 0)
		look.Position = UDim2.new(0.5, 0, 0, 40)
		look.ZIndex = 9
		look.Parent = portrait
		-- 右：前の姿（くすませる）と Cancel
		local panel, content = Components.panel({
			size = UDim2.fromOffset(700, 448),
			position = UDim2.new(1, -40, 0, band + 44),
			anchor = Vector2.new(1, 0),
			title = adv.name .. " " .. (if adv.gender == "f" then "♀" else "♂"),
		})
		panel.Name = "Previous"
		panel.Parent = body
		local tags = Components.chip(
			if job and job.attackType == "magic" then "◈" else "⚔",
			(if job then job.nameEn else adv.jobId) .. "   Lv " .. adv.level,
			C.inkLight
		)
		tags.AnchorPoint = Vector2.new(1, 0.5)
		tags.Position = UDim2.new(1, -96, 0, 0)
		tags.ZIndex = 8
		tags.Parent = panel
		new("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = content,
		})
		local prev: Frame = new("Frame", {
			Name = "PrevPortrait",
			LayoutOrder = 1,
			Size = UDim2.fromOffset(260, 290),
			BackgroundColor3 = C.ch13,
			BackgroundTransparency = if beat == 1 then 0.6 else 0.15,
			[CHILDREN] = { Components.corner(8), Components.stroke(C.ch16, 6) },
			Parent = content,
		})
		local pl = Components.text({ text = s.previousId, size = 21, color = C.inkLight, font = Tokens.font.number })
		pl.AnchorPoint = Vector2.new(0.5, 0.5)
		pl.Position = UDim2.fromScale(0.5, 0.5)
		pl.TextTransparency = 0.35
		pl.Parent = prev
		if beat == 2 then
			local cancel = Components.button({
				kind = "brown",
				width = 220,
				height = 66,
				label = "Cancel",
				name = "Cancel",
				glyph = "Y",
				onClick = function()
					choose("previous")
				end,
			})
			cancel.LayoutOrder = 2
			cancel.Parent = content
			local actions = Screen.actionRow(body)
			local nice = Components.button({
				kind = "gold",
				width = 320,
				icon = "★",
				label = "Nice",
				name = "Nice",
				glyph = "A",
				onClick = function()
					choose("current")
				end,
			})
			nice.LayoutOrder = 2
			nice.Parent = actions
		end
	end

	render()
	task.delay(SILHOUETTE, function()
		if body.Parent then
			beat = 2
			render()
		end
	end)
	return { frame = frame, scrim = 1 }
end

Nav.register("LookChange", build)

return {}
