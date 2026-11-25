--!strict
-- S-31c・d 演出つきの宝箱を1つずつ明かす（D-089・D-144・D-223 ③）。
--   1拍目（溜め）：宝箱と光。上に何個目かの★、下にレアリティの形が1段ずつ上がる。ボタンなし（触ると速まる・長押しで飛ばす）。
--     本番の演出（予告・擬似連・カットインなど）は M8-FX（D-140〜D-147）。途中で実際より上の格は見せない（D-141）。
--   2拍目（明かす）：左に品のカード（レアリティの形と色・名前・グレード・比べる値・修飾語、保護のピン）。
--     右に「誰が強くなるか」（バストアップ・名前の札・比べる値の行）。Equip が金、次の宝箱が茶（D-223 ③）。
--     強くなる人がいなければ品のカードだけ。強くなる人が探索中なら Equip は押せない（05章 §5）。
--   × は残りを飛ばして結果へ。

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local ChestCommon = require("./ChestCommon")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Formulas = require("@game/ReplicatedStorage/Core/Formulas")
local Nav = require("../../ui/Nav")
local Root = require("../../ui/Root")
local Screen = require("../Screen")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local Guide = require("../../hub/Guide")
local Words = require("../../ui/Words")
local Upgrades = require("../../chest/Upgrades")
local master = require("../../Master")

local C = Tokens.color
local I = ChestCommon.icon
local new = Create.new
local CHILDREN = Create.Children

-- 仮の時間（本番の値は M8-FX で決めてマスターデータへ：D-143・D-144）
local STEP = 0.35 -- レアリティの形が1段上がる秒
local HOLD_SKIP = 0.6

-- 品のカード
local function itemCard(parent: Frame, item: any, x: number, band: number, onPin: () -> ()): Frame
	local color = ChestCommon.rarityColor(item.rarity)
	local card, content = Components.panel({
		size = UDim2.fromOffset(460, 486),
		position = UDim2.fromOffset(x, band + 16),
	})
	card.Name = "ItemCard"
	card.Parent = parent
	Components.stroke(color, 3).Parent = card
	new("UIListLayout", {
		Padding = UDim.new(0, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = content,
	})
	-- レアリティの形（色だけで分けない）
	local shapes = Components.text({
		text = ChestCommon.rarityShape(item.rarity),
		size = 40,
		color = color,
		font = Tokens.font.number,
	})
	shapes.LayoutOrder = 1
	shapes.Parent = content
	-- 絵（仮）と保護のピン
	local art: Frame = new("Frame", {
		Name = "Art",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 220),
		BackgroundColor3 = C.ch52,
		[CHILDREN] = { Components.corner(6) },
		Parent = content,
	})
	local g = Components.text({
		text = if master.equipmentBases[item.baseId].slot == "weapon" then I.sword else I.armor,
		size = 40,
		color = C.inkDark,
		font = Tokens.font.number,
	})
	g.AutomaticSize = Enum.AutomaticSize.None
	g.Size = UDim2.fromScale(1, 1)
	g.Parent = art
	local pin: TextButton = new("TextButton", {
		Name = "Pin",
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(66, 66),
		BackgroundColor3 = if item.locked then C.selAmber else C.ch28,
		ZIndex = 5,
		[CHILDREN] = { Components.corner(33), Components.stroke(C.bronze, 3) },
		Parent = art,
	})
	local pinGlyph = Components.text({
		text = I.pin,
		size = 30,
		color = if item.locked then C.inkDark else C.inkLight,
		font = Tokens.font.number,
	})
	pinGlyph.AutomaticSize = Enum.AutomaticSize.None
	pinGlyph.Size = UDim2.fromScale(1, 1)
	pinGlyph.ZIndex = 6
	pinGlyph.Parent = pin
	pin.Activated:Connect(onPin)
	-- 名前とグレード
	local name = Components.text({
		text = ChestCommon.itemName(item) .. (if item.grade > 0 then "  +" .. item.grade else ""),
		size = 30,
		color = C.inkDark,
		font = Tokens.font.display,
	})
	name.LayoutOrder = 3
	name.Parent = content
	-- 比べる値と修飾語
	local stats: Frame = new("Frame", {
		LayoutOrder = 4,
		Size = UDim2.fromOffset(0, 56),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		[CHILDREN] = {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 14),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = content,
	})
	local value = Formulas.bulkSellValue(item, master)
	if value then
		local c = Components.chip(
			if master.equipmentBases[item.baseId].slot == "weapon" then I.sword else I.armor,
			tostring(value),
			C.bronzeHi
		)
		c.LayoutOrder = 1
		c.Parent = stats
	end
	if item.modifierId and item.modifierValue then
		local mv = item.modifierValue
		local text = if mv < 1 then "+" .. math.floor(mv * 100 + 0.5) .. "%" else "+" .. mv
		local c = Components.chip("◆", text, C.bronzeHi)
		c.LayoutOrder = 2
		c.Parent = stats
	end
	return card
