--!strict
-- S-42 装備の選択（D-130・D-218 ③・D-231 ⑤⑭・D-232 ⑥）。問い＝「どれを着ける？」。宝箱の明かす画面の右の面と同じ形。
--   - 上の並んだタブ＝枠（武器・防具・補助）。左＝付けられる倉庫の品だけの一覧（他の人が付けている品は出さない）。
--     一覧の先頭は「外す（空き）」の行。初期の選択は差が一番大きい品。
--   - 補助は種類ごとの値の差（盾＝防御、指輪＝能力、護符＝XP の倍率）。並びは今と同じ種類→指輪→護符（D-232 ⑥）。
--   - 右＝その人の面：変わる値の行だけ。新しい値の棒、白い目盛り＝今の値、右に▲▼（前と今を2枚並べない）。
--   - Equip＝右下の金（人＋剣）。「外す」の行を選んだときはアイコンが「外す」に変わる（D-232 ⑥）。外した品は倉庫へ。

local Formulas = require("@game/ReplicatedStorage/Core/Formulas")
local Inventory = require("@game/ReplicatedStorage/Core/Inventory")
local Party = require("@game/ReplicatedStorage/Core/Party")
local AdvCommon = require("./AdvCommon")
local ChestCommon = require("../chest/ChestCommon")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local EquipChoice = require("../../adventurers/EquipChoice")
local Nav = require("../../ui/Nav")
local Root = require("../../ui/Root")
local Screen = require("../Screen")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local Words = require("../../ui/Words")
local WarehouseCommon = require("../warehouse/WarehouseCommon")
local master = require("../../Master")

local C = Tokens.color
local I = AdvCommon.icon
local new = Create.new
local CHILDREN = Create.Children

local deps = {
	value = Formulas.bulkSellValue,
	canEquip = Inventory.canEquip,
	equipMult = Formulas.equipMult,
	expPct = Formulas.equipExpPct,
	memberDef = Party.memberDef,
	snapshot = Formulas.memberSnapshot,
}

local SLOTS = { "weapon", "armor", "sub" }
local RIGHT_W = 456
local KEY_LABEL = {
	atk = { icon = I.attack, text = "" },
	pdef = { icon = I.pdef, text = "" },
	mdef = { icon = I.mdef, text = "" },
	maxHp = { icon = "", text = "HP" },
	mag = { icon = "", text = "MAG" },
	agi = { icon = "", text = "AGI" },
	dex = { icon = "", text = "DEX" },
	expRate = { icon = "", text = "XP" },
}

local function deltaText(c: EquipChoice.Candidate): (string, Color3)
	if c.ratio then
		if c.ratio >= 1 then
			return string.format("XP ▲×%.2f", c.ratio), C.up
		end
		return string.format("XP ▼×%.2f", c.ratio), C.warn
	end
	if c.delta > 0 then
		return "▲" .. c.delta, C.up
	elseif c.delta < 0 then
		return "▼" .. -c.delta, C.warn
	end
	return "", C.inkMid
end

