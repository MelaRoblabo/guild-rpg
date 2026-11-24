--!strict
-- S-12 パーティメニュー（編成。D-005・D-120・D-130・D-163・D-216・D-231 ⑦⑨⑩・D-232 ⑧）。
--   開き方：待機中のパーティの面の Menu（茶）→ 画面いっぱいの1枚。× は右上で面に戻る。
--   - 羊皮紙のパネルに隊列1〜4のカード（左が1番）。題の札＝パーティの印＋番号。
--   - カード：被弾の帯（幅＝被弾の重みを1番＝100% とした長さ。% は出さない：D-005・D-218 ③）／肖像（仮）＋名前＋職業の札
--     （攻撃の種類のアイコン＋短い職業名：D-232 ⑧）＋★転生＋Lv／攻撃力・物理防御・魔法防御の凹み／最大HP の棒／装備の枠3つ（押すと S-42）。
--   - 入れ替え：カードの肖像を押す（琥珀）→ ほかのカード（点線）か下の一覧の顔を押す。選んでいる間はメイン・サブを消して一覧の帯を出す。
--     下の一覧はこのパーティ以外の冒険者。ほかのパーティの人・探索中の人は暗く（入れられない：ADVENTURER_IN_OTHER_PARTY）。左端は外す（空き枠）。
--   - 右下：金＝行き先を選ぶ（地図 → マップで選ぶ → S-15 の面で Go：D-231 ⑦）。茶＝自動装備（より良い装備があるときは緑の ▲：D-216）。
--   - 自動装備は押すとすぐ決めず、変わるカードの差（▲▼）を見せる。金の Equip で決め、茶の Cancel でやめる（D-231 ⑨・D-235 ③）。

local AutoEquip = require("@game/ReplicatedStorage/Core/AutoEquip")
local Formulas = require("@game/ReplicatedStorage/Core/Formulas")
local Party = require("@game/ReplicatedStorage/Core/Party")
local AdvCommon = require("../adventurers/AdvCommon")
local ChestCommon = require("../chest/ChestCommon")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Nav = require("../../ui/Nav")
local PickMode = require("../../hub/PickMode")
local Root = require("../../ui/Root")
local Screen = require("../Screen")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local WarehouseCommon = require("../warehouse/WarehouseCommon")
local master = require("../../Master")

local C = Tokens.color
local I = AdvCommon.icon
local new = Create.new
local CHILDREN = Create.Children

local MAP_ICON = "▦" -- 行き先を選ぶ（地図。仮の記号）
local AUTO_ICON = "🛡★" -- 自動装備（鎧＋きらめき。仮。✦ は出ない）

local function pill(icon: string, text: string, size: number, iconColor: Color3?): Frame
	return WarehouseCommon.pill(icon, text, size, iconColor)
end

-- 自動装備の提案を当てたときの、その人の実効値
local function snapAfter(view: any, adv: any, slot: number, plan: { any }): any
	local def = Party.memberDef(view, adv, slot)
	local eq = table.clone(def.equipment)
	for _, c in plan do
		if c.advUid == adv.uid then
			local e = view.equipment[c.to]
			eq[c.slot] = {
				baseId = e.baseId,
				rarity = e.rarity,
				grade = e.grade,
				itemLevel = e.itemLevel,
				modifierId = e.modifierId,
				modifierValue = e.modifierValue,
			}
		end
	end
	def.equipment = eq
	return Formulas.memberSnapshot(def, master)
end

