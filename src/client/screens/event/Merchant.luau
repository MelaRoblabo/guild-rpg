--!strict
-- 旅の商人（BuyFromMerchant。D-152・D-179・D-189・D-202・D-204・D-231 ⑭）。マップの印を触ると開く羊皮紙の面。
--   - 品のカード（触って選ぶ＝琥珀の輪）：レアリティの帯と形、品の絵、名前（2行まで）、性能、一番強くなる差の▲、値段。
--   - 手持ちのゴールドは右上にずっと出す。値段が足りない品は警告の色。
--   - 面の中の下：残り時間（176×56）と、右の金＝買う（手提げ袋＋費用）。倉庫がいっぱい／ゴールドが足りないときは押せない色と理由の札。
--   - 買った品は判子＋暗く。商人で買った装備は自動売却しない（D-152）。
--   - D-274：買えるのはパーティが商人のところにいる間だけ。向かっている間は「Arrives in」と灰色の Buy（押すと理由）。
--     着いたら左下に Leave（帰る）。帰り始めると商人は去り、面も閉じる。

local Formulas = require("@game/ReplicatedStorage/Core/Formulas")
local Game = require("@game/ReplicatedStorage/Core/Game")
local Inventory = require("@game/ReplicatedStorage/Core/Inventory")
local Party = require("@game/ReplicatedStorage/Core/Party")
local Art = require("../../ui/Art")
local ChestCommon = require("../chest/ChestCommon")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local HubState = require("../../hub/HubState")
local MerchantView = require("../../event/MerchantView")
local Nav = require("../../ui/Nav")
local Root = require("../../ui/Root")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local Words = require("../../ui/Words")
local WarehouseCommon = require("../warehouse/WarehouseCommon")
local master = require("../../Master")

local C = Tokens.color
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

local function clock(s: number): string
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d", s // 60, s % 60)
end

local NPC_W = 300 -- 商人の絵の枠の幅

