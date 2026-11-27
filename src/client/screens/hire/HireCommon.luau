--!strict
-- 雇用の画面（S-21a〜e、D-220・D-226・D-283）で共有する部品。
--   - S-21c・d・e は同じ配置：左に肖像の枠（460×486）、右に能力の面（700×448、題の札＝名前、5行＋Total、下に Cancel の段）。
--   - Total は HP を除く4項目の合計（Q-006）。hireTotalGreat・hireTotalAmazing 以上は金の行と語の札（D-283）。
--   - 絵は仮（バストアップの代わりの枠。D-227 ②）。

local Hiring = require("@game/ReplicatedStorage/Core/Hiring")
local Party = require("@game/ReplicatedStorage/Core/Party")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Portrait = require("../../ui/Portrait")
local Root = require("../../ui/Root")
local Screen = require("../Screen")
local Tokens = require("../../ui/Tokens")
local Words = require("../../ui/Words")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local HireCommon = {}

HireCommon.STATS = {
	{ key = "str", label = "STR" },
	{ key = "mag", label = "MAG" },
	{ key = "agi", label = "AGI" },
	{ key = "dex", label = "DEX" },
	{ key = "hp", label = "HP" },
}

-- 場面・右上の ×・右下の並びは画面共通（../Screen）
HireCommon.scene = Screen.scene
HireCommon.closeTopRight = Screen.closeTopRight
HireCommon.actionRow = Screen.actionRow

-- 伸びやすさの ▲ の数（上位2つだけ：D-046・Guild UI）
function HireCommon.growthMarks(jobId: string): { [string]: number }
	local job = master.jobs[jobId]
	local out: { [string]: number } = {}
	if not job or not job.growth then
		return out
	end
	local list = {}
	for _, s in HireCommon.STATS do
		table.insert(list, { key = s.key, v = job.growth[s.key] or 0 })
	end
	table.sort(list, function(a, b)
		return a.v > b.v
	end)
	for i = 1, 2 do
		local e = list[i]
		if e and e.v > 0 then
			out[e.key] = if e.v >= 5 then 3 elseif e.v >= 3 then 2 else 1
		end
	end
	return out
end

-- 攻撃に使う能力（太く見せる）
function HireCommon.attackStat(jobId: string): string
	local job = master.jobs[jobId]
	return if job and job.attackType == "magic" then "mag" else "str"
end

-- 肖像の枠（S-21c・d・e で同じ位置）
function HireCommon.portrait(parent: Frame, candidate: any)
	local band = Root.bandBottom()
	local frame, content = Components.panel({
		size = UDim2.fromOffset(460, 486),
		position = UDim2.fromOffset(40, band + 16),
		dark = true,
	})
	frame.Name = "Portrait"
	frame.Parent = parent
	local label = Components.text({
		text = "Bust-up (placeholder)",
		size = 21,
		color = C.inkLight,
	})
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = content
	if candidate and Portrait.fill(content, candidate.appearanceId) then
		label.Visible = false -- バストアップの画像があれば仮の文字を隠す
	end
	if candidate and candidate.kind == "unique" then
		local star = Components.text({ text = "@special", size = 40, color = C.rewardGlow, font = Tokens.font.number })
		star.Position = UDim2.fromOffset(8, 4)
		star.Parent = content
	end
	return frame
end

-- Total の段（D-283）："great"・"amazing"・nil。境目はマスターデータ（K.hireTotalGreat・K.hireTotalAmazing）
function HireCommon.totalTier(total: number): string?
	local K = master.K
	if total >= K.hireTotalAmazing then
		return "amazing"
	end
	if total >= K.hireTotalGreat then
		return "great"
	end
	return nil
end

