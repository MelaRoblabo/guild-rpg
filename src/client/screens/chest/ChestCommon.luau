--!strict
-- 宝箱の画面（S-30・S-31、D-223）で共有するもの。
--   - 宝箱の山の見せ方（普通はダンジョン名、特別な宝箱はアイコン：D-166）
--   - レアリティの色と形（色だけで分けない。開けるまで見せない：D-087）
--   - 開封の実行（山ごとに OpenChests を送り、結果を1つの束にまとめる）
--   - 「誰が強くなるか」（chest/Upgrades に core の関数を渡す）

local Formulas = require("@game/ReplicatedStorage/Core/Formulas")
local Inventory = require("@game/ReplicatedStorage/Core/Inventory")
local Party = require("@game/ReplicatedStorage/Core/Party")
local Chest = require("@game/ReplicatedStorage/Core/Chest")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local Upgrades = require("../../chest/Upgrades")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local ChestCommon = {}

ChestCommon.deps = { value = Formulas.bulkSellValue, canEquip = Inventory.canEquip }

-- 仮のアイコン（文字）。素材ができたら画像に差し替える（D-227 ②）
ChestCommon.icon = {
	chest = "▣",
	all = "▦",
	inbox = "▤",
	claim = "✓",
	sword = "⚔",
	armor = "🛡",
	recycle = "⇄",
	warehouse = "⌂",
	pin = "📌", -- 保護＝ピン（D-217）
	equip = "♟",
	next = "▶",
	warn = "⚠",
	gold = "G",
	ticket = "🎟",
	unique = "★",
}

-- 特別な宝箱の山のアイコン（D-166）
local SPECIAL_ICON = {
	["special:quest"] = "✓",
	["special:login"] = "▦",
	["special:playtime"] = "◉",
	["special:raid"] = "⚡",
	["special:rare"] = "◈",
}

-- 受け取り箱の出どころのアイコン（D-164）
ChestCommon.sourceIcon = {
	quest = "✓",
	login = "▦",
	playtime = "◉",
	raid = "⚡",
	referral = "❖",
}
-- 受け取り箱の行の記号に添える語（D-251 ①）
ChestCommon.sourceWord = {
	quest = "Quest",
	login = "Login",
	playtime = "Playtime",
	raid = "Raid",
	referral = "Friend",
}

export type PileInfo = { pileKey: string, special: boolean, icon: string, name: string }

-- 山の見せ方：普通の山はダンジョン名、特別な宝箱はアイコン（レアダンジョンは相当するダンジョン名も：D-171）
function ChestCommon.pileInfo(pileKey: string): PileInfo
	local d = master.dungeons[pileKey]
	if d then
		return { pileKey = pileKey, special = false, icon = ChestCommon.icon.chest, name = d.nameEn }
	end
	local rareOf = string.match(pileKey, "^special:rare:(.+)$")
	if rareOf then
		local rd = master.dungeons[rareOf]
		return {
			pileKey = pileKey,
			special = true,
			icon = SPECIAL_ICON["special:rare"],
			name = if rd then rd.nameEn else "",
		}
	end
	return { pileKey = pileKey, special = true, icon = SPECIAL_ICON[pileKey] or ChestCommon.icon.chest, name = "" }
end

-- レアリティの色と形（形は Guild UI の6つ。仮の記号）
local RARITY_COLOR = { C.rarCommon, C.rarUncommon, C.rarRare, C.rarEpic, C.rarLegend, C.rarMythic }
local RARITY_SHAPE = { "◎", "●", "◆", "▲", "★", "✚" } -- コモンは封をした箱（▣）と分ける

function ChestCommon.rarityColor(rank: number): Color3
	return RARITY_COLOR[rank] or C.rarCommon
end

function ChestCommon.rarityShape(rank: number): string
	return RARITY_SHAPE[rank] or RARITY_SHAPE[1]
end

-- 品の名前（修飾語＋装備名。グレードは別に出す）
function ChestCommon.itemName(item: any): string
	local base = master.equipmentBases[item.baseId]
	local mod = if item.modifierId then master.modifiers[item.modifierId] else nil
	return (if mod then mod.nameEn .. " " else "") .. (if base then base.nameEn else item.baseId)
end

function ChestCommon.isBusy(view: any, advUid: string): boolean
	return Party.isAdventurerBusy(view, advUid)
end

-- 倉庫がいっぱいで、次の宝箱を開けられない（1箱で増えうる装備の最大数より空きが少ない：Game.OpenChests と同じ判定）
function ChestCommon.warehouseBlocked(view: any): boolean
	return Inventory.warehouseFree(view) < Chest.maxEquipmentPerChest(master)
end

function ChestCommon.warehouse(view: any): (number, number)
	return Inventory.warehouseUsage(view), view.expansions.warehouseSize
end

function ChestCommon.pileCount(view: any, pileKey: string): number
	for _, c in view.chests or {} do
		if c.pileKey == pileKey then
			return c.count
		end
	end
	return 0
end

-- 開封の束（S-31 の画面が受け渡す）
export type Batch = {
	piles: { string }, -- 開けた山（続けて開けるときに使う）
	all: boolean, -- All で開けたか
	normal: { any }, -- 演出なし（Chest.open の結果に effect・order・autoSold などが付いたもの）
	special: { any }, -- 演出あり（レアリティの低い順。最後が一番派手：D-089）
	opened: number,
	gold: number, -- 宝箱のゴールド＋素材の売却＋自動売却
	autoSold: number, -- 自動売却した装備の数
	itemUids: { string }, -- 倉庫に入った装備
	stoppedBy: string?, -- "WAREHOUSE_FULL"
	plan: { Upgrades.Upgrade }, -- 開けた直後に計算した「誰が強くなるか」（装備する前の比べる値で見せる）
	upgradeItems: number, -- 誰かが強くなる品の数
}

