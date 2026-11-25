--!strict
-- S-21b 求人票（D-220）。候補の数だけ求人票が机に乗っている。
--   - 1枚は折りたたまれていて、触ると開く（演出の仮）。
--   - 求人票を触ると大きくなり、右下の判子（もう一度選ぶ）で採用＝面接へ。選ばなかった候補は破棄される。
--   - 判子（Hire）は最初から押せない色で出し、票を選ぶと金。選ぶまでは票が少し揺れる（D-250 ⑥）。
--   - 特別な訪問者（ユニーク）は金の票で、能力は最初から決まっている。採用すると面接を飛ばして S-21e へ。

local TweenService = game:GetService("TweenService")

local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Art = require("../../ui/Art")
local HireCommon = require("./HireCommon")
local Nav = require("../../ui/Nav")
local Portrait = require("../../ui/Portrait")
local Root = require("../../ui/Root")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local Words = require("../../ui/Words")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local SHEET_W = 300
local SHEET_H = 430

local function sheet(candidate: any, index: number): (TextButton, UIStroke)
	local unique = candidate.kind == "unique"
	local ring = Components.stroke(C.selAmber, 4, 1)
	local b: TextButton = new("TextButton", {
		Name = "Sheet" .. index,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(SHEET_W, SHEET_H),
		BackgroundColor3 = if unique then C.rewardGlow else C.ch68,
		[CHILDREN] = {
			Components.corner(8),
			Components.stroke(if unique then C.ctaGoldRim else C.ch50, 3),
			ring,
		},
	})
	-- 中身は別の枠に並べる（折りたたみの覆いが並びに入らないように）
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		[CHILDREN] = {
			Components.padding(12, 12, 12, 12),
			new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		},
		Parent = b,
	})
	local job = master.jobs[candidate.jobId]
	-- 顔（仮）・名前・性別・職業
	local head: Frame = new("Frame", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 72),
		BackgroundTransparency = 1,
		Parent = body,
	})
	local face: Frame = new("Frame", {
		Name = "Face",
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = C.ch45,
		[CHILDREN] = { Components.corner(8), Components.stroke(C.ch16, 2) },
		Parent = head,
	})
	Portrait.fill(face, candidate.appearanceId)
	local name = Components.text({
		text = candidate.name .. " " .. (if candidate.gender == "f" then "♀" else "♂"),
		size = 23,
		color = C.inkDark,
		font = Tokens.font.bodyStrong,
		xAlign = Enum.TextXAlignment.Left,
	})
	name.Position = UDim2.fromOffset(74, 4)
	name.Parent = head
	local jobText = Components.text({
		text = "",
		size = 21,
		color = C.inkDark,
		font = Tokens.font.body,
		xAlign = Enum.TextXAlignment.Left,
	})
	jobText.Position = UDim2.fromOffset(74, 38)
	jobText.Parent = head
	Components.setParts(jobText, {
		if job and job.attackType == "magic" then "@job_magic" else "@job_physical",
		if job then job.nameEn else "",
	})
	-- 能力の行（表記と伸びやすさの ▲。値はまだ決まっていない＝サイコロ。ユニークは決まった値）
	local marks = HireCommon.growthMarks(candidate.jobId)
	local fixed = if unique and master.uniques[candidate.uniqueId]
		then master.uniques[candidate.uniqueId].baseStats
		else nil
	for i, s in HireCommon.STATS do
		local row: Frame = new("Frame", {
			LayoutOrder = 1 + i,
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundColor3 = C.ch75,
			[CHILDREN] = { Components.corner(6), Components.padding(0, 10, 0, 10) },
			Parent = body,
		})
		local label = Components.text({
			text = s.label .. " " .. string.rep("▲", marks[s.key] or 0),
			size = 21,
			color = C.inkDark,
			font = Tokens.font.number,
			xAlign = Enum.TextXAlignment.Left,
		})
		label.Position = UDim2.fromOffset(0, 8)
		label.Parent = row
		local value = Components.text({
			text = if fixed then tostring(fixed[s.key]) else "?",
			size = 23,
			color = if fixed then C.numHi else C.inkLight,
			font = Tokens.font.number,
		})
		local well: Frame = new("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(56, 32),
			BackgroundColor3 = C.ch13,
			[CHILDREN] = { Components.corner(6) },
			Parent = row,
		})
		value.AutomaticSize = Enum.AutomaticSize.None
		value.Size = UDim2.fromScale(1, 1)
		value.Parent = well
	end
	-- ギフト
	for _, g in candidate.giftIds or {} do
		local gift = master.gifts[g]
		local medalImage = Art.gift(g)
		local t = Components.text({
			text = (if medalImage then "" else "◆ ") .. (if gift then gift.nameEn else g),
			size = 21,
			color = C.inkDark,
			font = Tokens.font.bodyStrong,
			xAlign = Enum.TextXAlignment.Left,
		})
		t.LayoutOrder = 20
		t.Parent = body
		if medalImage then
			-- メダルの絵を語の左に（文字を右へずらす）
			t.Size = UDim2.new(1, 0, 0, 30)
			t.AutomaticSize = Enum.AutomaticSize.None
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 34)
			pad.Parent = t
			local medal = Art.icon(medalImage, 28, 0) :: ImageLabel
			medal.Position = UDim2.fromOffset(-34, 1)
			medal.Parent = t
		end
	end
	return b, ring
