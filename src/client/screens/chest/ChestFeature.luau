--!strict
-- 開封の演出（必ず1箱：D-267）。1回の開封（1箱でも All でも）につき、開けた中で一番良い箱を中央で開ける。
--   フル（3秒以内）：その箱の絵が下から飛んで来て揺れる → ふたが開く（閉じた箱 → 開いた箱の絵：D-262 ②）
--     → 品の絵が飛び出して回り、表になる（枠はレアリティの色、下に名前・レアリティの語・枠の語）。
--   短い版（1秒）：開いた箱から品が出るだけ。設定 Chest opening がオフのとき（D-267 ⑤）。
--   最初の1回は設定にかかわらずフル（D-267 ④）。
--   触ると早送り、長押しで飛ばす、語付きの Skip も置く（D-267 ②）。終わったら少し見せて結果（S-31b+e）へ。
--   演出つきの宝箱（D-089）があるときは明かす画面（ChestReveal）がこの役を兼ねるので、ここは通らない。
--   本番の演出の語彙（先読み・予告など：D-140〜D-147）は M8-FX。ここは「必ず1箱」と「品の絵が飛び出す」の最低限。

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Game = require("@game/ReplicatedStorage/Core/Game")
local ChestCommon = require("./ChestCommon")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Art = require("../../ui/Art")
local Motion = require("../../ui/Motion")
local Nav = require("../../ui/Nav")
local Screen = require("../Screen")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local Words = require("../../ui/Words")
local master = require("../../Master")

local C = Tokens.color
local I = ChestCommon.icon
local new = Create.new
local CHILDREN = Create.Children

local HOLD_SKIP = 0.6 -- 長押しで飛ばすまでの秒
local SHOW_AFTER = 1.2 -- 表になってから結果へ進むまでの秒（触ればすぐ進む）

local SLOT_WORD = { weapon = "Weapon", armor = "Armor", sub = "Accessory" } -- 枠の語（D-268 ④）

-- 一番良い箱：レアリティの高い順。同じなら倉庫に残った装備がある箱、ゴールドの多い箱
local function bestRecord(batch: ChestCommon.Batch, view: any): any?
	local best, bestKey = nil, nil
	for _, r in batch.normal do
		local hasItem = false
		for _, uid in r.equipmentUids or {} do
			if view.equipment[uid] then
				hasItem = true
			end
		end
		local key = r.rank * 1e9 + (if hasItem then 1e8 else 0) + (r.gold or 0)
		if bestKey == nil or key > bestKey then
			best, bestKey = r, key
		end
	end
	return best
end

-- 箱から出す品：倉庫に残った装備のうちレアリティの高いもの
local function bestItem(r: any, view: any): any?
	local best = nil
	for _, uid in r.equipmentUids or {} do
		local it = view.equipment[uid]
		if it and (best == nil or it.rarity > best.rarity) then
			best = it
		end
	end
	return best
end