-- Total の行（HP を除く4項目の合計：Q-006）。左に「Total」、右に段の札・暗い凹みに白い数字・前回との ▲▼
function HireCommon.totalRow(total: number, prevTotal: number?): Frame
	local row: Frame = new("Frame", {
		Name = "Total",
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundColor3 = C.ch75,
		[CHILDREN] = {
			Components.corner(6),
			Components.padding(0, 12, 0, 12),
		},
	})
	local stroke = Components.stroke(C.ctaGoldLow, 3, 1)
	stroke.Name = "TierStroke"
	stroke.Parent = row
	local label = Components.text({
		text = Words.total,
		size = Tokens.text.body,
		color = C.inkDark,
		font = Tokens.font.display,
		xAlign = Enum.TextXAlignment.Left,
	})
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.fromScale(0, 0.5)
	label.Parent = row
	local right: Frame = new("Frame", {
		Name = "Right",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		[CHILDREN] = {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 12),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = row,
	})
	-- 段の札（Great・Amazing）。段がなければ隠す
	local tag: Frame = new("Frame", {
		Name = "Tier",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ctaGoldRim,
		Visible = false,
		[CHILDREN] = { Components.corner(18), Components.padding(0, 14, 0, 14) },
		Parent = right,
	})
	local tagText =
		Components.text({ text = "", size = 21, color = C.inkWhite, font = Tokens.font.display, stroke = true })
	tagText.Name = "Word"
	tagText.Size = UDim2.fromOffset(0, 36)
	tagText.Parent = tag
	-- 数字は暗い凹みに白（D-222 ⑨）
	local well: Frame = new("Frame", {
		Name = "Well",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(96, 38),
		BackgroundColor3 = C.ch13,
		[CHILDREN] = { Components.corner(6) },
		Parent = right,
	})
	local value = Components.text({
		text = tostring(total),
		size = Tokens.text.body,
		color = C.inkWhite,
		font = Tokens.font.number,
	})
	value.Name = "Value"
	value.AutomaticSize = Enum.AutomaticSize.None
	value.Size = UDim2.fromScale(1, 1)
	value.Parent = well
	if prevTotal then
		-- 前回との差（各行と同じ ▲▼：D-220 の S-21d）
		local d = total - prevTotal
		local txt = if d > 0
			then Components.plain(Components.icon.up) .. d
			elseif d < 0 then Components.plain(Components.icon.down) .. -d
			else ""
		local delta = Components.text({
			text = txt,
			size = Tokens.text.body,
			color = if d >= 0 then C.up else C.warn,
			font = Tokens.font.number,
			xAlign = Enum.TextXAlignment.Left,
		})
		delta.Name = "Delta"
		delta.LayoutOrder = 3
		delta.AutomaticSize = Enum.AutomaticSize.None
		delta.Size = UDim2.fromOffset(64, 30)
		delta.Parent = right
	end
	return row
end

-- Total の行の見た目を段に合わせる（total が nil なら「?」で段なし。面接で決まる前）
function HireCommon.paintTotal(row: Frame, total: number?)
	local tier = if total then HireCommon.totalTier(total) else nil
	row.BackgroundColor3 = if tier then C.rewardGlow else C.ch75
	local stroke = row:FindFirstChild("TierStroke") :: UIStroke?
	if stroke then
		stroke.Transparency = if tier then 0 else 1
		stroke.Color = if tier == "amazing" then C.ctaGoldRim else C.ctaGoldLow
		stroke.Thickness = if tier == "amazing" then 4 else 3
	end
	local tag = row:FindFirstChild("Tier", true) :: Frame?
	if tag then
		tag.Visible = tier ~= nil
		local word = tag:FindFirstChild("Word")
		if word and tier then
			Components.setParts(
				word,
				if tier == "amazing" then { Components.icon.star, Words.amazing } else { Words.great }
			)
		end
	end
	local value = row:FindFirstChild("Value", true) :: TextLabel?
	if value then
		value.Text = if total then tostring(total) else "?"
	end
end

export type StatPanel = {
	frame: Frame,
	content: Frame,
	rows: { [string]: Frame },
	total: Frame, -- Total の行（D-283）
	totalValue: TextLabel, -- Total の数字（面接でカウントアップする）
	footer: Frame,
}

