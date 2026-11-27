--!strict
-- 冒険者の画面（S-40・S-41）で共有するもの：deps、アイコン、パーティの状態の印。

local Formulas = require("@game/ReplicatedStorage/Core/Formulas")
local Game = require("@game/ReplicatedStorage/Core/Game")
local Inventory = require("@game/ReplicatedStorage/Core/Inventory")
local Party = require("@game/ReplicatedStorage/Core/Party")
local HubState = require("../../hub/HubState")
local PartyIcon = require("../../ui/PartyIcon")

local AdvCommon = {}

AdvCommon.deps = {
	snapshot = Game.query.snapshot,
	busy = Party.isAdventurerBusy,
	find = Party.find,
	value = Formulas.bulkSellValue,
	canEquip = Inventory.canEquip,
}

-- 仮のアイコン（文字）。素材ができたら画像に差し替える（D-227 ②）
AdvCommon.icon = {
	all = "@roster",
	sort = "▦",
	party = "@party",
	pin = "@pin",
	up = "@up",
	rebirth = "@rebirth",
	male = "♂",
	female = "♀",
	warn = "⚠",
	train = "@train",
	rename = "✏",
	look = "@look_change",
	jobPotion = "🧪",
	dismiss = "🚪",
	weapon = "@slot_weapon",
	armor = "@slot_armor",
	sub = "@slot_sub",
	attack = "@attack",
	pdef = "@pdef",
	mdef = "@mdef",
	bell = "🔔",
	hp = "@stat_hp",
	clock = "@time",
}

-- 職業系統のタブの語（D-231 ⑤：系統のアイコンは分からないので短い語）
AdvCommon.lineWord = { warrior = "Warrior", scout = "Scout", mage = "Mage", support = "Support" }

-- パーティの状態の印（メイン画面の一覧と同じ意味）
local STATE_GLYPH =
	{ moving = "@cart_moving", exploring = "@cart_exploring", returning = "@cart_returning", waiting = "@cart_waiting" }

-- 札の中身（状態の印：Components.setParts に渡す）。パーティにいなければ nil。
--   パーティは番号ではなくリーダーの顔で見せる（D-288）。顔は AdvCommon.partyIcon で札の左に置く
function AdvCommon.partyBadge(view: any, uid: string): { string }?
	local p = Party.find(view, uid)
	if p == nil then
		return nil
	end
	local s = HubState.status(view, p)
	return { STATE_GLYPH[s.state] or "@cart_waiting" }
end

-- その人がいるパーティのリーダーの顔の小さな丸（D-288）。パーティにいなければ nil
function AdvCommon.partyIcon(view: any, uid: string, size: number): Frame?
	local p = Party.find(view, uid)
	if p == nil then
		return nil
	end
	local icon = PartyIcon.make(size)
	PartyIcon.set(icon, view, p)
	return icon
end

return AdvCommon
