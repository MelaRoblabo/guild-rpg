--!strict
-- 倉庫の画面（S-50・S-51）で共有するもの：アイコン、品の性能の札、マス、重ねる面、スイッチ。

local Formulas = require("@game/ReplicatedStorage/Core/Formulas")
local Inventory = require("@game/ReplicatedStorage/Core/Inventory")
local ChestCommon = require("../chest/ChestCommon")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Art = require("../../ui/Art")
local Tokens = require("../../ui/Tokens")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local WarehouseCommon = {}

WarehouseCommon.deps = { value = Formulas.bulkSellValue, price = Inventory.equipmentSellPrice }

-- 仮のアイコン（文字）。素材ができたら画像に差し替える（D-227 ②）
WarehouseCommon.icon = {
	weapon = "@slot_weapon",
	armor = "@slot_armor",
	sub = "@slot_sub",
	items = "@ticket",
	sort = "▦",
	recycle = "@gold",
	bulk = "@gold",
	pin = "@pin",
	modifier = "◉",
	warehouse = "@warehouse",
	warn = "⚠",
	potion = "◈",
	desc = "@down",
	asc = "@up",
}

-- 並べ替えの種類のアイコン（レアリティ＝形、性能＝剣、売却額＝コイン、新しい順＝＋）
WarehouseCommon.sortIcon = { rarity = "@special", power = "@attack", sell = "@gold", new = "✚" }

-- 品の性能の札：{ icon, text }（武器＝攻撃、防具・盾＝防御、指輪＝能力、護符＝XP の倍率。D-231 ⑭）
function WarehouseCommon.values(item: any): { { icon: string, text: string } }
	local base = master.equipmentBases[item.baseId]
	if base == nil then
		return {}
	end
	local mult = Formulas.equipMult(item.rarity, item.grade, item.itemLevel or 1, master.K)
	local out = {}
	if base.atk then
		table.insert(out, { icon = "@attack", text = tostring(math.floor(base.atk * mult)) })
	end
	local def = math.floor((base.pdef or 0) * mult) + math.floor((base.mdef or 0) * mult)
	if base.pdef or base.mdef then
		table.insert(out, { icon = "@pdef", text = tostring(def) })
	end
	for stat, v in base.stats or {} do
		table.insert(out, { icon = "", text = string.upper(stat) .. " " .. math.floor(v * mult) })
	end
	if base.expPct then
		local x = 1 + Formulas.equipExpPct(item, master)
		table.insert(out, { icon = "", text = string.format("XP ×%.2f", x) })
	end
	if item.modifierId then
		local mod = master.modifiers[item.modifierId]
		if mod then
			table.insert(out, { icon = WarehouseCommon.icon.modifier, text = mod.nameEn })
		end
	end
	return out
end

-- 品の名前（修飾語＋装備名＋グレード）
function WarehouseCommon.fullName(item: any): string
	return ChestCommon.itemName(item) .. (if item.grade > 0 then " +" .. item.grade else "")
end

-- 装備できる職業（英語名）
function WarehouseCommon.jobs(item: any): { string }
	local out = {}
	for _, job in master.raw.Jobs do
		if Inventory.canEquip(job.id, item.baseId, master) then
			table.insert(out, job.nameEn)
		end
	end
	return out
end

