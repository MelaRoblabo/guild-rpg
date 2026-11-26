--!strict
-- S-01 ログイン時のまとめ（D-132・D-208・D-231 ⑬・D-232 ④・D-281）。留守の間に受け取った報酬があれば1枚だけ出す。
--   - 羊皮紙の面（1200×466）に題の札「Welcome Back」。中身は受け取った報酬の合計だけ（D-281）：
--     Gold＝持ち帰ったゴールドの合計／Chests＝宝箱（レアリティごとの数。分からないときはレアリティを表さない閉じた箱：D-087）／
--     Inbox＝受け取り箱に届いた物（アイコン＋数）。増えたものだけ出す（D-218 ⑥）。
--   - 数字は 0 からカウントアップ（共通の動きの部品：D-269 ⑤）。
--   - パーティの行・メンバーの顔・休息ボーナスの月・ギルドLv の行は出さない（D-280・D-281）。
--     パーティごとの獲得は、閉じたあと左の帰還のトーストで見せる（hub/LoginSequence）。
--   - × はない。右下の金＝次へ（▶）だけ（D-231 ⑬・D-232 ④）。

local Art = require("../../ui/Art")
local ChestCommon = require("../chest/ChestCommon")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local HubState = require("../../hub/HubState")
local LoginFlow = require("../../login/LoginFlow")
local Motion = require("../../ui/Motion")
local Nav = require("../../ui/Nav")
local Root = require("../../ui/Root")
local Tokens = require("../../ui/Tokens")
local Words = require("../../ui/Words")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local I = {
	chest = "@chest",
	inbox = "@inbox",
	itm_slot_ticket = Components.icon.ticket,
	itm_potion_appearance_change = "@look_change",
	itm_potion_appearance_keep = "@look_keep",
}

local TILE_ICON = 84 -- 物の絵の大きさ
local WELL_H = 54 -- 数字の暗い凹みの高さ
local GROUP_GAP = 16
local TILE_GAP = 10
local CONTENT_W = 1100 -- 面の中の使える幅（基準の単位）

type Tile = { icon: string?, image: string?, color: Color3, rank: number?, n: number, prefix: string }

