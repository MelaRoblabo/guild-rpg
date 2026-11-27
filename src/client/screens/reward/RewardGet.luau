--!strict
-- 獲得の画面（D-286・D-287）。クエストの受け取りと、帰還の宝箱の吹き出しを押したときに出す1枚。
--   - 羊皮紙の面（中央）に題の札（Quests の報酬なら "Rewards"、帰還なら "<リーダー名>'s Party"）。
--   - 物の札を横に並べ、数は 0 からカウントアップ（共通の動きの部品：D-269 ⑤）。宝箱はレアリティを見せない閉じた箱（D-087）。
--   - 下に金のボタン1つ（帰還で宝箱があれば Open＝その宝箱の開封へ、なければ OK）。× は右上（D-222）。
--   params：{ title, tiles = { { kind = "gold"|"chest"|"item", id?, n } }, primary = { icon, label, onClick }? }

local Art = require("../../ui/Art")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local HubState = require("../../hub/HubState")
local Motion = require("../../ui/Motion")
local Nav = require("../../ui/Nav")
local Tokens = require("../../ui/Tokens")
local Words = require("../../ui/Words")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local ITEM_ICON = {
	itm_slot_ticket = Components.icon.ticket,
	itm_potion_appearance_change = "@look_change",
	itm_potion_appearance_keep = "@look_keep",
}

local TILE = 110 -- 物の札の幅（画面の大きさ。ゲームの数値ではない）
local PIC = 84

export type Tile = { kind: string, id: string?, n: number }

local function build(params: any?, api: Nav.Api): Nav.Built
	local p = params or {}
	local tiles: { Tile } = p.tiles or {}
	local frame: Frame = new("Frame", {
		Name = "RewardGet",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	local width = math.max(560, #tiles * (TILE + 12) + 80)
	local panel, content = Components.panel({
		size = UDim2.fromOffset(width, 380),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		title = p.title or Words.title.rewards,
	})
	panel.Name = "Panel"
	panel.Parent = frame
	local close = Components.closeButton(api.close)
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.ZIndex = 20
	close.Parent = panel

	local row: Frame = new("Frame", {
		Name = "Tiles",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 20),
		Size = UDim2.fromOffset(0, PIC + 64),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		[CHILDREN] = {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 12),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = content,
	})
	local counters: { { label: TextLabel, n: number, prefix: string } } = {}
	for i, t in tiles do
		local tile: Frame = new("Frame", {
			Name = "Tile" .. i,
			LayoutOrder = i,
			Size = UDim2.fromOffset(TILE, PIC + 64),
			BackgroundTransparency = 1,
			Parent = row,
		})
		local pic: Frame = new("Frame", {
			Name = "Pic",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(PIC, PIC),
			BackgroundTransparency = 1,
			Parent = tile,
		})
		local icon, image, color, prefix
		if t.kind == "gold" then
			icon, color, prefix = Components.icon.coin, C.coinGold, "+"
		elseif t.kind == "chest" then
			icon, color, prefix = "@chest", C.bronzeHi, "×"
		else
			local id = t.id or ""
			icon, image, color, prefix = (ITEM_ICON :: any)[id] or "◈", Art.item(id), C.inkLight, "×"
		end
		if not Art.put(pic, image) then
			local glyph = Components.text({ text = icon, size = 60, color = color, font = Tokens.font.number })
			glyph.AutomaticSize = Enum.AutomaticSize.None
			glyph.Size = UDim2.fromScale(1, 1)
			glyph.Parent = pic
		end
		local well: Frame = new("Frame", {
			Name = "Well",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.new(1, 0, 0, 54),
			BackgroundColor3 = C.ch13,
			[CHILDREN] = { Components.corner(8) },
			Parent = tile,
		})
		local value = Components.text({ text = prefix .. "0", size = 28, color = C.numHi, font = Tokens.font.number })
		value.Name = "Value"
		value.AutomaticSize = Enum.AutomaticSize.None
		value.Size = UDim2.fromScale(1, 1)
		value.Parent = well
		table.insert(counters, { label = value, n = t.n, prefix = prefix })
	end
	task.defer(function()
		for i, c in counters do
			task.delay((i - 1) * 0.12, function()
				if c.label.Parent then
					Motion.countUp(
						c.label,
						0,
						c.n,
						{ prefix = c.prefix, format = HubState.formatNumber, float = false }
					)
				end
			end)
		end
	end)

	local primary = p.primary
	local btn = Components.button({
		kind = "gold",
		width = 300,
		icon = if primary then primary.icon else "✔",
		label = if primary then primary.label else Words.ok,
		name = "Primary",
		glyph = "A",
		onClick = function()
			if primary and primary.onClick then
				primary.onClick(api)
			else
				api.close()
			end
		end,
	})
	btn.AnchorPoint = Vector2.new(0.5, 1)
	btn.Position = UDim2.new(0.5, 0, 1, -18)
	btn.Parent = content
	return { frame = frame }
end

Nav.register("RewardGet", build)

return {}