local function build(params: any?, api: Nav.Api): Nav.Built
	local uid = (params :: any).uid
	local tab = (params :: any).slot or "weapon"
	local band = Root.bandBottom()
	local frame = Screen.scene("EquipSelect")
	Screen.closeTopRight(frame, api.close)
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local pick: string? = nil -- 選んだ品の uid（"" は外す）
	local busy = false
	local render: () -> ()

	render = function()
		body:ClearAllChildren()
		local view = Session.view
		if view == nil then
			return
		end
		local adv = view.adventurers[uid]
		if adv == nil then
			api.close()
			return
		end
		local curUid = adv.equipment and adv.equipment[tab]
		local list = EquipChoice.candidates(view, adv, tab, master, deps)
		if pick == nil or (pick ~= "" and view.equipment[pick] == nil) then
			pick = if list[1] then list[1].uid elseif curUid then "" else nil
		end

		-- 枠のタブ
		local tabs: Frame = new("Frame", {
			Name = "Slots",
			Position = UDim2.fromOffset(40, band + 12),
			Size = UDim2.fromOffset(0, 74),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.ch52,
			ZIndex = 10,
			[CHILDREN] = {
				Components.corner(37),
				Components.padding(4, 4, 4, 4),
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 4),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = body,
		})
		for i, id in SLOTS do
			local on = tab == id
			local b: TextButton = new("TextButton", {
				Name = "Tab_" .. id,
				LayoutOrder = i,
				Text = I[id] .. " " .. Words.slot[id], -- 語を添える（D-245）
				TextSize = 21,
				FontFace = Tokens.font.display,
				TextColor3 = if on then C.inkDark else C.inkLight,
				AutoButtonColor = false,
				Size = UDim2.fromOffset(Words.slotWidth[id], 66),
				BackgroundColor3 = if on then C.selAmber else C.ch28,
				ZIndex = 11,
				[CHILDREN] = { Components.corner(33) },
				Parent = tabs,
			})
			b.Activated:Connect(function()
				if tab ~= id then
					tab = id
					pick = nil
					render()
				end
			end)
		end

		-- 左：候補の一覧（暗い木）
		local left, leftContent = Components.panel({
			size = UDim2.new(1, -(40 + 24 + RIGHT_W + 40), 0, 392),
			position = UDim2.fromOffset(40, band + 98),
			dark = true,
		})
		left.Name = "Candidates"
		left.Parent = body
		local scroll: ScrollingFrame = new("ScrollingFrame", {
			Name = "List",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			ScrollBarImageColor3 = C.bronze,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			[CHILDREN] = {
				new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
				Components.padding(4, 10, 4, 4),
			},
			Parent = leftContent,
		})
		local function row(order: number, id: string, selected: boolean): TextButton
			local r: TextButton = new("TextButton", {
				Name = "Row_" .. (if id == "" then "Unequip" else id),
				LayoutOrder = order,
				Text = "",
				AutoButtonColor = false,
				Size = UDim2.new(1, 0, 0, 80),
				BackgroundColor3 = C.ch16,
				[CHILDREN] = {
					Components.corner(8),
					Components.stroke(if selected then C.selAmber else C.ch16, 3),
				},
				Parent = scroll,
			})
			r.Activated:Connect(function()
				pick = id
				render()
			end)
			return r
		end
		local function well(parent: GuiObject, icon: string, rarity: number?, grade: number?, dashed: boolean)
			local w: Frame = new("Frame", {
				Name = "Icon",
				Position = UDim2.fromOffset(8, 7),
				Size = UDim2.fromOffset(66, 66),
				BackgroundColor3 = C.ch10,
				BackgroundTransparency = if dashed then 1 else 0,
				[CHILDREN] = {
					Components.corner(8),
					Components.stroke(if rarity then ChestCommon.rarityColor(rarity) else C.ch28, 3),
				},
				Parent = parent,
			})
			local t = Components.text({
				text = icon,
				size = 34,
				color = if dashed then C.ch45 else C.inkLight,
				font = Tokens.font.number,
			})
			t.AnchorPoint = Vector2.new(0.5, 0.5)
			t.Position = UDim2.fromScale(0.5, 0.5)
			t.Parent = w
			if grade and grade > 0 then
				local g = Components.text({
					text = "+" .. grade,
					size = 21,
					color = C.numHi,
					font = Tokens.font.number,
					stroke = true,
				})
				g.AnchorPoint = Vector2.new(1, 1)
				g.Position = UDim2.new(1, -2, 1, 0)
				g.Parent = w
			end
		end
		local function delta(parent: GuiObject, text: string, color: Color3)
			if text == "" then
				return
			end
			local d =
				Components.text({ text = text, size = 25, color = color, font = Tokens.font.number, stroke = false })
			d.AnchorPoint = Vector2.new(1, 0.5)
			d.Position = UDim2.new(1, -14, 0.5, 0)
			d.TextColor3 = if color == C.up then C.upDark else C.warnDark
			d.Parent = parent
		end
		-- 先頭：外す（空き）の行。外したときに下がる値を▼
		if curUid then
			local r = row(1, "", pick == "")
			well(r, I[tab], nil, nil, true)
			local cur = view.equipment[curUid]
			local loss = EquipChoice.delta(cur, nil, master, deps)
			delta(
				r,
				if loss > 0 then "▼" .. string.format(if loss % 1 == 0 then "%d" else "%.2f", loss) else "",
				C.warn
			)
		end
		for i, c in list do
			local item = view.equipment[c.uid]
			local r = row(1 + i, c.uid, pick == c.uid)
			well(r, I[tab], item.rarity, item.grade, false)
			local vals: Frame = new("Frame", {
				Name = "Values",
				Position = UDim2.fromOffset(86, 0),
				Size = UDim2.new(1, -86 - 150, 1, 0),
				BackgroundTransparency = 1,
				[CHILDREN] = {
					new("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 8),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				},
				Parent = r,
			})
			for k, v in WarehouseCommon.values(item) do
				local p =
					WarehouseCommon.pill(v.icon, v.text, if v.icon == WarehouseCommon.icon.modifier then 21 else 23)
				p.LayoutOrder = k
				p.Parent = vals
			end
			local txt, col = deltaText(c)
			delta(r, txt, col)
		end

		-- 右：その人の面（変わる値の行だけ。棒＝新しい値、白い目盛り＝今の値、▲▼）
		local right, rc = Components.panel({
			size = UDim2.fromOffset(RIGHT_W, 392),
			position = UDim2.new(1, -40, 0, band + 98),
			anchor = Vector2.new(1, 0),
			title = adv.name,
		})
		right.Name = "Compare"
		right.Parent = body
		new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = rc })
		if pick ~= nil then
			local rows = EquipChoice.compare(view, adv, tab, if pick == "" then nil else pick, master, deps)
			for i, rr in rows do
				local lab = KEY_LABEL[rr.key]
				local isXp = rr.key == "expRate"
				local before = if isXp then 1 + rr.before else rr.before
				local after = if isXp then 1 + rr.after else rr.after
				local line: Frame = new("Frame", {
					Name = "Row_" .. rr.key,
					LayoutOrder = i,
					Size = UDim2.new(1, 0, 0, 56),
					BackgroundColor3 = C.ch75,
					[CHILDREN] = { Components.corner(6), Components.padding(0, 12, 0, 12) },
					Parent = rc,
				})
				local l = Components.text({
					text = (lab.icon ~= "" and lab.icon or lab.text),
					size = 25,
					color = C.inkDark,
					font = Tokens.font.number,
				})
				l.AnchorPoint = Vector2.new(0, 0.5)
				l.Position = UDim2.fromScale(0, 0.5)
				l.Parent = line
				-- 棒の尺度：大きい方が 3/4（宝箱 v3 と同じ表示用の倍率）
				local top = math.max(before, after) / 0.75
				local track: Frame = new("Frame", {
					Name = "Bar",
					Position = UDim2.new(0, 64, 0.5, -14),
					Size = UDim2.new(1, -64 - 110, 0, 28),
					BackgroundColor3 = C.barTrack,
					[CHILDREN] = { Components.corner(8) },
					Parent = line,
				})
				new("Frame", {
					Name = "Fill",
					Position = UDim2.fromOffset(2, 2),
					Size = UDim2.new(math.clamp(after / math.max(1e-6, top), 0, 1), -4, 1, -4),
					BackgroundColor3 = C.barFill,
					[CHILDREN] = { Components.corner(6) },
					Parent = track,
				})
				new("Frame", {
					Name = "Now",
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(math.clamp(before / math.max(1e-6, top), 0, 1), 0, 0, -3),
					Size = UDim2.new(0, 4, 1, 6),
					BackgroundColor3 = C.inkWhite,
					Parent = track,
				})
				local num = Components.text({
					text = if isXp then string.format("×%.2f", after) else tostring(after),
					size = 23,
					color = C.inkWhite,
					font = Tokens.font.number,
					stroke = true,
				})
				num.AnchorPoint = Vector2.new(0.5, 0.5)
				num.Position = UDim2.fromScale(0.5, 0.5)
				num.Parent = track
				local up = after > before
				local diff = if isXp
					then string.format("×%.2f", after / before)
					else tostring(math.abs(after - before))
				local d = Components.text({
					text = (if up then "▲" else "▼") .. diff,
					size = 25,
					color = if up then C.up else C.warn,
					font = Tokens.font.number,
				})
				d.AnchorPoint = Vector2.new(1, 0.5)
				d.Position = UDim2.fromScale(1, 0.5)
				d.Parent = line
			end
		end

		-- 右下：Equip（金）。外すの行なら外すのアイコン
		local actions = Screen.actionRow(body)
		local unequip = pick == ""
		local main = Components.button({
			kind = if pick ~= nil then "gold" else "disabled",
			width = 320,
			icon = if unequip then I[tab] .. "→" else I.party .. I.attack, -- 外す＝枠＋外への矢印（D-232 ⑥）
			label = if unequip then Words.unequip else Words.equip,
			name = if unequip then "Unequip" else "Equip",
			glyph = "A",
			onClick = function()
				if busy or pick == nil then
					return
				end
				busy = true
				local r
				if pick == "" then
					r = Session.sendAndWait({ type = "Unequip", adventurerUid = uid, slot = tab })
				else
					r = Session.sendAndWait({ type = "Equip", adventurerUid = uid, equipmentUid = pick })
				end
				busy = false
				if r and r.ok then
					api.close()
				else
					render()
				end
			end,
		})
		main.LayoutOrder = 2
		main.Parent = actions
	end

	render()
	local conn = Session.changed:connect(function()
		if not busy then
			render()
		end
	end)
	return {
		frame = frame,
		scrim = 1,
		destroy = function()
			conn.disconnect()
		end,
	}
end

Nav.register("EquipSelect", build)

return {}