-- 山ごとに OpenChests を送り、1つの束にまとめる。1つも開けられなければ nil
function ChestCommon.open(piles: { string }, all: boolean): Batch?
	local batch: Batch = {
		piles = piles,
		all = all,
		normal = {},
		special = {},
		opened = 0,
		gold = 0,
		autoSold = 0,
		itemUids = {},
		stoppedBy = nil,
		plan = {},
		upgradeItems = 0,
	}
	for i, pileKey in piles do
		local send = if i == #piles then Session.sendAndWait else Session.send
		local r = send({ type = "OpenChests", pileKey = pileKey, count = master.K.chestBatchOpen })
		if r and r.ok then
			for _, e in r.events or {} do
				if e.type == "ChestsOpened" then
					batch.opened += e.opened
					batch.stoppedBy = batch.stoppedBy or e.stoppedBy
					for _, list in { e.normal, e.special } do
						for _, res in list do
							batch.gold += (res.gold or 0) + (res.soldItemsGold or 0) + (res.autoSoldGold or 0)
							batch.autoSold += if res.autoSold then #res.autoSold else 0
							for _, uid in res.equipmentUids do
								table.insert(batch.itemUids, uid)
							end
						end
					end
					for _, res in e.normal do
						table.insert(batch.normal, res)
					end
					for _, res in e.special do
						table.insert(batch.special, res)
					end
				end
			end
		elseif r and r.error == "WAREHOUSE_FULL" then
			batch.stoppedBy = "WAREHOUSE_FULL"
			break
		end
	end
	if batch.opened == 0 then
		return nil
	end
	-- 複数の山を開けたときも、演出つきはレアリティの低い順（D-089）
	table.sort(batch.special, function(a, b)
		return a.rank < b.rank
	end)
	-- 最後の山の結果の後で、届いた状態から計算する（sendAndWait で状態が届いている）
	local view = Session.view
	batch.plan = Upgrades.plan(view, batch.itemUids, master, ChestCommon.deps)
	local n = 0
	for _, uid in batch.itemUids do
		if #Upgrades.forItem(view, uid, master, ChestCommon.deps) > 0 then
			n += 1
		end
	end
	batch.upgradeItems = n
	return batch
end

-- 開けられる山の一覧（All：山ごとに最大 chestBatchOpen 個：D-129）
function ChestCommon.allPiles(view: any): { string }
	local out = {}
	for _, c in view.chests or {} do
		if c.count > 0 then
			table.insert(out, c.pileKey)
		end
	end
	return out
end

-- 比べる値の行（明かす画面と結果のカード）：アイコン、棒（今の装備の位置に目盛り）、数字、▲差（D-130・D-218 ③）
function ChestCommon.compareRow(slot: string, value: number, current: number): Frame
	local row: Frame = new("Frame", {
		Name = "Compare",
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = C.ch75,
		[CHILDREN] = {
			Components.corner(6),
			Components.padding(0, 12, 0, 12),
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 12),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	})
	local icon = Components.text({
		text = if slot == "weapon" then ChestCommon.icon.sword else ChestCommon.icon.armor,
		size = 25,
		color = C.inkDark,
		font = Tokens.font.number,
	})
	icon.AutomaticSize = Enum.AutomaticSize.None
	icon.Size = UDim2.fromOffset(32, 32)
	icon.LayoutOrder = 1
	icon.Parent = row
	local track: Frame = new("Frame", {
		Name = "Bar",
		LayoutOrder = 2,
		Size = UDim2.new(1, -(32 + 80 + 24), 0, Tokens.size.barHLg),
		BackgroundColor3 = C.barTrack,
		ClipsDescendants = true,
		[CHILDREN] = { Components.corner(Tokens.radius.radiusBar) },
		Parent = row,
	})
	-- 棒の右端は大きい方の値（新しい品が右端に届く。差は目盛りとの間に見える）
	local top = math.max(value, current, 1)
	new("Frame", {
		Name = "Fill",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(value / top, -4, 1, -4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		[CHILDREN] = { Components.corner(Tokens.radius.radiusBar), Components.gradient(C.barFill, C.barFillLow) },
		Parent = track,
	})
	if current > 0 then
		new("Frame", {
			Name = "PrevTick",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(current / top, 0),
			Size = UDim2.new(0, 4, 1, 0),
			BackgroundColor3 = C.inkLight,
			ZIndex = 3,
			Parent = track,
		})
	end
	local num = Components.text({
		text = tostring(value),
		size = 23,
		color = C.inkWhite,
		font = Tokens.font.number,
		stroke = true,
	})
	num.AutomaticSize = Enum.AutomaticSize.None
	num.Size = UDim2.fromScale(1, 1)
	num.ZIndex = 4
	num.Parent = track
	local d = value - current
	local delta = Components.text({
		text = if d > 0 then Components.icon.up .. d else "",
		size = 25,
		color = C.up,
		font = Tokens.font.number,
		xAlign = Enum.TextXAlignment.Left,
	})
	delta.AutomaticSize = Enum.AutomaticSize.None
	delta.Size = UDim2.fromOffset(80, 32)
	delta.LayoutOrder = 3
	delta.Parent = row
	return row
end

-- バストアップの仮の枠
function ChestCommon.bust(size: Vector2): Frame
	local f: Frame = new("Frame", {
		Name = "Bust",
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = C.ch10,
		[CHILDREN] = { Components.corner(8), Components.stroke(C.ch16, 6) },
	})
	local t = Components.text({ text = "Bust-up", size = 21, color = C.ch45 })
	t.AutomaticSize = Enum.AutomaticSize.None
	t.Size = UDim2.fromScale(1, 1)
	t.Parent = f
	return f
end

return ChestCommon
