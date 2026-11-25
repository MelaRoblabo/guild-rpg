--!strict
-- S-41 冒険者の詳細（D-024・D-217・D-218・D-220・D-231 ①⑪・D-232 ⑦）。問い＝「この人をどう強くする？」
--   雇用 S-21c/d/e と同じ配置：左に肖像、右に能力の面（題の札＝名前）。
--   - 能力の列（アイコン＋STR などの表記＋伸びやすさ▲＋棒＋数字）。攻撃に使う能力と HP は太い棒。上に XP の細い棒。
--     下の暗いくぼみ＝攻撃力・物理防御・魔法防御。右の列＝装備3枠（押すと S-42。もっと良い品があれば緑の▲）とギフト（空きは点線）。
--   - 肖像の右上＝保護のピン（D-217）。肖像の下の段＝改名・見た目変更（個数）・転職ポーション（個数）・解雇。
--   - メイン（金）＝トレーニング1回（費用つき）。押し続けると約0.5秒で連続に入り、ゴールド・上限・指を離すまで続く。
--     Lv が上がっても止めない（D-231 ⑪・D-232 ⑦）。上限 Lv なら Rebirth（語あり）→ S-43a。
--   - 探索中は装備・転職・解雇・メインを押せない色にし、メインの左に理由の札（パーティの番号と状態）。
--   - 確認は解雇だけ（D-231 ①）。転職・見た目変更は押したらすぐ。

local Game = require("@game/ReplicatedStorage/Core/Game")
local JobChange = require("@game/ReplicatedStorage/Core/JobChange")
local Party = require("@game/ReplicatedStorage/Core/Party")
local Training = require("@game/ReplicatedStorage/Core/Training")
local AdvCommon = require("./AdvCommon")
local ChestCommon = require("../chest/ChestCommon")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Art = require("../../ui/Art")
local HireCommon = require("../hire/HireCommon")
local HubState = require("../../hub/HubState")
local Nav = require("../../ui/Nav")
local RebirthCommon = require("../rebirth/RebirthCommon")
local Root = require("../../ui/Root")
local Roster = require("../../adventurers/Roster")
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
local deps = AdvCommon.deps

-- 長押しの時間（仮。D-232 ⑦：値は M8-FX でマスターデータへ移す）
local HOLD_START = 0.5
local HOLD_STEP = 0.15

local function pill(icon: string, text: string, size: number, iconColor: Color3?): Frame
	return WarehouseCommon.pill(icon, text, size, iconColor)
end

local function vlist(parent: GuiObject, gap: number)
	new("UIListLayout", { Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder, Parent = parent })
end

-- 重ねる面（羊皮紙。右上の ×）
local function sheet(parent: Frame, name: string, size: UDim2, onClose: () -> ()): Frame
	local scrim: TextButton = new("TextButton", {
		Name = name .. "Scrim",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.scrim,
		BackgroundTransparency = Tokens.transparency.scrim,
		ZIndex = 30,
		Parent = parent,
	})
	local panel, content = Components.panel({
		size = size,
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
	})
	panel.Name = name
	panel.Parent = scrim
	local close = Components.closeButton(onClose)
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(1, -18, 0, 18)
	close.ZIndex = 40
	close.Parent = panel
	return content
end

