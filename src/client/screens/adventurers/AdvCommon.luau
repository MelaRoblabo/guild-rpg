--!strict
-- 冒険者の画面（S-40・S-41）で共有するもの：deps、アイコン、パーティの状態の印。

local Formulas = require("@game/ReplicatedStorage/Core/Formulas")
local Game = require("@game/ReplicatedStorage/Core/Game")
local Inventory = require("@game/ReplicatedStorage/Core/Inventory")
local Party = require("@game/ReplicatedStorage/Core/Party")
local HubState = require("../../hub/HubState")

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
	all = "♟",
	sort = "▦",
	party = "♟",
	pin = "📌",
	up = "▲",
	rebirth = "★",
	male = "♂",
	female = "♀",
	warn = "⚠",
	train = "▲",
	rename = "✏",
	look = "🎲",
	jobPotion = "🧪",
	dismiss = "🚪",
	weapon = "⚔",
	armor = "🛡",
	sub = "❖",
	attack = "⚔",
	pdef = "🛡",
	mdef = "◈",
	bell = "🔔",
	hp = "✚",
	clock = "🕒",
}

-- 職業系統のタブの語（D-231 ⑤：系統のアイコンは分からないので短い語）
AdvCommon.lineWord = { warrior = "Warrior", scout = "Scout", mage = "Mage", support = "Support" }

-- パーティの状態の印（メイン画面の一覧と同じ意味）
local STATE_GLYPH = { moving = "▶", exploring = "●", returning = "◀", waiting = "⌂" }

function AdvCommon.partyBadge(view: any, uid: string): string?
	local p = Party.find(view, uid)
	if p == nil then
		return nil
	end
	local s = HubState.status(view, p)
	return AdvCommon.icon.party .. p .. " " .. (STATE_GLYPH[s.state] or "⌂")
end

return AdvCommon
