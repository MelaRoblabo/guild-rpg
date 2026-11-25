--!strict
-- S-31a 開封中（D-089・D-223 ③）。ボタンを置かない（触ると速まる・長押しで飛ばす：D-218 ④）。
--   - 上に進み具合の棒。左の箱の列で宝箱が開いていき、演出なしの品は下の受け皿（装備・自動売却・ゴールド）に流れる。
--   - 演出つきの宝箱は右の取り置きの列へ（開けるまでレアリティは見せない：D-087）。
--   - 終わったら、演出つきがあれば明かす画面（S-31c・d）へ、なければ結果（S-31b+e）へ。
--   - 本番の演出（先読み・保留変化など）は M8-FX（D-140〜D-147）。ここは仮の短い動き。

local UserInputService = game:GetService("UserInputService")

local ChestCommon = require("./ChestCommon")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Art = require("../../ui/Art")
local HubState = require("../../hub/HubState")
local Nav = require("../../ui/Nav")
local Root = require("../../ui/Root")
local Screen = require("../Screen")
local Tokens = require("../../ui/Tokens")

local C = Tokens.color
local I = ChestCommon.icon
local new = Create.new
local CHILDREN = Create.Children

-- 仮の時間（本番の値は M8-FX で決めてマスターデータへ：D-143）
local PER_CHEST = 0.05 -- 1箱あたりの秒
local MAX_TOTAL = 2.5 -- 全部を開ける秒の上限
local HOLD_SKIP = 0.6 -- 長押しで飛ばすまでの秒
local CELLS = 40 -- 箱の列に並べる数

