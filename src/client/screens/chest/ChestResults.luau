--!strict
-- S-31b+e 結果（開封結果の表とまとめを1枚に：D-223 ①・D-268 ④⑤）。
--   - 強くなる品のカードを、品が主役の順に読ませる（D-268 ④）：
--       品の大きな絵・名前・レアリティの語・枠の語 → 差（DEF 3 → 9（+6））→ 小さな顔と「Equip to 名前」。
--     Equip を押すと品の絵が顔へ飛んで吸い込まれ、差の数字がカウントアップする。装備済みは ✓。
--     入りきらない分は「▲ +N」の札（品の一覧・絞り込みは倉庫 S-50 へ）。
--   - 下の1行：Gold +N・Auto-sold N・To Warehouse +N（語つき：D-264 ②。倉庫で止まったときは警告の色）。
--   - 右下：Sell（茶。今の装備より弱いものを売る：D-167・D-207）と、続けて開ける金（同じ山の残り。All なら全部の山）。
--   - × で閉じたらマップへ戻る。宝箱が残っているときだけ宝箱の一覧へ戻る（D-268 ⑤）。

local ChestCommon = require("./ChestCommon")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Art = require("../../ui/Art")
local Game = require("@game/ReplicatedStorage/Core/Game")
local HubState = require("../../hub/HubState")
local Motion = require("../../ui/Motion")
local Nav = require("../../ui/Nav")
local Portrait = require("../../ui/Portrait")
local Root = require("../../ui/Root")
local Screen = require("../Screen")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local Guide = require("../../hub/Guide")
local Words = require("../../ui/Words")
local master = require("../../Master")

local C = Tokens.color
local I = ChestCommon.icon
local new = Create.new
local CHILDREN = Create.Children

local CARDS = 2 -- 1枚に並べるカードの数（D-223 ①の見本）
local SLOT_WORD = { weapon = "Weapon", armor = "Armor", sub = "Accessory" } -- 枠の語（D-268 ④）
local VALUE_WORD = { weapon = "ATK", armor = "DEF", sub = "DEF" } -- 差の数字に添える語（D-264 ②）