end

local function build(_params: any?, api: Nav.Api): Nav.Built
	local view = Session.view
	local h = view and view.hireSession
	local band = Root.bandBottom()
	local frame = HireCommon.scene("HirePostings")
	-- 机（仮）
	new("Frame", {
		Name = "Desk",
		Position = UDim2.fromOffset(0, band),
		Size = UDim2.new(1, 0, 1, -band),
		BackgroundColor3 = Color3.new(1, 1, 1),
		[CHILDREN] = { Components.gradient(C.ch28, C.ch13) },
		Parent = frame,
	})
	HireCommon.closeTopRight(frame, api.close)
	if not h then
		return { frame = frame, scrim = 1 }
	end
	local row: Frame = new("Frame", {
		Name = "Sheets",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, band + 40),
		Size = UDim2.fromOffset(0, SHEET_H),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		ZIndex = 2,
		[CHILDREN] = {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 28),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = frame,
	})
	local selected: number? = nil
	local rings: { UIStroke } = {}
	local sheets: { TextButton } = {}
	local stamp: Frame
	local sways: { Tween } = {}
	local function refresh()
		for i, s in sheets do
			local on = selected == i
			rings[i].Transparency = if on then 0 else 1
			s.Size = if on then UDim2.fromOffset(SHEET_W * 1.08, SHEET_H * 1.08) else UDim2.fromOffset(SHEET_W, SHEET_H)
			s.BackgroundTransparency = if selected ~= nil and not on then 0.35 else 0
		end
		-- Hire は最初から押せない色で出し、票を選ぶと金（D-250 ⑥）
		Components.setButtonKind(stamp, if selected ~= nil then "gold" else "disabled")
		-- 選ぶまでは票が少し浮いて揺れる（触れる物だと分かるように）
		for _, tw in sways do
			tw:Cancel()
		end
		table.clear(sways)
		for i, s in sheets do
			s.Rotation = 0
			if selected == nil then
				s.Rotation = -1.5
				local tw = TweenService:Create(
					s,
					TweenInfo.new(0.9 + i * 0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Rotation = 1.5 }
				)
				tw:Play()
				table.insert(sways, tw)
			end
		end
	end
	local function hire()
		if selected == nil then
			return
		end
		local idx = selected
		local r = Session.sendAndWait({ type = "HirePick", candidateIndex = idx })
		if not (r and r.ok) then
			return
		end
		if h.candidates[idx].kind == "unique" then
			-- 特別な訪問者は面接を飛ばす（D-220）
			local r2 = Session.sendAndWait({ type = "HireChoose", which = "current" })
			if r2 and r2.ok then
				local uid = nil
				for _, e in r2.events or {} do
					if e.type == "Hired" then
						uid = e.uid
					end
				end
				api.replace("HireDone", { uid = uid })
			end
		else
			api.replace("HireInterview")
		end
	end
	local folded = #h.candidates -- 最後の1枚は折りたたんでおく（触ると開く）
	for i, c in h.candidates do
		local s, ring = sheet(c, i)
		s.LayoutOrder = i
		s.Parent = row
		sheets[i] = s
		rings[i] = ring
		if i == folded and c.kind ~= "unique" then
			local cover: TextButton = new("TextButton", {
				Name = "Folded",
				Text = "",
				AutoButtonColor = false,
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.ch52,
				ZIndex = 10,
				[CHILDREN] = { Components.corner(8), Components.stroke(C.ch16, 3) },
				Parent = s,
			})
			local seal = Components.text({ text = "?", size = 40, color = C.inkLight, font = Tokens.font.display })
			seal.AutomaticSize = Enum.AutomaticSize.None
			seal.Size = UDim2.fromScale(1, 1)
			seal.ZIndex = 11
			seal.Parent = cover
			cover.Activated:Connect(function()
				cover:Destroy()
			end)
		end
		s.Activated:Connect(function()
			if selected == i then
				hire() -- もう一度選ぶと採用
			else
				selected = i
				refresh()
			end
		end)
	end
	local actions = HireCommon.actionRow(frame)
	stamp = Components.button({
		kind = "gold",
		width = 200,
		icon = Components.icon.stamp,
		label = Words.hire,
		name = "Stamp",
		glyph = "A",
		onClick = hire,
	})
	stamp.Parent = actions
	refresh()
	return { frame = frame, scrim = 1 }
end

Nav.register("HirePostings", build)

return {}
