--!strict
-- S-21b 求人票（D-220・D-283）。候補の数だけ求人票が机に乗っている（伏せた票はない：D-283）。
--   - 票は絵（いちばん大きく）・名前・性別・職業・ギフトだけ。伸びやすさ（Growth）は職業を押したときだけ小さな札で出す。
--   - 票を押すと真ん中に大きく出る（他の票の上、暗幕の上）。Hire 以外のどこを押しても並びに戻る。
--   - 右下の判子（Hire）で、大きく出した票の人を採用＝面接へ。選ばなかった候補は破棄される。
--   - Hire は最初から押せない色で出し、票を選ぶと金。押せない色でも押すと理由を出す（D-250 ⑥・D-264 ②）。
--     選ぶまでは票が少し揺れる（D-250 ⑥）。
--   - 特別な訪問者（ユニーク）は金の票で、能力は最初から決まっている。採用すると面接を飛ばして S-21e へ。

local TweenService = game:GetService("TweenService")

local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Art = require("../../ui/Art")
local HireCommon = require("./HireCommon")
local Motion = require("../../ui/Motion")
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

-- 票の大きさ（基準の単位）。並びに入りきらない枚数（候補枠の拡張）は UIScale で縮める
local SHEET_W = 300
local SHEET_H = 400
local GAP = 28
local ROW_W = 1200 -- 並べてよい幅（左右 40 ずつ空ける）
local BIG = 1.2 -- 真ん中に出したときの大きさ
local ART_H = 236 -- 絵の高さ（票の中でいちばん大きい）
local MOVE = 0.3 -- 並び ⇔ 真ん中の動き（D-269 ⑤：0.3〜0.6 秒）

type Sheet = {
	button: TextButton,
	ring: UIStroke,
	zoom: UIScale,
	job: TextButton,
	growth: Frame,
}