-- 暗い凹みの札（アイコンと文字）
function WarehouseCommon.pill(icon: string, text: string, size: number?, iconColor: Color3?): Frame
	local h = if size and size < 25 then 36 else 44
	local pill: Frame = new("Frame", {
		Name = "Pill",
		Size = UDim2.fromOffset(0, h),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ch13,
		[CHILDREN] = {
			Components.corner(h / 2),
			Components.padding(0, 14, 0, 10),
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	})
	if icon ~= "" then
		local ic = Components.text({
			text = icon,
			size = size or 25,
			color = iconColor or C.bronzeHi,
			font = Tokens.font.number,
		})
		ic.LayoutOrder = 1
		ic.Parent = pill
	end
	local t = Components.text({ text = text, size = size or 25, color = C.inkLight, font = Tokens.font.number })
	t.LayoutOrder = 2
	t.Parent = pill
	return pill
end

-- 角の小さな丸（レアリティの形・ピン・選んだ印）
local function badge(parent: GuiObject, text: string, fill: Color3, ink: Color3, pos: UDim2, z: number): TextLabel
	return new("TextLabel", {
		Name = "Badge",
		Text = text,
		TextSize = 17,
		FontFace = Tokens.font.number,
		TextColor3 = ink,
		BackgroundColor3 = fill,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		Size = UDim2.fromOffset(30, 30),
		ZIndex = z,
		[CHILDREN] = { Components.corner(15), Components.stroke(C.ch13, 2) },
		Parent = parent,
	})
end

export type TileProps = {
	name: string,
	icon: string,
	image: string?, -- 品の絵（あれば記号の代わりに出す：15章 §4）
	rarity: number?,
	grade: number?,
	count: number?,
	modifier: boolean?,
	pinned: boolean?,
	selected: boolean?,
	order: number,
	onClick: () -> (),
}

-- 格子のマス（106×104）：品の絵＋レアリティの色の枠と形（左上）＋グレード（右下）＋修飾語（左下）＋ピン／選んだ印（右上）
function WarehouseCommon.tile(p: TileProps): TextButton
	local rar = if p.rarity then ChestCommon.rarityColor(p.rarity) else C.ch28
	local b: TextButton = new("TextButton", {
		Name = p.name,
		LayoutOrder = p.order,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.ch13,
		ZIndex = if p.selected then 9 else 8, -- 選んだマスの印が隣のマスの下にならないように
		[CHILDREN] = {
			Components.corner(10),
			Components.stroke(if p.selected then C.selAmber else rar, 3),
		},
	})
	local ic = Components.text({ text = p.icon, size = 42, color = C.inkLight, font = Tokens.font.number })
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.5)
	ic.ZIndex = 9
	ic.Parent = b
	if Art.put(b, p.image, { inset = 10, zIndex = 9 }) then
		ic.Visible = false
	end
	if p.rarity then
		badge(b, ChestCommon.rarityShape(p.rarity), rar, C.inkWhite, UDim2.fromOffset(4, 4), 10)
	end
	if p.grade and p.grade > 0 then
		local g = Components.text({
			text = "+" .. p.grade,
			size = 23,
			color = C.numHi,
			font = Tokens.font.number,
			stroke = true,
		})
		g.AnchorPoint = Vector2.new(1, 1)
		g.Position = UDim2.new(1, -6, 1, -2)
		g.ZIndex = 10
		g.Parent = b
	end
	if p.count then
		local c = WarehouseCommon.pill("", "×" .. p.count, 21)
		c.AnchorPoint = Vector2.new(1, 1)
		c.Position = UDim2.new(1, -4, 1, -4)
		c.ZIndex = 10
		c.Parent = b
	end
	if p.modifier then
		local m = Components.text({
			text = WarehouseCommon.icon.modifier,
			size = 21,
			color = C.bronzeHi,
			font = Tokens.font.number,
		})
		m.AnchorPoint = Vector2.new(0, 1)
		m.Position = UDim2.new(0, 6, 1, -4)
		m.ZIndex = 10
		m.Parent = b
	end
	if p.selected then
		badge(b, "✓", C.selAmber, C.inkDark, UDim2.new(1, -4, 0, 4), 11)
	elseif p.pinned then
		badge(b, WarehouseCommon.icon.pin, C.ch10, C.inkLight, UDim2.new(1, -4, 0, 4), 11)
	end
	b.Activated:Connect(p.onClick)
	return b
end

-- 押せる丸角の道具ボタン（茶。66×66 以上）
function WarehouseCommon.tool(name: string, icon: string, width: number, onClick: () -> ()): TextButton
	local b: TextButton = new("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(width, 66),
		BackgroundColor3 = C.secondary,
		ZIndex = 10,
		[CHILDREN] = { Components.corner(18), Components.stroke(C.secondaryRim, 3) },
	})
	-- 語を含むときは語の大きさ（D-245）
	local hasWord = utf8.len(icon) ~= nil and (utf8.len(icon) :: number) > 3
	local t = Components.text({
		text = icon,
		size = if hasWord then 21 else 30,
		color = C.inkLight,
		font = if hasWord then Tokens.font.display else Tokens.font.number,
	})
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(0.5, 0.5)
	t.ZIndex = 11
	t.Parent = b
	b.Activated:Connect(onClick)
	return b
end

-- オン／オフのスイッチ（120×66）
function WarehouseCommon.switch(name: string, on: boolean, onToggle: () -> ()): TextButton
	local b: TextButton = new("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(120, 66),
		BackgroundTransparency = 1,
		ZIndex = 12,
	})
	new("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(6, 11),
		Size = UDim2.fromOffset(108, 44),
		BackgroundColor3 = if on then C.selAmber else C.ch28,
		ZIndex = 12,
		[CHILDREN] = { Components.corner(22), Components.stroke(if on then C.ctaGoldRim else C.ch16, 3) },
		Parent = b,
	})
	new("Frame", {
		Name = "Knob",
		Position = UDim2.fromOffset(if on then 60 else 4, 5),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = C.ch75,
		ZIndex = 13,
		[CHILDREN] = { Components.corner(28), Components.stroke(C.bronze, 3) },
		Parent = b,
	})
	b.Activated:Connect(onToggle)
	return b
end

-- レアリティの段（6つの形を並べ、上限まで色を付ける）
function WarehouseCommon.raritySteps(maxRarity: number, width: number, onPick: (number) -> ()): Frame
	local n = master.rarityCount
	local row: Frame = new("Frame", {
		Name = "RaritySteps",
		Size = UDim2.fromOffset(width, 74),
		BackgroundColor3 = C.ch52,
		ZIndex = 12,
		[CHILDREN] = {
			Components.corner(37),
			Components.padding(4, 4, 4, 4),
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 4),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	})
	local w = math.floor((width - 8 - 4 * (n - 1)) / n)
	for r = 1, n do
		local sel = r == maxRarity
		local b: TextButton = new("TextButton", {
			Name = "Rarity" .. r,
			LayoutOrder = r,
			Text = ChestCommon.rarityShape(r),
			TextSize = 30,
			FontFace = Tokens.font.number,
			TextColor3 = if r <= maxRarity then ChestCommon.rarityColor(r) else C.ch45,
			AutoButtonColor = false,
			Size = UDim2.fromOffset(w, 66),
			BackgroundColor3 = if sel then C.selAmber else C.ch28,
			ZIndex = 13,
			[CHILDREN] = { Components.corner(33) },
			Parent = row,
		})
		b.Activated:Connect(function()
			onPick(r)
		end)
	end
	return row
end

return WarehouseCommon
