--!strict
-- 転生の画面（S-43a〜d、D-224・D-230）で共有する部品。雇用の S-21c・d・e と同じ配置（左に肖像、右に能力の面）。
--   - 能力の棒：長さ＝引き継ぐ分＋加算分の上限。引き継ぐ分（くすんだ茶と ▼）、加算分（暖かい色）、残りの余地（縁だけ）。
--     数字は棒の中に白で1つ（S-43a は引き継ぐ値、S-43b 以降は転生後の値）。差は加算分の ▲▼（v3 の決め事）。
--   - 良い値は上限の statGoodRatio 以上、特別な演出は rebirthGreatRatio 以上（07章・D-224）。

local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local HireCommon = require("../hire/HireCommon")
local Party = require("@game/ReplicatedStorage/Core/Party")
local Rebirth = require("@game/ReplicatedStorage/Core/Rebirth")
local Root = require("../../ui/Root")
local Tokens = require("../../ui/Tokens")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local RebirthCommon = {}

RebirthCommon.STATS = HireCommon.STATS
RebirthCommon.portrait = HireCommon.portrait
RebirthCommon.icon = {
	rebirth = "@rebirth", -- 転生回数の札
	inherit = "@inherit", -- 引き継ぐ分の印
	keep = "@look_keep", -- 形見のロケット（前の姿に戻す：D-255）
	train = "@train",
}

local STAT_COLOR = {
	str = C.statStr,
	mag = C.statMag,
	agi = C.statAgi,
	dex = C.statDex,
	hp = C.statHp,
}

-- 決まっていく順：関係の薄い能力 → HP → 攻撃に使う能力（最後が山場：v3 の決め事）
function RebirthCommon.chargeOrder(jobId: string): { string }
	local attack = HireCommon.attackStat(jobId)
	local out = {}
	for _, s in RebirthCommon.STATS do
		if s.key ~= attack and s.key ~= "hp" then
			table.insert(out, s.key)
		end
	end
	table.insert(out, "hp")
	table.insert(out, attack)
	return out
end

-- 加算分の出来（"great"＝特別、"good"＝良い）
function RebirthCommon.quality(bonus: number, bonusMax: number): string?
	if bonusMax <= 0 then
		return nil
	end
	local r = bonus / bonusMax
	if r >= master.K.rebirthGreatRatio then
		return "great"
	end
	if r >= master.K.statGoodRatio then
		return "good"
	end
	return nil
end

-- 転生の見込み（始める前の画面用）：引き継ぐ分と加算分の上限
function RebirthCommon.preview(adv: any): any
	return {
		inherited = Rebirth.inherited(adv.baseStats),
		bonusMax = Rebirth.bonusMax(adv.baseStats, master),
	}
end

-- 転生できない理由（S-43a の札）。nil なら押せる
function RebirthCommon.blockReason(view: any, adv: any): string?
	if Party.isAdventurerBusy(view, adv.uid) then
		return "BUSY"
	end
	local err = Rebirth.canRebirth(adv, master)
	if err then
		return err
	end
	if view.gold < Rebirth.cost(adv, master) then
		return "NOT_ENOUGH_GOLD"
	end
	return nil
end

function RebirthCommon.cost(adv: any): number
	return Rebirth.cost(adv, master)
end

export type Row = {
	frame: Frame,
	bonusFill: Frame,
	number: TextLabel,
	delta: TextLabel,
	total: number,
}

export type RowProps = {
	stat: string,
	label: string,
	inherited: number,
	bonusMax: number,
	bonus: number?, -- nil＝まだ決まっていない（S-43a）
	prevBonus: number?, -- 前回の加算分（S-43c：目盛りと差）
	big: boolean?,
}