local function build(params: any?, api: Nav.Api): Nav.Built
	local uid = (params :: any).uid
	local band = Root.bandBottom()
	local frame = Screen.scene("AdvDetail")
	Screen.closeTopRight(frame, api.close)
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local overlay: "job" | "dismiss" | "rename" | nil = nil
	local busy = false
	local holding = false
	local held = false
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
		local adv = view.adventurers[uid]
		if adv == nil then
			api.close() -- 解雇したあと
			return
		end
		local job = master.jobs[adv.jobId]
		local exploring = Party.isAdventurerBusy(view, uid)
		local snap = Game.query.snapshot(view, uid, master)

		-- 左：肖像（仮）と保護のピン、下の段の道具
		local portrait = HireCommon.portrait(body, adv)
		-- 保護のピン（D-217）。語を添える（D-245）
		local pin: TextButton = new("TextButton", {
			Name = "Pin",
			Text = "",
			TextSize = 21,
			FontFace = Tokens.font.display,
			TextColor3 = if adv.locked then C.inkDark else C.inkLight,
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 12),
			Size = UDim2.fromOffset(0, 66),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = if adv.locked then C.selAmber else C.secondary,
			ZIndex = 9,
			[CHILDREN] = { Components.corner(33), Components.stroke(C.bronze, 3), Components.padding(0, 18, 0, 16) },
			Parent = portrait,
		})
		Components.setParts(pin, { I.pin, if adv.locked then Words.locked else Words.lock })
		pin.Activated:Connect(function()
			if not busy then
				send({ type = "SetLock", uid = uid, locked = not adv.locked })
				render()
			end
		end)
		-- 道具：アイコン＋語の2列（D-245。アイコンだけの小さな丸から大きさを変えた）
		local tools: Frame = new("Frame", {
			Name = "Tools",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.new(1, -28, 0, 66 * 2 + 12),
			BackgroundTransparency = 1,
			ZIndex = 9,
			[CHILDREN] = {
				new("UIGridLayout", {
					CellSize = UDim2.new(0.5, -6, 0, 66),
					CellPadding = UDim2.fromOffset(12, 12),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = portrait,
		})
		local function tool(
			order: number,
			name: string,
			icon: string,
			word: string,
			count: number?,
			enabled: boolean,
			onClick: () -> ()
		)
			local b: TextButton = new("TextButton", {
				Name = name,
				LayoutOrder = order,
				Text = "",
				TextSize = 21,
				FontFace = Tokens.font.display,
				TextColor3 = C.inkLight,
				TextTransparency = if enabled then 0 else 0.5,
				AutoButtonColor = false,
				Active = enabled,
				BackgroundColor3 = if enabled then C.secondary else C.disabled,
				ZIndex = 10,
				[CHILDREN] = { Components.corner(18), Components.stroke(C.secondaryRim, 3) },
				Parent = tools,
			})
			Components.setParts(b, { icon, word })
			if count then
				local c = pill("", tostring(count), 21)
				c.AnchorPoint = Vector2.new(1, 1)
				c.Position = UDim2.new(1, 8, 1, 8)
				c.ZIndex = 11
				c.Parent = b
			end
			if enabled then
				b.Activated:Connect(onClick)
			end
		end
		local items = view.items or {}
		local jobPotions = 0
		for _, row in master.raw.Items do
			if row.kind == "potion_job" then
				jobPotions += items[row.id] or 0
			end
		end
		tool(1, "Rename", I.rename, Words.rename, nil, adv.uniqueId == nil, function()
			overlay = "rename"
			render()
		end)
		local looks = items.itm_potion_appearance_change or 0
		local pending = view.appearanceSession and view.appearanceSession.adventurerUid == uid
		tool(2, "LookChange", I.look, Words.looks, looks, adv.uniqueId == nil and (looks > 0 or pending), function()
			-- 押したらすぐ1個使って抽選（確認なし：D-231 ①）→ S-44。選ぶ途中なら続き（D-131）
			if busy then
				return
			end
			if pending then
				api.open("LookChange", { uid = uid })
				return
			end
			local r = send({ type = "ChangeAppearance", adventurerUid = uid })
			if r and r.ok then
				api.open("LookChange", { uid = uid })
			else
				render()
			end
		end)
		tool(3, "JobPotion", I.jobPotion, Words.jobChange, jobPotions, not exploring and jobPotions > 0, function()
			overlay = "job"
			render()
		end)
		tool(4, "Dismiss", I.dismiss, Words.dismiss, nil, not exploring and not adv.locked, function()
			overlay = "dismiss"
			render()
		end)

		-- 右：能力の面（題の札＝名前、右に職業・転生・Lv の札）
		local panel, content = Components.panel({
			size = UDim2.fromOffset(700, 448),
			position = UDim2.new(1, -40, 0, band + 44),
			anchor = Vector2.new(1, 0),
			title = adv.name,
		})
		panel.Name = "Stats"
		panel.Parent = body
		local tags = Components.chip(
			if job and job.attackType == "magic" then "@job_magic" else "@job_physical",
			if (adv.rebirthCount or 0) > 0
				then { if job then job.nameEn else adv.jobId, I.rebirth, tostring(adv.rebirthCount), "Lv " .. adv.level }
				else { if job then job.nameEn else adv.jobId, "Lv " .. adv.level },
			C.inkLight
		)
		tags.Name = "Tags"
		tags.AnchorPoint = Vector2.new(1, 0.5)
		tags.Position = UDim2.new(1, -96, 0, 0)
		tags.ZIndex = 8
		tags.Parent = panel
		local leftCol: Frame = new("Frame", {
			Name = "Left",
			Size = UDim2.new(0, 360, 1, 0),
			BackgroundTransparency = 1,
			Parent = content,
		})
		vlist(leftCol, 6)
		-- XP の細い棒
		local need = Game.query.expToNext(adv.level, master, adv.rebirthCount)
		local xpRow: Frame = new("Frame", {
			Name = "XP",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			Parent = leftCol,
		})
		local xpLabel = Components.text({ text = "XP", size = 21, color = C.inkDark, font = Tokens.font.number })
		xpLabel.Parent = xpRow
		local track: Frame = new("Frame", {
			Name = "Track",
			Position = UDim2.fromOffset(44, 4),
			Size = UDim2.new(1, -48, 0, 18),
			BackgroundColor3 = C.barTrack,
			[CHILDREN] = { Components.corner(9) },
			Parent = xpRow,
		})
		new("Frame", {
			Name = "Fill",
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(
				if adv.level >= adv.levelCap then 1 else math.clamp((adv.exp or 0) / math.max(1, need), 0, 1),
				-4,
				1,
				-4
			),
			BackgroundColor3 = C.barFill,
			[CHILDREN] = { Components.corner(7) },
			Parent = track,
		})
		-- 能力の列（素の能力。雇用・転生と同じ並び）
		local marks = HireCommon.growthMarks(adv.jobId)
		local attack = HireCommon.attackStat(adv.jobId)
		for i, s in HireCommon.STATS do
			local r = Components.statRow({
				stat = s.key,
				label = s.label,
				value = adv.baseStats[s.key],
				min = 0,
				max = Roster.statMax(adv, s.key, master),
				big = s.key == attack or s.key == "hp",
				marks = marks[s.key],
			})
			r.LayoutOrder = 1 + i
			r.Size = UDim2.new(1, 0, 0, 50)
			r.Parent = leftCol
		end
		-- 攻撃力・物理防御・魔法防御（実効）
		local wells: Frame = new("Frame", {
			Name = "Wells",
			LayoutOrder = 10,
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundTransparency = 1,
			[CHILDREN] = {
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 10),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = leftCol,
		})
		local a = pill(I.attack, tostring(snap.atk), 30, C.statStrDark)
		a.LayoutOrder = 1
		a.Parent = wells
		local p = pill(I.pdef, tostring(snap.pdef), 25)
		p.LayoutOrder = 2
		p.Parent = wells
		local m = pill(I.mdef, tostring(snap.mdef), 25, C.statMagDark)
		m.LayoutOrder = 3
		m.Parent = wells

		-- 右の列：装備3枠とギフト
		local rightCol: Frame = new("Frame", {
			Name = "Right",
			Position = UDim2.fromOffset(374, 0),
			Size = UDim2.new(1, -374, 1, 0),
			BackgroundTransparency = 1,
			Parent = content,
		})
		vlist(rightCol, 8)
		for i, slot in { "weapon", "armor", "sub" } do
			local itemUid = adv.equipment and adv.equipment[slot]
			local item = if itemUid then view.equipment[itemUid] else nil
			local b: TextButton = new("TextButton", {
				Name = "Slot_" .. slot,
				LayoutOrder = i,
				Text = "",
				AutoButtonColor = false,
				Active = not exploring,
				Size = UDim2.new(1, 0, 0, 78),
				BackgroundColor3 = C.ch75,
				BackgroundTransparency = if exploring then 0.4 else 0,
				[CHILDREN] = { Components.corner(8) },
				Parent = rightCol,
			})
			local well: Frame = new("Frame", {
				Name = "Icon",
				Position = UDim2.fromOffset(6, 6),
				Size = UDim2.fromOffset(66, 66),
				BackgroundColor3 = C.ch10,
				[CHILDREN] = {
					Components.corner(8),
					Components.stroke(if item then ChestCommon.rarityColor(item.rarity) else C.ch28, 3),
				},
				Parent = b,
			})
			local ic = Components.text({
				text = I[slot],
				size = 34,
				color = if item then C.inkLight else C.ch45,
				font = Tokens.font.number,
			})
			ic.AnchorPoint = Vector2.new(0.5, 0.5)
			ic.Position = UDim2.fromScale(0.5, 0.5)
			ic.Parent = well
			if Art.put(well, Art.equip(item), { inset = 4 }) then
				ic.Visible = false -- 付けている品の絵（D-254）
			end
			if item then
				if item.grade > 0 then
					local g = Components.text({
						text = "+" .. item.grade,
						size = 21,
						color = C.numHi,
						font = Tokens.font.number,
						stroke = true,
					})
					g.AnchorPoint = Vector2.new(1, 1)
					g.Position = UDim2.new(1, -2, 1, 0)
					g.Parent = well
				end
				local vals: Frame = new("Frame", {
					Name = "Values",
					Position = UDim2.fromOffset(84, 0),
					Size = UDim2.new(1, -92, 1, 0),
					BackgroundTransparency = 1,
					[CHILDREN] = {
						new("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0, 8),
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
					},
					Parent = b,
				})
				for k, v in WarehouseCommon.values(item) do
					if v.icon ~= WarehouseCommon.icon.modifier then
						local pv = pill(v.icon, v.text, 23)
						pv.LayoutOrder = k
						pv.Parent = vals
					end
				end
			end
			if Roster.betterGear(view, adv, slot, master, deps) then
				local up = Components.text({ text = I.up, size = 21, color = C.inkDark, font = Tokens.font.number })
				up.Name = "Better"
				up.AnchorPoint = Vector2.new(0.5, 0.5)
				up.Position = UDim2.new(1, -4, 0, 4)
				up.Size = UDim2.fromOffset(32, 32)
				up.AutomaticSize = Enum.AutomaticSize.None
				up.BackgroundTransparency = 0
				up.BackgroundColor3 = C.okGreen
				new("UICorner", { CornerRadius = UDim.new(0, 16), Parent = up })
				up.Parent = b
			end
			if not exploring then
				b.Activated:Connect(function()
					api.open("EquipSelect", { uid = uid, slot = slot })
				end)
			end
		end
		-- ギフト（最大 giftMax。空きは点線＝転生で増える：D-024）
		local gifts: Frame = new("Frame", {
			Name = "Gifts",
			LayoutOrder = 4,
			Size = UDim2.new(1, 0, 0, 108),
			BackgroundColor3 = C.ch50,
			[CHILDREN] = {
				Components.corner(8),
				Components.padding(8, 8, 8, 8),
				new("UIGridLayout", {
					CellSize = UDim2.new(0.5, -3, 0, 44),
					CellPadding = UDim2.fromOffset(6, 6),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = rightCol,
		})
		for k = 1, master.K.giftMax do
			local g = adv.giftIds[k]
			if g then
				local gift = master.gifts[g]
				local t = pill("", if gift then gift.nameEn else g, 21)
				local medal = Art.icon(Art.gift(g), 28, 0)
				if medal then
					medal.Parent = t -- メダルの絵を語の左に（D-245）
				end
				t.LayoutOrder = k
				t.Parent = gifts
			else
				new("Frame", {
					Name = "Empty" .. k,
					LayoutOrder = k,
					BackgroundTransparency = 1,
					[CHILDREN] = { Components.corner(22), Components.stroke(C.inkMid, 2) },
					Parent = gifts,
				})
			end
		end

		-- 右下：メイン（トレーニング／Rebirth）と、探索中なら理由の札
		local actions = Screen.actionRow(body)
		if exploring then
			local why = pill("", AdvCommon.partyBadge(view, uid) or "", 25)
			why.LayoutOrder = 1
			why.Parent = actions
		end
		local atCap = adv.level >= adv.levelCap
		if atCap then
			local cost = RebirthCommon.cost(adv)
			local main = Components.button({
				kind = if exploring then "disabled" else "gold",
				width = 320,
				icon = RebirthCommon.icon.rebirth, -- 転生の面と同じ（D-245：アイコン＋語）
				label = "Rebirth",
				cost = HubState.formatNumber(cost),
				name = "Rebirth",
				glyph = "A",
				onClick = function()
					local id, prm = RebirthCommon.entry(view, uid)
					api.open(id, prm)
				end,
			})
			main.LayoutOrder = 2
			main.Parent = actions
			-- 転生できる「!」（一覧と同じ赤い印）
			new("TextLabel", {
				Name = "Notice",
				Text = "!",
				TextSize = 23,
				FontFace = Tokens.font.number,
				TextColor3 = C.inkWhite,
				BackgroundColor3 = C.notice,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -6, 0, 6),
				Size = UDim2.fromOffset(32, 32),
				ZIndex = 5,
				[CHILDREN] = { Components.corner(16) },
				Parent = main,
			})
		else
			local cost = Training.sessionCost(adv.level, master.K)
			local can = not exploring and adv.level < Training.levelCap(adv, view, master) and view.gold >= cost
			local main = Components.button({
				kind = if can then "gold" else "disabled",
				width = 320,
				icon = I.train,
				label = Words.train,
				cost = HubState.formatNumber(cost),
				name = "Train",
				glyph = "A",
				onClick = function()
					if held then
						held = false -- 長押しのあとの指離れは1回に数えない
						return
					end
					if not busy then
						send({ type = "Train", adventurerUid = uid, sessions = 1 })
						render()
					end
				end,
			})
			main.LayoutOrder = 2
			main.Parent = actions
			-- 長押し：約0.5秒で連続に入り、1回ずつ送る（ゴールド・上限・指を離すまで。Lv では止めない）
			local face = main:FindFirstChild("Face") :: TextButton?
			if face and can then
				face.InputBegan:Connect(function(input)
					local t = input.UserInputType
					if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then
						return
					end
					holding = true
					task.delay(HOLD_START, function()
						if not holding then
							return
						end
						held = true
						while holding do
							local r = send({ type = "Train", adventurerUid = uid, sessions = 1 })
							if not (r and r.ok) then
								holding = false
								break
							end
							task.wait(HOLD_STEP)
						end
						render()
					end)
				end)
				face.InputEnded:Connect(function(input)
					local t = input.UserInputType
					if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
						holding = false
					end
				end)
			end
		end

		-- 重ねる面
		if overlay == "job" then
			local sc = sheet(body, "JobSheet", UDim2.fromOffset(680, 380), function()
				overlay = nil
				render()
			end)
			vlist(sc, 8)
			local n = 0
			for _, row in master.raw.Items do
				local count = items[row.id] or 0
				if row.kind == "potion_job" and count > 0 and row.jobId ~= adv.jobId then
					n += 1
					local target = master.jobs[row.jobId]
					local ok = JobChange.check(adv, row.jobId, master) == nil
					local lost = #JobChange.unequippableSlots(view, adv, row.jobId, master)
					local b: TextButton = new("TextButton", {
						Name = "Job_" .. row.jobId,
						LayoutOrder = n,
						Text = "",
						AutoButtonColor = false,
						Active = ok,
						Size = UDim2.new(1, 0, 0, 76),
						BackgroundColor3 = C.ch75,
						BackgroundTransparency = if ok then 0 else 0.4,
						ZIndex = 33,
						[CHILDREN] = {
							Components.corner(8),
							Components.padding(0, 14, 0, 14),
							new("UIListLayout", {
								FillDirection = Enum.FillDirection.Horizontal,
								VerticalAlignment = Enum.VerticalAlignment.Center,
								Padding = UDim.new(0, 12),
								SortOrder = Enum.SortOrder.LayoutOrder,
							}),
						},
						Parent = sc,
					})
					local nm = pill(
						if target and target.attackType == "magic" then "@job_magic" else "@job_physical",
						if target then target.nameEn else row.jobId,
						23
					)
					nm.LayoutOrder = 1
					nm.Parent = b
					local gm = HireCommon.growthMarks(row.jobId)
					local k = 2
					for _, s in HireCommon.STATS do
						if gm[s.key] then
							local g = pill(I.up, s.label, 21, C.up)
							g.LayoutOrder = k
							g.Parent = b
							k += 1
						end
					end
					if lost > 0 then
						local w = pill(WarehouseCommon.icon.warehouse, "×" .. lost, 21)
						w.LayoutOrder = 9
						w.Parent = b
					end
					local c = pill(I.jobPotion, "×" .. count, 21)
					c.LayoutOrder = 10
					c.Parent = b
					if ok then
						b.Activated:Connect(function()
							-- 押したらすぐ転職（確認なし：D-231 ①）
							if not busy then
								send({ type = "ChangeJob", adventurerUid = uid, jobId = row.jobId })
								overlay = nil
								render()
							end
						end)
					end
				end
			end
		elseif overlay == "dismiss" then
			-- 取り返しのつかない操作の確認（D-231 ①）。NPC の台詞の扱いで1文だけ文字を出す
			local sc = sheet(body, "DismissSheet", UDim2.fromOffset(500, 300), function()
				overlay = nil
				render()
			end)
			new("UIListLayout", {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 14),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = sc,
			})
			local q = Components.text({
				text = "Dismiss " .. adv.name .. "?",
				size = 25,
				color = C.inkDark,
				font = Tokens.font.display,
			})
			q.LayoutOrder = 1
			q.Parent = sc
			local back = pill("", { I.weapon, I.armor, I.sub, "→", WarehouseCommon.icon.warehouse }, 25)
			back.LayoutOrder = 2
			back.Parent = sc
			local yes = Components.button({
				kind = "brown",
				width = 260,
				height = 66,
				label = "Dismiss",
				name = "DismissYes",
				glyph = "A",
				onClick = function()
					if not busy then
						send({ type = "Dismiss", adventurerUid = uid })
						overlay = nil
						render()
					end
				end,
			})
			yes.LayoutOrder = 3
			yes.Parent = sc
		elseif overlay == "rename" then
			local sc = sheet(body, "RenameSheet", UDim2.fromOffset(560, 240), function()
				overlay = nil
				render()
			end)
			new("UIListLayout", {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 14),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = sc,
			})
			local box: TextBox = new("TextBox", {
				Name = "NameBox",
				LayoutOrder = 1,
				Text = adv.name,
				ClearTextOnFocus = false,
				TextSize = 25,
				FontFace = Tokens.font.display,
				TextColor3 = C.inkLight,
				Size = UDim2.new(1, 0, 0, 66),
				BackgroundColor3 = C.ch13,
				ZIndex = 33,
				[CHILDREN] = { Components.corner(10) },
				Parent = sc,
			})
			local ok = Components.button({
				kind = "gold",
				width = 200,
				height = 66,
				icon = "✓",
				label = Words.ok,
				name = "RenameOk",
				glyph = "A",
				onClick = function()
					if not busy then
						send({ type = "Rename", adventurerUid = uid, name = box.Text })
						overlay = nil
						render()
					end
				end,
			})
			ok.LayoutOrder = 2
			ok.Parent = sc
		end
	end

	render()
	local conn = Session.changed:connect(function()
		if not busy and not holding then
			render()
		end
	end)
	return {
		frame = frame,
		scrim = 1,
		destroy = function()
			holding = false
			conn.disconnect()
		end,
	}
end

Nav.register("AdvDetail", build)

return {}