local function build(params: any?, api: Nav.Api): Nav.Built
	local batch: ChestCommon.Batch = (params :: any).batch
	local band = Root.bandBottom()
	local frame = Screen.scene("ChestOpening")

	local function finish()
		if #batch.special > 0 then
			api.replace("ChestReveal", { batch = batch, index = 1 })
		else
			api.replace("ChestResults", { batch = batch })
		end
	end

	-- 進んでいる間の × は薄く（介入しない。押すと最後まで飛ばす）
	local close = Screen.closeTopRight(frame, function()
		api.replace("ChestResults", { batch = batch })
	end)
	close.BackgroundTransparency = 0.5

	-- 進み具合の棒
	local progress: Frame = new("Frame", {
		Name = "Progress",
		Position = UDim2.fromOffset(270, band + 12),
		Size = UDim2.fromOffset(400, 20),
		BackgroundColor3 = C.barTrack,
		ZIndex = 8,
		[CHILDREN] = { Components.corner(8) },
		Parent = frame,
	})
	local progressFill: Frame = new("Frame", {
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(0, 0, 1, -4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 9,
		[CHILDREN] = { Components.corner(6), Components.gradient(C.barFill, C.barFillLow) },
		Parent = progress,
	})

	-- 左：箱の列
	local grid, gridContent = Components.panel({
		size = UDim2.new(1, -(40 + 24 + 316 + 40), 0, 424), -- 横に広い端末では箱の列が伸びる
		position = UDim2.fromOffset(40, band + 44),
		dark = true,
	})
	grid.Name = "Grid"
	grid.Parent = frame
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(74, 82),
		CellPadding = UDim2.fromOffset(8, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = gridContent,
	})
	local cells: { Frame } = {}
	local all = {}
	for _, r in batch.normal do
		table.insert(all, r)
	end
	for _, r in batch.special do
		table.insert(all, r)
	end
	table.sort(all, function(a, b)
		return (a.order or 0) < (b.order or 0)
	end)
	for i = 1, math.min(#all, CELLS) do
		local cell: Frame = new("Frame", {
			Name = "Cell" .. i,
			LayoutOrder = i,
			BackgroundColor3 = C.ch16,
			[CHILDREN] = { Components.corner(10), Components.stroke(C.ch28, 2) },
			Parent = gridContent,
		})
		local glyph = Components.text({ text = I.chest, size = 40, color = C.ch45, font = Tokens.font.number })
		glyph.Name = "Glyph"
		glyph.AutomaticSize = Enum.AutomaticSize.None
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.Parent = cell
		cells[i] = cell
	end

	-- 右：演出つきの取り置き
	local aside, asideContent = Components.panel({
		size = UDim2.fromOffset(316, 424),
		position = UDim2.new(1, -40, 0, band + 44),
		anchor = Vector2.new(1, 0),
		dark = true,
	})
	aside.Name = "SetAside"
	aside.Parent = frame
	new("UIListLayout", {
		Padding = UDim.new(0, 22),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = asideContent,
	})
	local asideCount = 0
	local asideMore: TextLabel? = nil
	local function setAside()
		asideCount += 1
		if asideCount <= 3 then
			local tile: Frame = new("Frame", {
				Name = "Special" .. asideCount,
				LayoutOrder = asideCount,
				Size = UDim2.fromOffset(150, 96),
				Rotation = if asideCount % 2 == 0 then 3 else -3,
				BackgroundColor3 = C.ch28,
				[CHILDREN] = { Components.corner(14), Components.stroke(C.rewardGlow, 3) },
				Parent = asideContent,
			})
			local g = Components.text({ text = I.chest, size = 40, color = C.rewardGlow, font = Tokens.font.number })
			g.AutomaticSize = Enum.AutomaticSize.None
			g.Size = UDim2.fromScale(1, 1)
			g.Parent = tile
		else
			if asideMore == nil then
				local t = Components.text({ text = "", size = 30, color = C.rewardGlow, font = Tokens.font.number })
				t.LayoutOrder = 10
				t.Parent = asideContent
				asideMore = t
			end
			(asideMore :: TextLabel).Text = "+" .. (asideCount - 3)
		end
	end

	-- 下：受け皿（装備・自動売却・ゴールド）
	local tray: Frame = new("Frame", {
		Name = "Tray",
		Position = UDim2.fromOffset(40, band + 484),
		Size = UDim2.new(1, -80, 0, 106),
		BackgroundColor3 = C.ch10,
		ZIndex = 7,
		[CHILDREN] = {
			Components.corner(16),
			Components.stroke(C.ch16, 3),
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 22),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = frame,
	})
	local function trayChip(icon: string, color: Color3, order: number): TextLabel
		local chip = Components.chip(icon, "0", color)
		chip.LayoutOrder = order
		chip.ZIndex = 8
		chip.Parent = tray
		local label: TextLabel? = nil
		for _, d in chip:GetChildren() do
			if d:IsA("TextLabel") and d.Text == "0" then
				label = d
			end
		end
		return label :: TextLabel
	end
	local itemsText = trayChip(I.sword, C.bronzeHi, 1)
	local soldText = trayChip(I.recycle, C.bronzeHi, 2)
	local goldText = trayChip(I.gold, C.coinGold, 3)
	goldText.TextColor3 = C.numHi

	-- 触ると速まる・長押しで飛ばす（D-218 ④）
	local speed = 1
	local skip = false
	local holding = false
	local tap: TextButton = new("TextButton", {
		Name = "SpeedUp",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20, -- × より下（× は押せる）
		Parent = frame,
	})
	tap.MouseButton1Down:Connect(function()
		speed = 4
		holding = true
		local started = os.clock()
		task.spawn(function()
			while holding and not skip do
				if os.clock() - started >= HOLD_SKIP then
					skip = true
				end
				task.wait()
			end
		end)
	end)
	tap.MouseButton1Up:Connect(function()
		holding = false
	end)
	local inputConn = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.ButtonX then
			skip = true
		end
	end)

	local alive = true
	task.spawn(function()
		local step = math.min(PER_CHEST, MAX_TOTAL / math.max(1, #all))
		local items, sold, gold = 0, 0, 0
		for k, r in all do
			if not alive then
				return
			end
			if r.effect then
				setAside()
			else
				items += #r.equipmentUids
				sold += if r.autoSold then #r.autoSold else 0
			end
			gold += (r.gold or 0) + (r.soldItemsGold or 0) + (r.autoSoldGold or 0)
			local cell = cells[((k - 1) % CELLS) + 1]
			if cell then
				local glyph = cell:FindFirstChild("Glyph") :: TextLabel
				if r.effect then
					cell.BackgroundColor3 = C.ch28
					glyph.TextColor3 = C.rewardGlow
				else
					-- 開けた後なのでレアリティを見せてよい（D-087）
					cell.BackgroundColor3 = C.ch13
					glyph.Text = ChestCommon.rarityShape(r.rank)
					glyph.TextColor3 = ChestCommon.rarityColor(r.rank)
					-- 開いた箱の絵（レアリティごとの箱：D-253）。開ける前は箱の種類を見せない（D-087）
					if Art.put(cell, Art.chest(r.rank, true), { inset = 4 }) then
						glyph.Visible = false
					end
				end
			end
			itemsText.Text = HubState.formatNumber(items)
			soldText.Text = HubState.formatNumber(sold)
			goldText.Text = "+" .. HubState.formatNumber(gold)
			progressFill.Size = UDim2.new(k / #all, -4, 1, -4)
			if not skip then
				task.wait(step / speed)
			end
		end
		task.wait(if skip then 0.1 else 0.4 / speed)
		if alive then
			finish()
		end
	end)

	return {
		frame = frame,
		scrim = 1,
		destroy = function()
			alive = false
			holding = false
			inputConn:Disconnect()
		end,
	}
end

Nav.register("ChestOpening", build)

return {}