local function build(params: any?, _api: Nav.Api): Nav.Built
	local sum = (params :: any).summary :: LoginFlow.Summary
	local onNext = (params :: any).onNext :: () -> ()
	local band = Root.bandBottom()
	local frame: Frame = new("Frame", {
		Name = "LoginSummary",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	local panel, content = Components.panel({
		size = UDim2.new(1, -80, 0, 466),
		position = UDim2.fromOffset(40, band + 16),
		title = Words.title.welcomeBack,
	})
	panel.Name = "Panel"
	panel.Parent = frame
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, GROUP_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = content,
	})

	-- 出す物の組（増えたものだけ：D-218 ⑥）
	local groups: { { name: string, word: string, tiles: { Tile } } } = {}
	if sum.gold > 0 then
		table.insert(groups, {
			name = "Gold",
			word = Words.gold,
			tiles = { { icon = Components.icon.coin, color = C.coinGold, n = sum.gold, prefix = "+" } },
		})
	end
	if sum.chests > 0 then
		local tiles: { Tile } = {}
		for _, c in sum.chestsByRank do
			table.insert(tiles, {
				icon = I.chest,
				image = if c.rank then Art.chest(c.rank, false) else nil,
				color = if c.rank then ChestCommon.rarityColor(c.rank) else C.bronzeHi,
				rank = c.rank,
				n = c.n,
				prefix = "×",
			})
		end
		table.insert(groups, { name = "Chests", word = Words.chests, tiles = tiles })
	end
	if sum.inboxCount > 0 then
		local tiles: { Tile } = {}
		for _, l in sum.inbox do
			if l.kind == "gold" then
				table.insert(tiles, { icon = Components.icon.coin, color = C.coinGold, n = l.n, prefix = "+" })
			elseif l.kind == "chest" then
				table.insert(tiles, {
					icon = I.chest,
					image = if l.rank then Art.chest(l.rank, false) else nil,
					color = if l.rank then ChestCommon.rarityColor(l.rank) else C.bronzeHi,
					rank = l.rank,
					n = l.n,
					prefix = "×",
				})
			elseif l.kind == "item" then
				local id = l.id or ""
				table.insert(
					tiles,
					{ icon = (I :: any)[id] or "◈", image = Art.item(id), color = C.inkLight, n = l.n, prefix = "×" }
				)
			else
				table.insert(tiles, { icon = Components.icon.party, color = C.inkLight, n = l.n, prefix = "×" })
			end
		end
		if #tiles == 0 then
			-- 中身が要約にまだない：届いた件数だけ
			table.insert(tiles, { icon = I.inbox, color = C.bronzeHi, n = sum.inboxCount, prefix = "×" })
		end
		table.insert(groups, { name = "Inbox", word = Words.inbox, tiles = tiles })
	end

	-- 物の数に合わせて札の幅を決める（入りきらないときは狭める）
	local total = 0
	for _, g in groups do
		total += #g.tiles
	end
	local nGroups = #groups
	local free = CONTENT_W
		- nGroups * 20
		- math.max(0, total - nGroups) * TILE_GAP
		- math.max(0, nGroups - 1) * GROUP_GAP
	local tileW = math.clamp(math.floor(free / math.max(total, 1)), TILE_ICON, 150)
	-- 数字が入る幅（ゴールドなど桁の多い数は札を広げる。語を縮めない：D-264）
	local function widthOf(t: Tile): number
		return math.max(tileW, utf8.len(t.prefix .. HubState.formatNumber(t.n)) :: number * 17 + 24)
	end

	local counters: { { label: TextLabel, n: number, prefix: string } } = {}
	for gi, grp in groups do
		local box: Frame = new("Frame", {
			Name = grp.name,
			LayoutOrder = gi,
			Size = UDim2.new(0, 0, 1, -10),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.ch50,
			[CHILDREN] = {
				Components.corner(8),
				Components.padding(14, 10, 14, 10),
				new("UIListLayout", {
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding = UDim.new(0, 14),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = content,
		})
		-- 組の見出し（Gold・Chests・Inbox）
		local head = Components.text({
			text = grp.word,
			size = Tokens.text.label,
			color = C.inkLight,
			font = Tokens.font.display,
			stroke = true,
		})
		head.Name = "Title"
		head.LayoutOrder = 1
		head.Parent = box
		local row: Frame = new("Frame", {
			Name = "Tiles",
			LayoutOrder = 2,
			Size = UDim2.fromOffset(0, TILE_ICON + 14 + WELL_H),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			[CHILDREN] = {
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, TILE_GAP),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = box,
		})
		for ti, t in grp.tiles do
			local tile: Frame = new("Frame", {
				Name = "Tile" .. ti,
				LayoutOrder = ti,
				Size = UDim2.fromOffset(widthOf(t), TILE_ICON + 14 + WELL_H),
				BackgroundTransparency = 1,
				Parent = row,
			})
			local pic: Frame = new("Frame", {
				Name = "Pic",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromOffset(TILE_ICON, TILE_ICON),
				BackgroundTransparency = 1,
				Parent = tile,
			})
			if not Art.put(pic, t.image) then
				local glyph = Components.text({
					text = t.icon or "◈",
					size = 60,
					color = t.color,
					font = Tokens.font.number,
				})
				glyph.AutomaticSize = Enum.AutomaticSize.None
				glyph.Size = UDim2.fromScale(1, 1)
				glyph.Parent = pic
			end
			if t.rank then
				-- レアリティの形（色だけで分けない：ChestCommon）
				local mark: Frame = new("Frame", {
					Name = "Rarity",
					AnchorPoint = Vector2.new(1, 1),
					Position = UDim2.new(1, 6, 1, 4),
					Size = UDim2.fromOffset(36, 36),
					BackgroundColor3 = C.ch13,
					ZIndex = 4,
					[CHILDREN] = { Components.corner(18), Components.stroke(t.color, 2) },
					Parent = pic,
				})
				local shape = Components.text({
					text = ChestCommon.rarityShape(t.rank),
					size = 21,
					color = t.color,
					font = Tokens.font.number,
				})
				shape.AutomaticSize = Enum.AutomaticSize.None
				shape.Size = UDim2.fromScale(1, 1)
				shape.ZIndex = 5
				shape.Parent = mark
			end
			local well: Frame = new("Frame", {
				Name = "Well",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 1),
				Size = UDim2.new(1, 0, 0, WELL_H),
				BackgroundColor3 = C.ch13,
				[CHILDREN] = { Components.corner(8) },
				Parent = tile,
			})
			local value = Components.text({
				text = t.prefix .. "0",
				size = if t.prefix == "+" then 30 else 28,
				color = C.numHi,
				font = Tokens.font.number,
			})
			value.Name = "Value"
			value.AutomaticSize = Enum.AutomaticSize.None
			value.Size = UDim2.fromScale(1, 1)
			value.Parent = well
			table.insert(counters, { label = value, n = t.n, prefix = t.prefix })
		end
	end

	-- 数字は 0 からカウントアップ（D-269 ⑤）。左から少しずつずらす
	task.defer(function()
		for i, c in counters do
			task.delay((i - 1) * 0.12, function()
				if c.label.Parent then
					Motion.countUp(c.label, 0, c.n, {
						prefix = c.prefix,
						format = HubState.formatNumber,
						float = false,
					})
				end
			end)
		end
	end)

	-- 右下の金：次へ
	local nextBtn = Components.button({
		kind = "gold",
		width = 320,
		icon = "▶",
		label = Words.next,
		name = "Next",
		glyph = "A",
		onClick = onNext,
	})
	nextBtn.AnchorPoint = Vector2.new(1, 1)
	nextBtn.Position = UDim2.new(1, -40, 1, -24)
	nextBtn.Parent = frame
	return { frame = frame }
end

Nav.register("LoginSummary", build)

return {}