local function build(params: any?, api: Nav.Api): Nav.Built
	local slot = (params :: any).slot :: number
	local band = Root.bandBottom()
	local frame: Frame = new("Frame", {
		Name = "Merchant",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local pick = 1
	local busy = false
	-- 品はサーバーで作る（seed は要約で隠している：Session.query）。開いたときと買ったあとに取り直す
	local goods: any = Session.query({ kind = "merchant", eventSlot = slot })
	local alive = true
	local render: () -> ()

	render = function()
		body:ClearAllChildren()
		local view = Session.view
		if view == nil then
			return
		end
		local now = Session.now()
		local q = goods
		-- 向かっている・着いている商人（D-274）。いなくなったら閉じる
		local here: any = nil
		for _, p in Game.query.merchantPresence(view, now, master) do
			if p.eventSlot == slot and p.phase ~= "open" then
				here = p
			end
		end
		if q == nil or here == nil then
			api.close()
			return
		end
		local arrived = here.phase == "here"
		local items = q.items
		if items[pick] == nil or items[pick].bought then
			pick = 1
			for i, it in items do
				if not it.bought then
					pick = i
					break
				end
			end
		end
		-- 右上：手持ちのゴールド（ずっと出す）
		local cur = items[pick]
		local poor = cur ~= nil and view.gold < cur.price
		local gold = Components.chip(Components.icon.coin, HubState.formatNumber(view.gold))
		gold.AnchorPoint = Vector2.new(1, 0)
		gold.Position = UDim2.new(1, -40, 0, band + 12)
		if poor then
			Components.stroke(C.warnDark, 2).Parent = gold
		end
		gold.Parent = body
		-- 旅の商人の絵（D-239。受付嬢と同じ暗い枠：S-20）。絵がなければ品の面を全幅に
		local left = 40
		local npc = Art.npc("npc_merchant")
		if npc then
			local stall, stallContent = Components.panel({
				size = UDim2.fromOffset(NPC_W, 504),
				position = UDim2.fromOffset(40, band + 90),
				dark = true,
			})
			stall.Name = "MerchantNpc"
			stall.Parent = body
			Art.put(stallContent, npc, { scaleType = Enum.ScaleType.Crop })
			left = 40 + NPC_W + 16
		end
		local panel, content = Components.panel({
			size = UDim2.new(1, -(left + 40), 0, 504),
			position = UDim2.fromOffset(left, band + 90),
			title = "@merchant",
		})
		panel.Name = "Panel"
		panel.Parent = body
		local close = Components.closeButton(api.close)
		close.AnchorPoint = Vector2.new(0.5, 0.5)
		close.Position = UDim2.new(1, -12, 0, 12)
		close.ZIndex = 20
		close.Parent = panel
		-- 品のカード
		local grid: Frame = new("Frame", {
			Name = "Goods",
			Size = UDim2.new(1, 0, 1, -92),
			BackgroundColor3 = C.ch50,
			[CHILDREN] = {
				Components.corner(8),
				Components.padding(10, 10, 10, 10),
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 12),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = content,
		})
		for i, it in items do
			local sel = i == pick
			local base = master.equipmentBases[it.baseId]
			local card: TextButton = new("TextButton", {
				Name = "Good" .. i,
				LayoutOrder = i,
				Text = "",
				AutoButtonColor = false,
				Active = not it.bought,
				Size = UDim2.new(1 / #items, -12 * (#items - 1) / #items, 1, 0),
				BackgroundColor3 = if it.bought then C.ch68 else C.ch75,
				[CHILDREN] = {
					Components.corner(10),
					Components.stroke(
						if sel then C.selAmber else ChestCommon.rarityColor(it.rarity),
						if sel then 4 else 3
					),
					Components.padding(12, 10, 10, 10),
					new("UIListLayout", {
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						Padding = UDim.new(0, 6),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				},
				Parent = grid,
			})
			card.Activated:Connect(function()
				if not it.bought then
					pick = i
					render()
				end
			end)
			local function txt(order: number, t: string, size: number, color: Color3, wrap: boolean?)
				local l = Components.text({ text = t, size = size, color = color, font = Tokens.font.number })
				l.LayoutOrder = order
				if wrap then
					l.AutomaticSize = Enum.AutomaticSize.Y
					l.Size = UDim2.fromScale(1, 0)
					l.TextWrapped = true
				end
				l.TextTransparency = if it.bought then 0.55 else 0
				l.Parent = card
			end
			txt(1, ChestCommon.rarityShape(it.rarity), 25, ChestCommon.rarityColor(it.rarity))
			-- 装備の絵（見た目の段：D-254）。絵がなければ枠のアイコン
			local art = Art.icon(Art.equip(it), 88, 2)
			if art then
				art.ImageTransparency = if it.bought then 0.55 else 0
				art.Parent = card
			else
				txt(2, WarehouseCommon.icon[if base then base.slot else "weapon"] or "?", 44, C.inkDark)
			end
			txt(3, WarehouseCommon.fullName(it), 21, C.inkDark, true)
			local vals = WarehouseCommon.values(it)
			if vals[1] then
				local p = WarehouseCommon.pill(vals[1].icon, vals[1].text, 23)
				p.LayoutOrder = 4
				p.Parent = card
			end
			local best = if it.bought then nil else MerchantView.best(view, it, master, deps)
			if best then
				txt(5, if best.ratio then string.format("▲×%.2f", best.ratio) else "▲" .. best.delta, 25, C.up)
			end
			local price = WarehouseCommon.pill(Components.icon.coin, HubState.formatNumber(it.price), 23, nil)
			price.LayoutOrder = 6
			if view.gold < it.price and not it.bought then
				for _, c in price:GetDescendants() do
					if c:IsA("TextLabel") then
						c.TextColor3 = C.warnDark
					end
				end
			end
			price.Parent = card
			if it.bought then
				local stamp = Components.text({ text = "✓", size = 64, color = C.bronze, font = Tokens.font.number })
				stamp.Name = "Stamp"
				stamp.AnchorPoint = Vector2.new(0.5, 0.5)
				stamp.Position = UDim2.fromScale(0.5, 0.45)
				stamp.Rotation = -14
				stamp.Parent = card
			end
		end
		-- 下：残り時間と買う
		local foot: Frame = new("Frame", {
			Name = "Footer",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 82),
			BackgroundTransparency = 1,
			Parent = content,
		})
		if arrived then
			-- 帰る（D-274）：押すと帰り始め、商人は去る
			local leave = Components.button({
				kind = "brown",
				width = 200,
				icon = "◀",
				label = Words.leave,
				name = "Leave",
				glyph = "X",
				onClick = function()
					if busy then
						return
					end
					busy = true
					local r = Session.sendAndWait({ type = "LeaveMerchant", partyIndex = here.partyIndex })
					busy = false
					if r and r.ok then
						api.close()
					else
						render()
					end
				end,
			})
			leave.AnchorPoint = Vector2.new(0, 0.5)
			leave.Position = UDim2.fromScale(0, 0.5)
			leave.Parent = foot
		else
			-- 向かっている：着くまでの時計（D-274）
			local timer = WarehouseCommon.pill("@time", Words.arrivesIn .. " " .. clock(here.arriveIn or 0), 30)
			timer.AnchorPoint = Vector2.new(0, 0.5)
			timer.Position = UDim2.fromScale(0, 0.5)
			timer.Parent = foot
		end
		local full = Inventory.warehouseFree(view) < 1
		local can = arrived and cur ~= nil and not cur.bought and not full and not poor
		if arrived and (full or poor) then
			local why =
				WarehouseCommon.pill(if full then WarehouseCommon.icon.warehouse else Components.icon.coin, "⚠", 25)
			why.AnchorPoint = Vector2.new(1, 0.5)
			why.Position = UDim2.new(1, -340, 0.5, 0)
			why.Parent = foot
		end
		local buy = Components.button({
			kind = if can then "gold" else "disabled",
			width = 320,
			icon = "@merchant",
			label = Words.buy,
			cost = if cur then HubState.formatNumber(cur.price) else nil,
			name = "Buy",
			reason = if not arrived then Words.reason.partyOnTheWay else nil, -- 着くまで買えない（D-274）
			glyph = "A",
			onClick = function()
				if busy or not can then
					return
				end
				busy = true
				Session.sendAndWait({ type = "BuyFromMerchant", eventSlot = slot, itemIndex = pick })
				goods = Session.query({ kind = "merchant", eventSlot = slot })
				busy = false
				render()
			end,
		})
		buy.AnchorPoint = Vector2.new(1, 0.5)
		buy.Position = UDim2.fromScale(1, 0.5)
		buy.Parent = foot
	end

	render()
	task.spawn(function()
		while alive do
			task.wait(1)
			if alive and not busy then
				render()
			end
		end
	end)
	return {
		frame = frame,
		destroy = function()
			alive = false
		end,
	}
end

Nav.register("Merchant", build)

return {}