local function sheet(candidate: any, index: number): Sheet
	local unique = candidate.kind == "unique"
	local ring = Components.stroke(C.selAmber, 4, 1)
	local b: TextButton = new("TextButton", {
		Name = "Sheet" .. index,
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(SHEET_W, SHEET_H),
		BackgroundColor3 = if unique then C.rewardGlow else C.ch68,
		ZIndex = 2,
		[CHILDREN] = {
			Components.corner(10),
			Components.stroke(if unique then C.ctaGoldRim else C.ch50, 3),
			ring,
		},
	})
	local zoom = new("UIScale", { Name = "Zoom", Parent = b })
	local job = master.jobs[candidate.jobId]

	-- 絵（バストアップ。票の中でいちばん大きい）
	local art: Frame = new("Frame", {
		Name = "Art",
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(1, -24, 0, ART_H),
		BackgroundColor3 = C.ch45,
		[CHILDREN] = { Components.corner(8), Components.stroke(C.ch16, 2) },
		Parent = b,
	})
	if not Portrait.fill(art, candidate.appearanceId) then
		local ph = Components.text({ text = "Bust-up (placeholder)", size = 21, color = C.inkLight })
		ph.AutomaticSize = Enum.AutomaticSize.None
		ph.Size = UDim2.fromScale(1, 1)
		ph.Parent = art
	end
	-- 黄色い票（特別な訪問者）には「Unique」の帯（D-269 ④。色だけでは分からなかった）
	if unique then
		local band: Frame = new("Frame", {
			Name = "UniqueBand",
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.new(1, -24, 0, 34),
			BackgroundColor3 = C.ctaGoldRim,
			ZIndex = 5,
			[CHILDREN] = { Components.corner(6) },
			Parent = b,
		})
		local w =
			Components.text({ text = "", size = 21, color = C.inkWhite, font = Tokens.font.display, stroke = true })
		w.AnchorPoint = Vector2.new(0.5, 0.5)
		w.Position = UDim2.fromScale(0.5, 0.5)
		w.ZIndex = 6
		w.Parent = band
		Components.setParts(w, { Components.icon.star, "Unique" })
	end

	-- 名前と性別
	local name = Components.text({
		text = candidate.name .. " " .. (if candidate.gender == "f" then "♀" else "♂"),
		size = Tokens.text.body,
		color = C.inkDark,
		font = Tokens.font.bodyStrong,
		xAlign = Enum.TextXAlignment.Left,
	})
	name.Name = "Name"
	name.Position = UDim2.fromOffset(14, ART_H + 20)
	name.Parent = b

	-- 職業（押せる札。押すと Growth の札を開く・閉じる）。押せるので茶のボタンと同じ縁（D-222）
	local jobButton: TextButton = new("TextButton", {
		Name = "Job",
		Text = "",
		AutoButtonColor = false,
		Position = UDim2.fromOffset(12, ART_H + 58),
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ch28,
		ZIndex = 3,
		[CHILDREN] = {
			Components.corner(22),
			Components.stroke(C.bronze, 2),
			Components.padding(0, 14, 0, 14),
		},
		Parent = b,
	})
	local jobText = Components.text({ text = "", size = 23, color = C.inkLight, font = Tokens.font.bodyStrong })
	jobText.Size = UDim2.fromOffset(0, 44)
	jobText.ZIndex = 4
	jobText.Parent = jobButton
	Components.setParts(jobText, {
		if job and job.attackType == "magic" then "@job_magic" else "@job_physical",
		if job then job.nameEn else candidate.jobId,
		Components.icon.up, -- ▲＝伸びやすさ（押すと Growth が出る）
	})

	-- ギフト
	local gifts: Frame = new("Frame", {
		Name = "Gifts",
		Position = UDim2.fromOffset(14, ART_H + 112),
		Size = UDim2.new(1, -28, 0, 34),
		BackgroundTransparency = 1,
		ZIndex = 3,
		[CHILDREN] = {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 12),
			}),
		},
		Parent = b,
	})
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
		t.ZIndex = 4
		t.Parent = gifts
		if medalImage then
			-- メダルの絵を語の左に（文字を右へずらす）
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 34)
			pad.Parent = t
			local medal = Art.icon(medalImage, 28, 0) :: ImageLabel
			medal.Position = UDim2.fromOffset(-34, 1)
			medal.ZIndex = 5
			medal.Parent = t
		end
	end

	-- Growth の札（職業を押したときだけ。職業の札のすぐ上、絵の下の方に重ねる）。上位2つの ▲（D-046・Guild UI）
	local growth: Frame = new("Frame", {
		Name = "Growth",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromOffset(12, ART_H + 52),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = C.ch13,
		Visible = false,
		ZIndex = 10,
		[CHILDREN] = {
			Components.corner(8),
			Components.stroke(C.bronze, 2),
			Components.padding(8, 14, 8, 14),
			new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		},
		Parent = b,
	})
	local header = Components.text({
		text = "",
		size = 21,
		color = C.inkLight,
		font = Tokens.font.display,
		xAlign = Enum.TextXAlignment.Left,
	})
	header.LayoutOrder = 0
	header.ZIndex = 11
	header.Parent = growth
	Components.setParts(header, { Components.icon.up, Words.growth })
	local marks = HireCommon.growthMarks(candidate.jobId)
	for i, s in HireCommon.STATS do
		local m = marks[s.key]
		if m then
			local line = Components.text({
				text = "",
				size = 23,
				color = C.inkLight,
				font = Tokens.font.number,
				xAlign = Enum.TextXAlignment.Left,
			})
			line.LayoutOrder = i
			line.ZIndex = 11
			line.Parent = growth
			Components.setParts(line, {
				"@stat_" .. s.key,
				s.label,
				string.rep(Components.plain(Components.icon.up), m),
			})
		end
	end
	return { button = b, ring = ring, zoom = zoom, job = jobButton, growth = growth }
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

	local n = #h.candidates
	-- 並びに入りきらない枚数は縮める（候補枠の拡張で 4〜6 枚：Expansions）
	local fit = math.min(1, (ROW_W - (n - 1) * GAP) / (n * SHEET_W))
	local rowW = n * SHEET_W * fit + (n - 1) * GAP
	local rowY = band + 40 + SHEET_H * fit / 2
	local bigY = band + 12 + SHEET_H * BIG / 2 -- 真ん中に出した票（帯のすぐ下から）

	local selected: number? = nil
	local growthOpen: number? = nil
	local sheets: { Sheet } = {}
	local stamp: Frame
	local sways: { Tween } = {}

	-- 暗幕：票を真ん中に出している間だけ。押すと並びに戻る（Hire 以外のどこでも：D-283）
	local scrim: TextButton = new("TextButton", {
		Name = "Scrim",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.scrim,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 35,
		Parent = frame,
	})

	local function slotPos(i: number): UDim2
		local x = -rowW / 2 + (i - 1) * (SHEET_W * fit + GAP) + SHEET_W * fit / 2
		return UDim2.new(0.5, x, 0, rowY)
	end

	local function refresh()
		for i, s in sheets do
			local on = selected == i
			s.ring.Transparency = if on then 0 else 1
			s.button.ZIndex = if on then 40 else 2
			s.growth.Visible = growthOpen == i
			local info = TweenInfo.new(MOVE, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			TweenService:Create(s.button, info, { Position = if on then UDim2.new(0.5, 0, 0, bigY) else slotPos(i) })
				:Play()
			TweenService:Create(s.zoom, info, { Scale = if on then BIG else fit }):Play()
		end
		scrim.Visible = selected ~= nil
		if selected ~= nil then
			scrim.BackgroundTransparency = 1
			TweenService:Create(scrim, TweenInfo.new(0.2), { BackgroundTransparency = 0.5 }):Play() -- 暗幕 50%（D-225）
		end
		-- Hire は最初から押せない色で出し、票を選ぶと金（D-250 ⑥）。押せない色でも押せて理由を出す（D-264 ②）
		Components.setButtonKind(stamp, if selected ~= nil then "gold" else "disabled")
		local face = stamp:FindFirstChild("Face") :: TextButton?
		if face then
			face.Active = true
		end
		-- 選ぶまでは票が少し浮いて揺れる（触れる物だと分かるように）
		for _, tw in sways do
			tw:Cancel()
		end
		table.clear(sways)
		for i, s in sheets do
			s.button.Rotation = 0
			if selected == nil then
				s.button.Rotation = -1.5
				local tw = TweenService:Create(
					s.button,
					TweenInfo.new(0.9 + i * 0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Rotation = 1.5 }
				)
				tw:Play()
				table.insert(sways, tw)
			end
		end
	end

	local function backToRow()
		if selected == nil and growthOpen == nil then
			return
		end
		selected = nil
		growthOpen = nil
		refresh()
	end
	scrim.Activated:Connect(backToRow)

	local hiring = false
	local function hire()
		if selected == nil then
			Motion.reason(stamp, Words.reason.pickPosting)
			return
		end
		if hiring then
			return
		end
		hiring = true
		local idx = selected
		local r = Session.sendAndWait({ type = "HirePick", candidateIndex = idx })
		if not (r and r.ok) then
			hiring = false
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
			else
				hiring = false
			end
		else
			api.replace("HireInterview")
		end
	end

	for i, c in h.candidates do
		local s = sheet(c, i)
		s.button.Position = slotPos(i)
		s.zoom.Scale = fit
		s.button.Parent = frame
		sheets[i] = s
		s.button.Activated:Connect(function()
			if selected == nil then
				selected = i -- 押した票を真ん中に大きく
				growthOpen = nil
				refresh()
			else
				backToRow() -- 大きく出した票をもう一度押しても並びに戻る（採用は Hire だけ：D-283）
			end
		end)
		s.job.Activated:Connect(function()
			-- 職業を押すと Growth の札（もう一度で閉じる）。並び・真ん中のどちらでも、票の選び方は変えない
			growthOpen = if growthOpen == i then nil else i
			for j, o in sheets do
				o.growth.Visible = growthOpen == j
			end
		end)
	end

	local actions = HireCommon.actionRow(frame)
	actions.ZIndex = 45 -- 暗幕の上（Hire だけは並びに戻さない：D-283）
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