-- 能力の行（アイコン・表記・棒・差）
function RebirthCommon.row(p: RowProps): Row
	local row: Frame = new("Frame", {
		Name = "Stat_" .. p.stat,
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = C.ch75,
		[CHILDREN] = { Components.corner(6) },
	})
	new("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = STAT_COLOR[p.stat] or C.inkMid,
		[CHILDREN] = { Components.corner(15), Components.stroke(C.inkDark, 2) },
		Parent = row,
	})
	local label = Components.text({
		text = p.label,
		size = Tokens.text.body,
		color = C.inkDark,
		font = Tokens.font.number,
		xAlign = Enum.TextXAlignment.Left,
	})
	label.AutomaticSize = Enum.AutomaticSize.None
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, 54, 0.5, 0)
	label.Size = UDim2.fromOffset(64, 30)
	label.Parent = row
	local barH = if p.big then Tokens.size.barHLg else Tokens.size.barH
	local track: Frame = new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 126, 0.5, 0),
		Size = UDim2.new(1, -(126 + 88), 0, barH),
		BackgroundColor3 = C.barTrack,
		ClipsDescendants = true,
		[CHILDREN] = { Components.corner(Tokens.radius.radiusBar) },
		Parent = row,
	})
	local total = math.max(1, p.inherited + p.bonusMax)
	local inhFrac = p.inherited / total
	-- 引き継ぐ分（くすんだ茶と ▼）
	local inh: Frame = new("Frame", {
		Name = "Inherited",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(inhFrac, -2, 1, -4),
		BackgroundColor3 = C.ch45,
		[CHILDREN] = { Components.corner(6) },
		Parent = track,
	})
	local mark =
		Components.text({ text = RebirthCommon.icon.inherit, size = 15, color = C.ch16, font = Tokens.font.number })
	mark.AnchorPoint = Vector2.new(1, 0.5)
	mark.Position = UDim2.new(1, -4, 0.5, 0)
	mark.Parent = inh
	-- 加算分の余地（縁だけ）
	new("Frame", {
		Name = "Room",
		Position = UDim2.new(inhFrac, 0, 0, 2),
		Size = UDim2.new(1 - inhFrac, -2, 1, -4),
		BackgroundTransparency = 1,
		[CHILDREN] = { Components.corner(6), Components.stroke(C.bronzeHi, 2, 0.4) },
		Parent = track,
	})
	-- 加算分
	local bonus = p.bonus or 0
	local bonusFill: Frame = new("Frame", {
		Name = "Bonus",
		Position = UDim2.new(inhFrac, 0, 0, 2),
		Size = UDim2.new(bonus / total, 0, 1, -4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 2,
		[CHILDREN] = { Components.corner(6), Components.gradient(C.barFill, C.barFillLow) },
		Parent = track,
	})
	if p.prevBonus then
		new("Frame", {
			Name = "PrevTick",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale((p.inherited + p.prevBonus) / total, 0),
			Size = UDim2.new(0, 4, 1, 0),
			BackgroundColor3 = C.inkLight,
			ZIndex = 3,
			Parent = track,
		})
	end
	local num = Components.text({
		text = tostring(p.inherited + bonus),
		size = 23,
		color = C.inkWhite,
		font = Tokens.font.number,
		stroke = true,
	})
	num.AutomaticSize = Enum.AutomaticSize.None
	num.Size = UDim2.fromScale(1, 1)
	num.ZIndex = 4
	num.Parent = track
	local d = if p.prevBonus and p.bonus then p.bonus - p.prevBonus else 0
	local delta = Components.text({
		text = if d > 0
			then Components.plain(Components.icon.up) .. d
			elseif d < 0 then Components.plain(Components.icon.down) .. -d
			else "",
		size = Tokens.text.body,
		color = if d >= 0 then C.up else C.warn,
		font = Tokens.font.number,
		xAlign = Enum.TextXAlignment.Left,
	})
	delta.AutomaticSize = Enum.AutomaticSize.None
	delta.AnchorPoint = Vector2.new(1, 0.5)
	delta.Position = UDim2.new(1, -8, 0.5, 0)
	delta.Size = UDim2.fromOffset(72, 30)
	delta.Parent = row
	return { frame = row, bonusFill = bonusFill, number = num, delta = delta, total = total }
end

export type Panel = {
	frame: Frame,
	content: Frame,
	rows: { [string]: Row },
	footer: Frame,
}

-- 能力の面（題の札＝名前、職業と転生回数の札、5行、下の段）
function RebirthCommon.statPanel(
	parent: Frame,
	adv: any,
	data: any, -- { inherited, bonusMax }
	bonus: any?, -- 加算分（nil＝まだ）
	prevBonus: any?,
	rebirthCount: number?
): Panel
	local band = Root.bandBottom()
	local job = master.jobs[adv.jobId]
	local frame, content = Components.panel({
		size = UDim2.fromOffset(700, 448),
		position = UDim2.new(1, -40, 0, band + 44),
		anchor = Vector2.new(1, 0),
		title = adv.name,
	})
	frame.Name = "Stats"
	frame.Parent = parent
	new("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = content,
	})
	local tags = Components.chip(
		if job and job.attackType == "magic" then "@job_magic" else "@job_physical",
		(if job then job.nameEn else adv.jobId)
			.. "   "
			.. Components.plain(RebirthCommon.icon.rebirth)
			.. " "
			.. tostring(rebirthCount or adv.rebirthCount),
		C.inkLight
	)
	tags.Name = "Tags"
	tags.AnchorPoint = Vector2.new(1, 0.5)
	tags.Position = UDim2.new(1, -96, 0, 0) -- 右上の × を避ける
	tags.ZIndex = 8
	tags.Parent = frame
	local attack = HireCommon.attackStat(adv.jobId)
	local rows: { [string]: Row } = {}
	for i, s in RebirthCommon.STATS do
		local r = RebirthCommon.row({
			stat = s.key,
			label = s.label,
			inherited = data.inherited[s.key],
			bonusMax = data.bonusMax[s.key],
			bonus = if bonus then bonus[s.key] else nil,
			prevBonus = if prevBonus then prevBonus[s.key] else nil,
			big = s.key == attack or s.key == "hp",
		})
		r.frame.LayoutOrder = i
		r.frame.Parent = content
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

-- 途中から開く（D-131）：見た目の選択が残っていれば S-43d、転生スロットの途中なら S-43c、なければ S-43a
function RebirthCommon.entry(view: any, advUid: string?): (string, any?)
	if view.rebirthAppearance then
		return "RebirthDone", { uid = view.rebirthAppearance.adventurerUid, resume = true }
	end
	if view.rebirthSession then
		return "RebirthCompare", nil
	end
	return "RebirthRitual", { uid = advUid }
end

return RebirthCommon