-- 能力の面（題の札＝名前、5行、Total、下に Cancel の段）
-- hideTotal：Total を「?」で出す（面接で最後に決めて見せる）
function HireCommon.statPanel(parent: Frame, candidate: any, roll: any, prev: any?, hideTotal: boolean?): StatPanel
	local band = Root.bandBottom()
	local job = master.jobs[candidate.jobId]
	local frame, content = Components.panel({
		size = UDim2.fromOffset(700, 448),
		position = UDim2.new(1, -40, 0, band + 44),
		anchor = Vector2.new(1, 0),
		title = candidate.name,
	})
	frame.Name = "Stats"
	frame.Parent = parent
	new("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = content,
	})
	-- 職業とギフトの小さな札（題の札の右）
	local tags: Frame = new("Frame", {
		Name = "Tags",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -90, 0, 0),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		ZIndex = 8,
		[CHILDREN] = {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
		},
		Parent = frame,
	})
	local function tag(text: string)
		local t: Frame = new("Frame", {
			Size = UDim2.fromOffset(0, 36),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.ch13,
			ZIndex = 8,
			[CHILDREN] = {
				Components.corner(18),
				Components.padding(0, 12, 0, 12),
			},
			Parent = tags,
		})
		local l = Components.text({
			text = if type(text) == "string" then text else "",
			size = 21,
			color = C.inkLight,
			font = Tokens.font.bodyStrong,
		})
		l.Size = UDim2.fromOffset(0, 36)
		if type(text) == "table" then
			Components.setParts(l, text)
		end
		l.ZIndex = 9
		l.Parent = t
	end
	tag({
		if job and job.attackType == "magic" then "@job_magic" else "@job_physical",
		if job then job.nameEn else candidate.jobId,
	})
	for _, g in candidate.giftIds or {} do
		local gift = master.gifts[g]
		tag(if gift then gift.nameEn else g)
	end

	local range = master.K.hireStatRange
	local marks = HireCommon.growthMarks(candidate.jobId)
	local attack = HireCommon.attackStat(candidate.jobId)
	local rows: { [string]: Frame } = {}
	-- ▲ の列の見出し（D-288：▲ だけでは伸びやすさと分からなかった）
	local growthHead = Components.statHeader(Words.growth)
	growthHead.LayoutOrder = 0
	growthHead.Parent = content
	for i, s in HireCommon.STATS do
		local r = Components.statRow({
			stat = s.key,
			label = s.label,
			value = roll[s.key],
			min = range[s.key].min,
			max = range[s.key].max,
			big = s.key == attack or s.key == "hp",
			marks = marks[s.key],
			prev = if prev then prev[s.key] else nil,
		})
		r.LayoutOrder = i
		-- Total の行と Growth の見出し（D-288）が入るように 52 → 39（面の高さ 448 のまま。大きい棒 32 は収まる）
		r.Size = UDim2.new(1, 0, 0, 39)
		r.Parent = content
		rows[s.key] = r
	end
	local totalValue = Hiring.total(roll)
	local total = HireCommon.totalRow(totalValue, if prev then Hiring.total(prev) else nil)
	total.LayoutOrder = 8
	total.Parent = content
	HireCommon.paintTotal(total, if hideTotal then nil else totalValue)
	local footer: Frame = new("Frame", {
		Name = "Footer",
		LayoutOrder = 10,
		Size = UDim2.new(1, 0, 0, 70), -- Cancel（高さ 66＋厚み 4）
		BackgroundTransparency = 1,
		Parent = content,
	})
	return {
		frame = frame,
		content = content,
		rows = rows,
		total = total,
		totalValue = total:FindFirstChild("Value", true) :: TextLabel,
		footer = footer,
	}
end

-- 雇った人を入れる先（D-283）：待機中のパーティを 1, 2, … の順に見て、最初の空き枠。なければ nil
function HireCommon.openSlot(view: any): (number?, number?)
	local parties = (view and view.parties) or {}
	for i = 1, #parties do
		local p = parties[i]
		if p and not Party.isBusy(view, i) then
			for slot = 1, Party.SIZE do
				if p.slots[slot] == Party.EMPTY then
					return i, slot
				end
			end
		end
	end
	return nil, nil
end

-- 最初の待機中のパーティ（空き枠がなくても。編成の面を開く先：D-265 ①）
function HireCommon.idleParty(view: any): number?
	local parties = (view and view.parties) or {}
	for i = 1, #parties do
		if parties[i] and not Party.isBusy(view, i) then
			return i
		end
	end
	return nil
end

-- 良い値（範囲の statGoodRatio 以上）・最大値（D-220 の S-21c）
function HireCommon.quality(key: string, value: number): string?
	local r = master.K.hireStatRange[key]
	if value >= r.max then
		return "max"
	end
	if value >= r.min + (r.max - r.min) * master.K.statGoodRatio then
		return "good"
	end
	return nil
end

return HireCommon