local function build(params: any?, api: Nav.Api): Nav.Built
	local batch: ChestCommon.Batch = (params :: any).batch
	local frame = Screen.scene("ChestFeature")
	local view = Session.view
	local done = false
	local function toResults()
		if done then
			return
		end
		done = true
		api.replace("ChestResults", { batch = batch })
	end
	Screen.closeTopRight(frame, toResults)
	local rec = if view then bestRecord(batch, view) else nil
	if view == nil or rec == nil then
		task.defer(toResults)
		return { frame = frame, scrim = 1 }
	end
	local item = bestItem(rec, view)
	local prefs = Game.query.preferences(view, master)
	local full = batch.first == true or prefs.chestAnimation ~= false
	local rank = rec.rank

	-- 舞台：中央の箱
	local stage: Frame = new("Frame", {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromOffset(280, 280),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = frame,
	})
	local glow: Frame = new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.4, 1.4),
		BackgroundColor3 = ChestCommon.rarityColor(rank),
		BackgroundTransparency = 1,
		ZIndex = 4,
		[CHILDREN] = { Components.corner(400) },
		Parent = stage,
	})
	local box: Frame = new("Frame", {
		Name = "Box",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = stage,
	})
	local boxArt = Art.put(box, Art.chest(rank, not full), { zIndex = 7 })
	local boxGlyph: TextLabel? = nil
	if boxArt == nil then
		local g = Components.text({
			text = I.chest,
			size = 160,
			color = ChestCommon.rarityColor(rank),
			font = Tokens.font.number,
		})
		g.AutomaticSize = Enum.AutomaticSize.None
		g.Size = UDim2.fromScale(1, 1)
		g.ZIndex = 7
		g.Parent = box
		boxGlyph = g
	end

	-- 出てくる品のカード（最初は隠す）
	local card: Frame = new("Frame", {
		Name = "ItemCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(180, 180),
		BackgroundColor3 = C.ch13,
		Visible = false,
		ZIndex = 10,
		[CHILDREN] = {
			Components.corner(20),
			Components.stroke(ChestCommon.rarityColor(item and item.rarity or rank), 6),
		},
		Parent = stage,
	})
	local cardScale = new("UIScale", { Scale = 0.3, Parent = card })
	if item then
		if not Art.put(card, Art.equip(item), { inset = 12, zIndex = 11 }) then
			local base = master.equipmentBases[item.baseId]
			local g = Components.text({
				text = I[base and base.slot == "armor" and "armor" or "sword"],
				size = 90,
				color = C.inkLight,
				font = Tokens.font.number,
			})
			g.AutomaticSize = Enum.AutomaticSize.None
			g.Size = UDim2.fromScale(1, 1)
			g.ZIndex = 11
			g.Parent = card
		end
	else
		-- 装備が残らなかった箱（ゴールドだけ・自動売却）はゴールド
		local g = Components.text({ text = I.gold, size = 90, color = C.coinGold, font = Tokens.font.number })
		g.AutomaticSize = Enum.AutomaticSize.None
		g.Size = UDim2.fromScale(1, 1)
		g.ZIndex = 11
		g.Parent = card
	end

	-- 名前・レアリティの語・枠の語（表になってから）
	local caption: Frame = new("Frame", {
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.46, 170),
		Size = UDim2.fromOffset(700, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 12,
		[CHILDREN] = {
			new("UIListLayout", {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = frame,
	})
	local rarityRow = master.raw.Rarities[if item then item.rarity else rank]
	local nameText = if item
		then ChestCommon.itemName(item)
		else "Gold +" .. tostring((rec.gold or 0) + (rec.soldItemsGold or 0) + (rec.autoSoldGold or 0))
	local nm = Components.text({
		text = nameText,
		size = Tokens.text.title,
		color = C.inkWhite,
		font = Tokens.font.display,
		stroke = true,
	})
	nm.LayoutOrder = 1
	nm.ZIndex = 13
	nm.Parent = caption
	local sub = {}
	if rarityRow then
		table.insert(sub, rarityRow.nameEn)
	end
	if item then
		local base = master.equipmentBases[item.baseId]
		if base and SLOT_WORD[base.slot] then
			table.insert(sub, SLOT_WORD[base.slot])
		end
	end
	local tag = Components.text({
		text = table.concat(sub, " · "),
		size = Tokens.text.body,
		color = ChestCommon.rarityColor(if item then item.rarity else rank),
		font = Tokens.font.display,
		stroke = true,
	})
	tag.LayoutOrder = 2
	tag.ZIndex = 13
	tag.Parent = caption

	-- 語付きの Skip（D-267 ②）
	local actions = Screen.actionRow(frame)
	local skipBtn = Components.button({
		kind = "brown",
		width = 160,
		height = 66,
		icon = "▶",
		label = Words.skip,
		name = "Skip",
		glyph = "X",
		onClick = toResults,
	})
	skipBtn.Parent = actions

	-- 触ると早送り・長押しで飛ばす
	local fast = false
	local revealed = false
	local holding = false
	local tap: TextButton = new("TextButton", {
		Name = "Tap",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3, -- ボタンと × より下
		Parent = frame,
	})
	tap.MouseButton1Down:Connect(function()
		if revealed then
			toResults()
			return
		end
		fast = true
		holding = true
		local started = os.clock()
		task.spawn(function()
			while holding and not done do
				if os.clock() - started >= HOLD_SKIP then
					toResults()
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
			toResults()
		elseif input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.Return then
			if revealed then
				toResults()
			else
				fast = true
			end
		end
	end)

	local function wait(t: number)
		local left = t
		while left > 0 and not done do
			local dt = task.wait()
			left -= if fast then dt * 6 else dt
		end
	end
	local function tween(obj: Instance, t: number, goal: { [string]: any }, style: Enum.EasingStyle?)
		local tw = TweenService:Create(
			obj,
			TweenInfo.new(if fast then t / 6 else t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			goal
		)
		tw:Play()
		return tw
	end

	task.spawn(function()
		-- 箱の絵が読み込まれるまで少し待つ（最大1秒。間に合わないと何も映らない）
		local t0 = os.clock()
		while boxArt and not boxArt.IsLoaded and os.clock() - t0 < 1 and not done do
			task.wait()
		end
		if full then
			-- 1. 箱が下から飛んで来る（0.45秒）
			box.Position = UDim2.fromScale(0.5, 1.6)
			tween(box, 0.45, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Back)
			wait(0.5)
			-- 2. 揺れる（3回、0.6秒）。レアリティの色の光がにじむ
			tween(glow, 0.6, { BackgroundTransparency = if Motion.reduced() then 0.85 else 0.65 })
			for k = 1, 3 do
				local a = if k % 2 == 0 then -8 else 8
				tween(box, 0.08, { Rotation = a })
				wait(0.1)
				tween(box, 0.08, { Rotation = 0 })
				wait(0.1)
			end
			-- 3. ふたが開く（閉じた箱 → 開いた箱の絵）
			if boxArt then
				boxArt.Image = Art.chest(rank, true) or boxArt.Image
			elseif boxGlyph then
				boxGlyph.Text = Components.plain(I.all)
			end
			Motion.bump(box, 0.12)
			wait(0.15)
		else
			-- 短い版：開いた箱から始める
			glow.BackgroundTransparency = 0.75
			wait(0.15)
		end
		if done then
			return
		end
		-- 4. 品が飛び出して回り、表になる
		card.Visible = true
		card.Rotation = if full then -360 else 0
		tween(card, if full then 0.55 else 0.35, {
			Position = UDim2.fromScale(0.5, 0.05),
			Rotation = 0,
		}, Enum.EasingStyle.Back)
		tween(cardScale, if full then 0.55 else 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(box, 0.4, { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.5, 0.8) })
		wait(if full then 0.55 else 0.35)
		caption.Visible = true
		revealed = true
		wait(if full then SHOW_AFTER else 0.5) -- 短い版は全部で約1秒（D-267 ⑤）
		toResults()
	end)

	return {
		frame = frame,
		scrim = 1,
		destroy = function()
			done = true
			holding = false
			inputConn:Disconnect()
		end,
	}
end

Nav.register("ChestFeature", build)

return {}
