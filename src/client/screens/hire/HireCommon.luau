--!strict
-- 雇用の画面（S-21a〜e、D-220・D-226）で共有する部品。
--   - S-21c・d・e は同じ配置：左に肖像の枠（460×486）、右に能力の面（700×448、題の札＝名前、下に Cancel の段）。
--   - 絵は仮（バストアップの代わりの枠。D-227 ②）。

local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Root = require("../../ui/Root")
local Screen = require("../Screen")
local Tokens = require("../../ui/Tokens")
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
	if candidate and candidate.kind == "unique" then
		local star = Components.text({ text = "★", size = 40, color = C.rewardGlow, font = Tokens.font.number })
		star.Position = UDim2.fromOffset(8, 4)
		star.Parent = content
	end
	return frame
end

export type StatPanel = {
	frame: Frame,
	content: Frame,
	rows: { [string]: Frame },
	footer: Frame,
}

-- 能力の面（題の札＝名前、5行、下に Cancel の段）
function HireCommon.statPanel(parent: Frame, candidate: any, roll: any, prev: any?): StatPanel
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
		local l = Components.text({ text = text, size = 21, color = C.inkLight, font = Tokens.font.bodyStrong })
		l.Size = UDim2.fromOffset(0, 36)
		l.ZIndex = 9
		l.Parent = t
	end
	tag((if job and job.attackType == "magic" then "◈ " else "⚔ ") .. (if job then job.nameEn else candidate.jobId))
	for _, g in candidate.giftIds or {} do
		local gift = master.gifts[g]
		tag(if gift then gift.nameEn else g)
	end

	local range = master.K.hireStatRange
	local marks = HireCommon.growthMarks(candidate.jobId)
	local attack = HireCommon.attackStat(candidate.jobId)
	local rows: { [string]: Frame } = {}
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
		r.Size = UDim2.new(1, 0, 0, 52)
		r.Parent = content
		rows[s.key] = r
	end
	local footer: Frame = new("Frame", {
		Name = "Footer",
		LayoutOrder = 10,
		Size = UDim2.new(1, 0, 0, 76),
		BackgroundTransparency = 1,
		Parent = content,
	})
	return { frame = frame, content = content, rows = rows, footer = footer }
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