local function build(params: any?, api: Nav.Api): Nav.Built
	local batch: ChestCommon.Batch = (params :: any).batch
	-- 初回の誘導の Equip の段：結果に Equip が出るならそれを光らせ、出ないならここで済んだ扱い（D-244 ①・D-246 ①）
	local guideEquip = false
	if Guide.is("equip") then
		local v = Session.view
		for i, u in batch.plan do
			local adv = v and v.adventurers[u.advUid]
			local item = v and v.equipment[u.itemUid]
			if i <= CARDS and adv and item and item.equippedBy ~= adv.uid and not ChestCommon.isBusy(v, adv.uid) then
				guideEquip = true
				break
			end
		end
		if not guideEquip then
			Guide.done("equip")
		end
	end
	local band = Root.bandBottom()
	local frame = Screen.scene("ChestResults")
	-- 閉じたらマップへ。宝箱が残っているときだけ一覧へ（D-268 ⑤）
	Screen.closeTopRight(frame, function()
		local v = Session.view
		if v and #ChestCommon.allPiles(v) > 0 then
			api.close()
		else
			api.home()
		end
	end)
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local busy = false
	local justEquipped: { [string]: boolean } = {} -- Equip した直後のカード（差をカウントアップで見せる）

	local render: () -> ()
	render = function()
		body:ClearAllChildren()
		local view = Session.view
		if view == nil then
			return
		end
		local panel, content = Components.panel({
			size = UDim2.new(1, -80, 0, 408),
			position = UDim2.fromOffset(40, band + 44),
		})
		panel.Name = "Upgrades"
		panel.Parent = body
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = content,
		})
		local shown = 0
		for i, u in batch.plan do
			if i > CARDS then
				break
			end
			local adv = view.adventurers[u.advUid]
			local item = view.equipment[u.itemUid]
			if adv and item then
				shown += 1
				local base = master.equipmentBases[item.baseId]
				local slot = (base and base.slot) or u.slot
				local card: Frame = new("Frame", {
					Name = "Card" .. i,
					LayoutOrder = i,
					Size = UDim2.new(0, 478, 1, 0),
					BackgroundColor3 = C.ch75,
					[CHILDREN] = {
						Components.corner(8),
						Components.padding(10, 12, 10, 12),
						new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
					},
					Parent = content,
				})
				-- 1. 品：大きな絵・名前・レアリティの語・枠の語
				local top: Frame = new("Frame", {
					Name = "Item",
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 132),
					BackgroundTransparency = 1,
					Parent = card,
				})
				local pic: Frame = new("Frame", {
					Name = "Picture",
					Size = UDim2.fromOffset(132, 132),
					BackgroundColor3 = C.ch13,
					[CHILDREN] = {
						Components.corner(14),
						Components.stroke(ChestCommon.rarityColor(item.rarity), 4),
					},
					Parent = top,
				})
				if not Art.put(pic, Art.equip(item), { inset = 8 }) then
					local g = Components.text({
						text = "@slot_" .. slot,
						size = 64,
						color = C.inkLight,
						font = Tokens.font.number,
					})
					g.AutomaticSize = Enum.AutomaticSize.None
					g.Size = UDim2.fromScale(1, 1)
					g.Parent = pic
				end
				local info: Frame = new("Frame", {
					Position = UDim2.fromOffset(146, 0),
					Size = UDim2.new(1, -146, 1, 0),
					BackgroundTransparency = 1,
					[CHILDREN] = {
						new("UIListLayout", {
							Padding = UDim.new(0, 6),
							VerticalAlignment = Enum.VerticalAlignment.Center,
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
					},
					Parent = top,
				})
				local itemName = Components.text({
					text = ChestCommon.itemName(item),
					size = 25,
					color = C.inkDark,
					font = Tokens.font.display,
					xAlign = Enum.TextXAlignment.Left,
				})
				itemName.AutomaticSize = Enum.AutomaticSize.Y
				itemName.Size = UDim2.fromScale(1, 0)
				itemName.TextWrapped = true
				itemName.LayoutOrder = 1
				itemName.Parent = info
				local rr = master.raw.Rarities[item.rarity]
				local tag = Components.text({
					text = ChestCommon.rarityShape(item.rarity)
						.. " "
						.. (if rr then rr.nameEn else "")
						.. "  ·  "
						.. (SLOT_WORD[slot] or ""),
					size = 21,
					color = C.inkMid,
					font = Tokens.font.bodyStrong,
					xAlign = Enum.TextXAlignment.Left,
				})
				tag.LayoutOrder = 2
				tag.Parent = info
				-- 2. 差：DEF 3 → 9（+6）と比べる値の棒
				local word = VALUE_WORD[slot] or ""
				local diff = u.value - u.current
				local deltaLine = Components.text({
					text = string.format(
						"%s %d → %d (%s%d)",
						word,
						u.current,
						u.value,
						if diff >= 0 then "+" else "",
						diff
					),
					size = 30,
					color = if diff > 0 then C.up else C.inkDark,
					font = Tokens.font.number,
					xAlign = Enum.TextXAlignment.Left,
				})
				deltaLine.Name = "Delta"
				deltaLine.LayoutOrder = 2
				deltaLine.Parent = card
				local row = ChestCommon.compareRow(u.slot, u.value, u.current)
				row.LayoutOrder = 3
				row.Parent = card
				-- 3. 誰に：小さな顔と Equip to 名前（済んだら ✓）
				local who: Frame = new("Frame", {
					Name = "Who",
					LayoutOrder = 4,
					Size = UDim2.new(1, 0, 0, 80),
					BackgroundTransparency = 1,
					Parent = card,
				})
				local face: Frame = new("Frame", {
					Name = "Face",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromScale(0, 0.5),
					Size = UDim2.fromOffset(72, 72),
					BackgroundColor3 = C.ch13,
					[CHILDREN] = { Components.corner(12) },
					Parent = who,
				})
				Portrait.fill(face, adv.appearanceId)
				local equipped = item.equippedBy == adv.uid
				if equipped then
					local nm = Components.text({
						text = adv.name,
						size = 25,
						color = C.inkDark,
						font = Tokens.font.display,
						xAlign = Enum.TextXAlignment.Left,
					})
					nm.AnchorPoint = Vector2.new(0, 0.5)
					nm.Position = UDim2.new(0, 86, 0.5, 0)
					nm.Parent = who
					local mark: Frame = new("Frame", {
						Name = "Equipped",
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.fromScale(1, 0.5),
						Size = UDim2.fromOffset(56, 56),
						BackgroundColor3 = C.okGreen,
						[CHILDREN] = { Components.corner(28), Components.stroke(C.ch13, 3) },
						Parent = who,
					})
					local ok =
						Components.text({ text = "✓", size = 30, color = C.inkDark, font = Tokens.font.number })
					ok.AutomaticSize = Enum.AutomaticSize.None
					ok.Size = UDim2.fromScale(1, 1)
					ok.Parent = mark
					if justEquipped[item.uid] then
						justEquipped[item.uid] = nil
						-- 付けた直後：差の数字が今の値から新しい値へカウントアップする
						Motion.countUp(deltaLine, u.current, u.value, {
							float = false,
							format = function(n: number): string
								return string.format(
									"%s %d → %d (%s%d)",
									word,
									u.current,
									n,
									if diff >= 0 then "+" else "",
									diff
								)
							end,
						})
						if diff ~= 0 then
							Motion.floatText(
								face,
								(if diff > 0 then "+" else "") .. diff,
								if diff > 0 then C.up else C.warn
							)
						end
						Motion.bump(face, 0.2)
					end
				else
					local canEquip = not ChestCommon.isBusy(view, adv.uid)
					local equip = Components.button({
						kind = if canEquip then "gold" else "disabled",
						width = 300,
						height = 66,
						-- 付ける枠のアイコン（Equip＝枠：D-256。鎧なら鎧）
						icon = "@slot_" .. slot,
						label = Words.equip .. " to " .. adv.name,
						name = "Equip",
						reason = Words.reason.partyOut,
						onClick = function()
							if busy then
								return
							end
							busy = true
							local r = Session.sendAndWait({
								type = "Equip",
								adventurerUid = adv.uid,
								equipmentUid = item.uid,
							})
							busy = false
							Guide.done("equip")
							if not (r and r.ok) then
								render()
								return
							end
							-- 品の絵が顔へ飛んで吸い込まれる（D-268 ④）
							local vis: Frame = new("Frame", {
								BackgroundColor3 = C.ch13,
								[CHILDREN] = {
									Components.corner(14),
									Components.stroke(ChestCommon.rarityColor(item.rarity), 4),
								},
							})
							Art.put(vis, Art.equip(item), { inset = 8 })
							justEquipped[item.uid] = true
							Motion.fly({
								from = pic,
								to = Motion.center(face),
								visual = vis,
								size = 132,
								endSize = 40,
								onArrive = render,
							})
						end,
					})
					equip.AnchorPoint = Vector2.new(1, 0.5)
					equip.Position = UDim2.fromScale(1, 0.5)
					equip.Parent = who
					-- 初回の誘導：最初の Equip だけ光らせる（下端に近いので指は上から）
					if guideEquip and canEquip and Guide.is("equip") and shown == 1 then
						Guide.mark(equip, true, 18, true)
					end
				end
			end
		end
		-- 入りきらない強化の数（倉庫へ）
		local more = batch.upgradeItems - shown
		if more > 0 then
			local tile: Frame = new("Frame", {
				Name = "More",
				LayoutOrder = 10,
				Size = UDim2.new(1, -(shown * (478 + 12)), 1, 0),
				BackgroundColor3 = C.ch75,
				[CHILDREN] = {
					Components.corner(8),
					Components.stroke(C.ch45, 2),
					new("UIListLayout", {
						Padding = UDim.new(0, 12),
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				},
				Parent = content,
			})
			local up =
				Components.text({ text = Components.icon.up, size = 30, color = C.up, font = Tokens.font.number })
			up.LayoutOrder = 1
			up.Parent = tile
			local n = Components.text({ text = "+" .. more, size = 40, color = C.inkDark, font = Tokens.font.display })
			n.LayoutOrder = 2
			n.Parent = tile
			local w = Components.text({ text = I.warehouse, size = 30, color = C.inkMid, font = Tokens.font.number })
			w.LayoutOrder = 3
			w.Parent = tile
		end

		-- 強くなった人がいなければ面を出さず、下の1行を真ん中に大きく出す（主役を1つに：D-218 ②）
		local empty = shown == 0 and more <= 0
		if empty then
			panel:Destroy()
		end
		-- 下の1行：Gold・Auto-sold・To Warehouse（語つき：D-264 ②・D-268 ③）
		local line: Frame = new("Frame", {
			Name = "Summary",
			Position = if empty then UDim2.new(0.5, 0, 0, band + 260) else UDim2.fromOffset(40, band + 524),
			AnchorPoint = if empty then Vector2.new(0.5, 0.5) else Vector2.zero,
			Size = UDim2.fromOffset(0, 52),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			ZIndex = 8,
			[CHILDREN] = {
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 12),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = body,
		})
		if empty then
			new("UIScale", { Scale = 1.5, Parent = line })
		end
		local gold = Components.chip(I.gold, "Gold +" .. HubState.formatNumber(batch.gold))
		gold.LayoutOrder = 1
		gold.Parent = line
		if batch.autoSold > 0 then
			local sold = Components.chip(I.recycle, "Auto-sold " .. HubState.formatNumber(batch.autoSold), C.bronzeHi)
			sold.LayoutOrder = 2
			sold.Parent = line
		end
		local stopped = batch.stoppedBy == "WAREHOUSE_FULL"
		local ware = Components.chip(
			if stopped then I.warn else I.warehouse,
			"To Warehouse +" .. HubState.formatNumber(#batch.itemUids),
			if stopped then C.warnDark else C.bronzeHi
		)
		ware.LayoutOrder = 3
		if stopped then
			Components.stroke(C.warnDark, 2).Parent = ware
		end
		ware.Parent = line

		-- 右下：Sell（茶）と続けて開ける（金）
		local actions = Screen.actionRow(body)
		local preview = Game.query.bulkSellPreview(view, batch.itemUids, master)
		if preview.count > 0 then
			local sell = Components.button({
				kind = "brown",
				width = 240,
				height = 66,
				icon = I.recycle,
				label = "Sell",
				cost = HubState.formatNumber(preview.gold),
				name = "Sell",
				glyph = "X",
				onClick = function()
					if busy then
						return
					end
					busy = true
					Session.sendAndWait({ type = "BulkSell", equipmentUids = preview.equipmentUids })
					busy = false
					render()
				end,
			})
			sell.LayoutOrder = 1
			sell.Parent = actions
		end
		local piles: { string }
		local label: string? = nil
		local icon: string
		if batch.all then
			piles = ChestCommon.allPiles(view)
			icon = I.all
			label = Words.openAll
		else
			local key = batch.piles[1]
			local left = ChestCommon.pileCount(view, key)
			piles = if left > 0 then { key } else {}
			icon = ChestCommon.pileInfo(key).icon
			label = Words.open .. (if left > 0 then " ×" .. math.min(left, master.K.chestBatchOpen) else "")
		end
		local canOpen = #piles > 0 and not ChestCommon.warehouseBlocked(view)
		local again = Components.button({
			kind = if canOpen then "gold" else "disabled",
			width = 320,
			icon = icon,
			label = label,
			name = "Again",
			glyph = "A",
			onClick = function()
				if busy then
					return
				end
				busy = true
				local next = ChestCommon.open(piles, batch.all)
				busy = false
				if next then
					api.replace("ChestOpening", { batch = next })
				else
					render()
				end
			end,
		})
		again.LayoutOrder = 2
		again.Parent = actions
	end

	render()
	return { frame = frame, scrim = 1 }
end

Nav.register("ChestResults", build)

return {}