local function build(params: any?, api: Nav.Api): Nav.Built
	local partyIndex = (params :: any).partyIndex :: number
	local band = Root.bandBottom()
	local frame = Screen.scene("PartyMenu")
	Screen.closeTopRight(frame, api.close)
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local pickSlot: number? = nil -- 入れ替えで選んでいる隊列
	local equipMode = false -- 自動装備の差を見せている
	local busy = false
	local render: () -> ()

	local function send(cmd: any): any?
		busy = true
		local r = Session.sendAndWait(cmd)
		busy = false
		return r
	end

	render = function()
		body:ClearAllChildren()
		local view = Session.view
		if view == nil then
			return
		end
		local party = view.parties[partyIndex]
		if party == nil or Party.isBusy(view, partyIndex) then
			api.close()
			return
		end
		local plan = AutoEquip.plan(view, partyIndex, master)
		if equipMode and #plan == 0 then
			equipMode = false
		end

		-- 隊列のパネル（題の札＝パーティの番号）
		local panel, content = Components.panel({
			size = UDim2.new(1, -80, 0, 444),
			position = UDim2.fromOffset(40, band + 44),
			title = I.party .. " " .. partyIndex .. "  " .. "⌂",
		})
		panel.Name = "Formation"
		panel.Parent = body
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = content,
		})
		local weights = master.K.hitWeights
		local maxW = weights[1]
		-- 最大HP の棒の尺度：パーティで一番高い人が 3/4（宝箱 v3 と同じ表示用の倍率。Q6）
		local hpTop = 1
		for _, u in party.slots do
			local a = view.adventurers[u]
			if a then
				hpTop = math.max(hpTop, Formulas.memberSnapshot(Party.memberDef(view, a, 1), master).maxHp / 0.75)
			end
		end
		for slot = 1, Party.SIZE do
			local uid = party.slots[slot]
			local adv = view.adventurers[uid]
			local selected = pickSlot == slot
			local target = pickSlot ~= nil and not selected
			local card: Frame = new("Frame", {
				Name = "Card" .. slot,
				LayoutOrder = slot,
				Size = UDim2.new(0.25, -8, 1, 0),
				BackgroundColor3 = C.ch75,
				[CHILDREN] = {
					Components.corner(6),
					Components.padding(10, 12, 10, 12),
					Components.stroke(
						if selected then C.selAmber elseif target then C.selAmber else C.ch68,
						if selected then 4 else 2
					),
				},
				Parent = content,
			})
			-- 被弾の帯（1番＝100%）
			local hit: Frame = new("Frame", {
				Name = "Hit",
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundTransparency = 1,
				Parent = card,
			})
			Components.text({ text = "⚠", size = 21, color = C.inkDark, font = Tokens.font.number }).Parent = hit
			local track: Frame = new("Frame", {
				Name = "Track",
				Position = UDim2.fromOffset(34, 5),
				Size = UDim2.new(1, -34, 0, 16),
				BackgroundColor3 = C.barTrack,
				[CHILDREN] = { Components.corner(8) },
				Parent = hit,
			})
			new("Frame", {
				Name = "Fill",
				Position = UDim2.fromOffset(2, 2),
				Size = UDim2.new(weights[slot] / maxW, -4, 1, -4),
				BackgroundColor3 = C.barFill,
				[CHILDREN] = { Components.corner(6) },
				Parent = track,
			})
			-- 肖像（押すと入れ替え）
			local face: TextButton = new("TextButton", {
				Name = "Face",
				Position = UDim2.fromOffset(0, 36),
				Size = UDim2.fromOffset(96, 120),
				Text = if adv then I.party else "✚",
				TextSize = 44,
				FontFace = Tokens.font.number,
				TextColor3 = if adv then C.ch45 else C.inkMid,
				AutoButtonColor = false,
				BackgroundColor3 = C.ch13,
				[CHILDREN] = { Components.corner(8), Components.stroke(C.ch16, 2) },
				Parent = card,
			})
			face.Activated:Connect(function()
				if equipMode or busy then
					return
				end
				if pickSlot == nil then
					pickSlot = slot
					render()
				elseif pickSlot == slot then
					pickSlot = nil
					render()
				else
					-- 同じパーティ内の入れ替え（SetPartySlot は同じパーティの人なら入れ替える）
					local a = party.slots[pickSlot]
					local from = pickSlot
					pickSlot = nil
					if a ~= Party.EMPTY then
						send({ type = "SetPartySlot", partyIndex = partyIndex, slot = slot, adventurerUid = a })
					elseif uid ~= Party.EMPTY then
						send({ type = "SetPartySlot", partyIndex = partyIndex, slot = from, adventurerUid = uid })
					end
					render()
				end
			end)
			if adv then
				local job = master.jobs[adv.jobId]
				local info: Frame = new("Frame", {
					Name = "Info",
					Position = UDim2.fromOffset(106, 36),
					Size = UDim2.new(1, -106, 0, 120),
					BackgroundTransparency = 1,
					[CHILDREN] = {
						new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
					},
					Parent = card,
				})
				local nm = Components.text({
					text = adv.name,
					size = 23,
					color = C.inkDark,
					font = Tokens.font.display,
					xAlign = Enum.TextXAlignment.Left,
				})
				nm.LayoutOrder = 1
				nm.AutomaticSize = Enum.AutomaticSize.None
				nm.Size = UDim2.new(1, 0, 0, 28)
				nm.TextTruncate = Enum.TextTruncate.AtEnd
				nm.Parent = info
				local jt = pill(
					if job and job.attackType == "magic" then "◈" else "⚔",
					if job then job.nameEn else adv.jobId,
					21,
					C.inkLight
				)
				jt.LayoutOrder = 2
				jt.Parent = info
				local lv = Components.text({
					text = I.rebirth .. (adv.rebirthCount or 0) .. "   Lv" .. adv.level,
					size = 21,
					color = C.inkDark,
					font = Tokens.font.number,
					xAlign = Enum.TextXAlignment.Left,
				})
				lv.LayoutOrder = 3
				lv.Parent = info
				-- 攻撃・物防・魔防（自動装備の差は ▲▼）
				local before = Formulas.memberSnapshot(Party.memberDef(view, adv, slot), master)
				local after = if equipMode then snapAfter(view, adv, slot, plan) else before
				local stats: Frame = new("Frame", {
					Name = "Stats",
					Position = UDim2.fromOffset(0, 166),
					Size = UDim2.new(1, 0, 0, 40),
					BackgroundTransparency = 1,
					[CHILDREN] = {
						new("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							Padding = UDim.new(0, 6),
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
					},
					Parent = card,
				})
				local function stat(order: number, icon: string, key: string)
					local b, a = before[key], after[key]
					local mark = if a > b then " ▲" elseif a < b then " ▼" else ""
					local p = pill(icon, tostring(a) .. mark, 21)
					p.LayoutOrder = order
					p.Parent = stats
				end
				stat(1, I.attack, "atk")
				stat(2, I.pdef, "pdef")
				stat(3, I.mdef, "mdef")
				-- 最大HP の棒（数字は棒の中）
				local hpTrack: Frame = new("Frame", {
					Name = "HP",
					Position = UDim2.fromOffset(30, 216),
					Size = UDim2.new(1, -30, 0, 32),
					BackgroundColor3 = C.barTrack,
					[CHILDREN] = { Components.corner(8) },
					Parent = card,
				})
				local ht = Components.text({ text = I.hp, size = 21, color = C.statHp, font = Tokens.font.number })
				ht.Position = UDim2.fromOffset(0, 220)
				ht.Parent = card
				new("Frame", {
					Name = "Fill",
					Position = UDim2.fromOffset(2, 2),
					Size = UDim2.new(math.clamp(after.maxHp / hpTop, 0, 1), -4, 1, -4),
					BackgroundColor3 = C.barFill,
					[CHILDREN] = { Components.corner(6) },
					Parent = hpTrack,
				})
				local hn = Components.text({
					text = tostring(after.maxHp),
					size = 23,
					color = C.inkWhite,
					font = Tokens.font.number,
					stroke = true,
				})
				hn.AnchorPoint = Vector2.new(0.5, 0.5)
				hn.Position = UDim2.fromScale(0.5, 0.5)
				hn.Parent = hpTrack
				-- 装備の枠3つ（押すと S-42）
				local eqRow: Frame = new("Frame", {
					Name = "Equipment",
					Position = UDim2.fromOffset(0, 258),
					Size = UDim2.new(1, 0, 0, 66),
					BackgroundTransparency = 1,
					[CHILDREN] = {
						new("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							Padding = UDim.new(0, 8),
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
					},
					Parent = card,
				})
				for k, s in { "weapon", "armor", "sub" } do
					local itemUid = adv.equipment[s]
					local item = if itemUid then view.equipment[itemUid] else nil
					local changing = false
					if equipMode then
						for _, c in plan do
							if c.advUid == adv.uid and c.slot == s then
								changing = true
							end
						end
					end
					local b: TextButton = new("TextButton", {
						Name = "Slot_" .. s,
						LayoutOrder = k,
						Text = I[s],
						TextSize = 28,
						FontFace = Tokens.font.number,
						TextColor3 = if item then C.inkLight else C.ch45,
						AutoButtonColor = false,
						Size = UDim2.fromOffset(66, 66),
						BackgroundColor3 = C.secondary,
						[CHILDREN] = {
							Components.corner(14),
							Components.stroke(
								if changing
									then C.okGreen
									elseif item then ChestCommon.rarityColor(item.rarity)
									else C.secondaryRim,
								3
							),
						},
						Parent = eqRow,
					})
					b.Activated:Connect(function()
						if not equipMode and pickSlot == nil then
							api.open("EquipSelect", { uid = adv.uid, slot = s })
						end
					end)
				end
			end
		end

		-- 入れ替えで選んでいる間：下の一覧（このパーティ以外の冒険者。左端は外す）
		if pickSlot ~= nil then
			local strip: Frame = new("Frame", {
				Name = "Others",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 40, 1, -12),
				Size = UDim2.new(1, -80 - 120, 0, 96),
				BackgroundColor3 = C.ch10,
				[CHILDREN] = { Components.corner(12), Components.padding(15, 12, 15, 12) },
				Parent = body,
			})
			local scroll: ScrollingFrame = new("ScrollingFrame", {
				Name = "List",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 4,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.X,
				ScrollingDirection = Enum.ScrollingDirection.X,
				[CHILDREN] = {
					new("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = UDim.new(0, 8),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				},
				Parent = strip,
			})
			local function put(uid: string)
				local s = pickSlot :: number
				pickSlot = nil
				send({ type = "SetPartySlot", partyIndex = partyIndex, slot = s, adventurerUid = uid })
				render()
			end
			local empty: TextButton = new("TextButton", {
				Name = "LeaveEmpty",
				LayoutOrder = 0,
				Text = "○",
				TextSize = 28,
				FontFace = Tokens.font.number,
				TextColor3 = C.inkLight,
				AutoButtonColor = false,
				Size = UDim2.fromOffset(66, 66),
				BackgroundColor3 = C.ch13,
				[CHILDREN] = { Components.corner(12), Components.stroke(C.ch28, 2) },
				Parent = scroll,
			})
			empty.Activated:Connect(function()
				if not busy then
					put(Party.EMPTY)
				end
			end)
			local others = {}
			for uid, a in view.adventurers do
				local p = Party.find(view, uid)
				if p ~= partyIndex then
					table.insert(others, { uid = uid, adv = a, p = p })
				end
			end
			table.sort(others, function(x, y)
				if (x.p == nil) ~= (y.p == nil) then
					return x.p == nil
				end
				if x.adv.level ~= y.adv.level then
					return x.adv.level > y.adv.level
				end
				return x.uid < y.uid
			end)
			for i, o in others do
				local free = o.p == nil
				local b: TextButton = new("TextButton", {
					Name = "Adv_" .. o.uid,
					LayoutOrder = i,
					Text = if free then I.party else I.party .. o.p,
					TextSize = 21,
					FontFace = Tokens.font.number,
					TextColor3 = C.inkLight,
					TextTransparency = if free then 0 else 0.5,
					AutoButtonColor = false,
					Active = free,
					Size = UDim2.fromOffset(74, 66),
					BackgroundColor3 = if free then C.ch28 else C.ch13,
					[CHILDREN] = { Components.corner(12) },
					Parent = scroll,
				})
				if free then
					b.Activated:Connect(function()
						if not busy then
							put(o.uid)
						end
					end)
				end
			end
			return -- 選んでいる間はメイン・サブを消す
		end

		-- 右下：自動装備（茶）と行き先（金）。自動装備の差を見せている間は Cancel（茶）と Equip（金）
		local actions = Screen.actionRow(body)
		if equipMode then
			local cancel = Components.button({
				kind = "brown",
				width = 200,
				height = 66,
				label = "Cancel",
				name = "Cancel",
				glyph = "Y",
				onClick = function()
					equipMode = false
					render()
				end,
			})
			cancel.LayoutOrder = 1
			cancel.Parent = actions
			local equip = Components.button({
				kind = "gold",
				width = 320,
				icon = I.party .. "✓",
				name = "Equip",
				glyph = "A",
				onClick = function()
					if busy then
						return
					end
					send({ type = "AutoEquip", partyIndex = partyIndex })
					equipMode = false
					render()
				end,
			})
			equip.LayoutOrder = 2
			equip.Parent = actions
		else
			local auto = Components.button({
				kind = if #plan > 0 then "brown" else "disabled",
				width = 120,
				height = 66,
				icon = AUTO_ICON,
				name = "AutoEquip",
				glyph = "X",
				onClick = function()
					if #plan > 0 then
						equipMode = true
						render()
					end
				end,
			})
			auto.LayoutOrder = 1
			auto.Parent = actions
			if #plan > 0 then
				-- より良い装備があるときは緑の ▲（D-216）
				new("TextLabel", {
					Name = "Better",
					Text = "▲",
					TextSize = 18,
					FontFace = Tokens.font.number,
					TextColor3 = C.inkDark,
					BackgroundColor3 = C.okGreen,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(4, 4),
					Size = UDim2.fromOffset(30, 30),
					ZIndex = 5,
					[CHILDREN] = { Components.corner(15) },
					Parent = auto,
				})
			end
			local dest = Components.button({
				kind = "gold",
				width = 320,
				icon = MAP_ICON,
				name = "Destination",
				glyph = "A",
				onClick = function()
					-- マップで選ぶ（D-231 ⑦）。メインの画面に戻って、ダンジョンを触ると S-15 がこのパーティから開く
					PickMode.start(partyIndex)
					api.home()
				end,
			})
			dest.LayoutOrder = 2
			dest.Parent = actions
		end
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

Nav.register("PartyMenu", build)

return {}