end

local function build(params: any?, api: Nav.Api): Nav.Built
	local p = params :: any
	local batch: ChestCommon.Batch = p.batch
	local index: number = p.index
	local res = batch.special[index]
	local band = Root.bandBottom()
	local frame = Screen.scene("ChestReveal")
	local alive = true

	local function goNext()
		if index < #batch.special then
			api.replace("ChestReveal", { batch = batch, index = index + 1 })
		else
			api.replace("ChestResults", { batch = batch })
		end
	end
	local close = Screen.closeTopRight(frame, function()
		api.replace("ChestResults", { batch = batch })
	end)

	-- 1拍目：溜め
	local buildUp: Frame = new("Frame", {
		Name = "BuildUp",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	-- 何個目か（★の列。溜めの間だけ）
	local pips: Frame = new("Frame", {
		Name = "Pips",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, band + 12),
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		ZIndex = 8,
		[CHILDREN] = {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 14),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = buildUp,
	})
	for i = 1, #batch.special do
		local on = i == index
		local pip: Frame = new("Frame", {
			LayoutOrder = i,
			Size = UDim2.fromOffset(44, 44),
			BackgroundColor3 = if on then C.ch16 else C.ch13,
			ZIndex = 8,
			[CHILDREN] = { Components.corner(22), Components.stroke(if on then C.selAmber else C.ch28, 3) },
			Parent = pips,
		})
		local s = Components.text({
			text = "★",
			size = 23,
			color = if i < index then C.ch45 elseif on then C.rewardGlow else C.ch28,
			font = Tokens.font.number,
		})
		s.AutomaticSize = Enum.AutomaticSize.None
		s.Size = UDim2.fromScale(1, 1)
		s.ZIndex = 9
		s.Parent = pip
	end

	local halo: Frame = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, band + 294),
		Size = UDim2.fromOffset(460, 460),
		BackgroundColor3 = C.rewardGlow,
		BackgroundTransparency = 0.85,
		[CHILDREN] = { Components.corner(230) },
		Parent = buildUp,
	})
	local chest = Components.text({ text = I.chest, size = 40, color = C.ch28, font = Tokens.font.number })
	chest.AutomaticSize = Enum.AutomaticSize.None
	chest.AnchorPoint = Vector2.new(0.5, 0.5)
	chest.Position = UDim2.new(0.5, 0, 0, band + 294)
	chest.Size = UDim2.fromOffset(300, 300)
	chest.TextScaled = true
	chest.TextColor3 = C.bronzeHi
	chest.Parent = buildUp
	local steps: Frame = new("Frame", {
		Name = "Steps",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, band + 512),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		[CHILDREN] = {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 16),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = buildUp,
	})

	-- 2拍目：明かす
	local revealed: Frame = new("Frame", {
		Name = "Revealed",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = frame,
	})
	local function showReveal()
		buildUp.Visible = false
		revealed.Visible = true
		revealed:ClearAllChildren() -- ピンを押したら作り直す
		local view = Session.view
		local uid = res.equipmentUids[1]
		local item = if uid then view.equipment[uid] else nil
		local actions = Screen.actionRow(revealed)
		-- 強くなる人がいて装備できるときは Equip が金・次が茶。それ以外は次が金（右下のメイン：D-219 ③）
		local equipable = false
		local uid0 = res.equipmentUids[1]
		local item0 = if uid0 then view.equipment[uid0] else nil
		local best0 = if item0 then Upgrades.forItem(view, item0.uid, master, ChestCommon.deps)[1] else nil
		if best0 and not ChestCommon.isBusy(view, best0.advUid) then
			equipable = true
		end
		local nextButton = Components.button({
			kind = if equipable then "brown" else "gold",
			width = if equipable then 160 else 320,
			height = if equipable then 66 else nil,
			icon = I.next,
			label = Words.next
				.. (if index < #batch.special then " " .. string.rep("●", #batch.special - index) else ""),
			name = "Next",
			glyph = if equipable then "X" else "A",
			onClick = goNext,
		})
		nextButton.LayoutOrder = 1
		if item == nil then
			-- 自動売却された・素材だけ・ゴールドだけの宝箱（D-167）
			local gold = (res.gold or 0) + (res.soldItemsGold or 0) + (res.autoSoldGold or 0)
			local chip = Components.chip(I.gold, "+" .. gold)
			chip.AnchorPoint = Vector2.new(0.5, 0.5)
			chip.Position = UDim2.new(0.5, 0, 0, band + 294)
			chip.Parent = revealed
			nextButton.Parent = actions
			return
		end
		local function onPin()
			Session.sendAndWait({ type = "SetLock", uid = item.uid, locked = not item.locked })
			showReveal()
		end
		nextButton.Parent = actions
		local best = Upgrades.forItem(view, item.uid, master, ChestCommon.deps)[1]
		if best == nil then
			-- 強くなる人がいない：品のカードだけ（真ん中）
			itemCard(revealed, item, 410, band, onPin)
			return
		end
		itemCard(revealed, item, 40, band, onPin)
		local adv = view.adventurers[best.advUid]
		local job = master.jobs[adv.jobId]
		local panel, content = Components.panel({
			size = UDim2.fromOffset(700, 448),
			position = UDim2.new(1, -40, 0, band + 44),
			anchor = Vector2.new(1, 0),
			title = adv.name,
		})
		panel.Name = "WhoGetsStronger"
		panel.Parent = revealed
		local bust = ChestCommon.bust(Vector2.new(230, 380), adv.appearanceId)
		bust.Position = UDim2.fromOffset(0, 6)
		bust.Parent = content
		local busy = ChestCommon.isBusy(view, adv.uid)
		if busy then
			local chip = Components.chip("▶", "", C.bronzeHi)
			chip.AnchorPoint = Vector2.new(0.5, 1)
			chip.Position = UDim2.new(0.5, 0, 1, -8)
			chip.Parent = bust
		end
		-- 職業と Lv の札
		local tags =
			Components.chip(if job and job.attackType == "magic" then "◈" else "⚔", "Lv " .. adv.level, C.inkLight)
		tags.AnchorPoint = Vector2.new(1, 0.5)
		tags.Position = UDim2.new(1, -96, 0, 0) -- 右上の × を避ける
		tags.ZIndex = 8
		tags.Parent = panel
		local rows: Frame = new("Frame", {
			Name = "Rows",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.new(1, -250, 0, 52),
			BackgroundTransparency = 1,
			Parent = content,
		})
		ChestCommon.compareRow(best.slot, best.value, best.current).Parent = rows
		local equip = Components.button({
			kind = if busy then "disabled" else "gold",
			width = 320,
			icon = I.equip,
			label = Words.equip,
			name = "Equip",
			glyph = "A",
			onClick = function()
				local r = Session.sendAndWait({ type = "Equip", adventurerUid = adv.uid, equipmentUid = item.uid })
				if r and r.ok then
					Guide.done("equip")
					goNext()
				end
			end,
		})
		equip.LayoutOrder = 2
		equip.Parent = actions
		Guide.mark(equip, Guide.is("equip"), 18, true) -- 初回の誘導：Equip（最後の段）
	end

	-- 触ると速まる・長押しで飛ばす（溜めの間だけ）
	local speed, skip, holding = 1, false, false
	local tap: TextButton = new("TextButton", {
		Name = "SpeedUp",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Parent = buildUp,
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
		if input.KeyCode == Enum.KeyCode.ButtonX and buildUp.Visible then
			skip = true
		end
	end)
	close.ZIndex = 30

	task.spawn(function()
		-- レアリティの形を1段ずつ（最後が実際のレアリティ。降格しない：D-141）
		for rank = 1, res.rank or 1 do
			if not alive then
				return
			end
			local s = Components.text({
				text = ChestCommon.rarityShape(rank),
				size = 34,
				color = ChestCommon.rarityColor(rank),
				font = Tokens.font.number,
			})
			s.LayoutOrder = rank
			s.Parent = steps
			halo.BackgroundColor3 = ChestCommon.rarityColor(rank)
			TweenService:Create(chest, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), {
				Rotation = if rank % 2 == 0 then 4 else -4,
			}):Play()
			if not skip then
				task.wait(STEP / speed)
			end
		end
		task.wait(if skip then 0.05 else 0.3 / speed)
		if alive then
			showReveal()
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

Nav.register("ChestReveal", build)

return {}
