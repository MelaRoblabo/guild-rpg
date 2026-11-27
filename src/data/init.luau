--!strict
-- マスターデータの束（docs/system/04_master_data.md）
-- ファイルを追加したらここに登録する。検証は src/core/MasterData.luau が行う。

return {
	Constants = require("@self/Constants"),
	Rarities = require("@self/Rarities"),
	Jobs = require("@self/Jobs"),
	Gifts = require("@self/Gifts"),
	Modifiers = require("@self/Modifiers"),
	EquipmentBases = require("@self/EquipmentBases"),
	EquipmentLooks = require("@self/EquipmentLooks"),
	Items = require("@self/Items"),
	Monsters = require("@self/Monsters"),
	Dungeons = require("@self/Dungeons"),
	LootTables = require("@self/LootTables"),
	StarterSet = require("@self/StarterSet"),
	Appearances = require("@self/Appearances"),
	Names = require("@self/Names"),
	Uniques = require("@self/Uniques"),
	GuildLevels = require("@self/GuildLevels"),
	Expansions = require("@self/Expansions"),
	DailyTraits = require("@self/DailyTraits"),
	SpecialChests = require("@self/SpecialChests"),
	Quests = require("@self/Quests"),
	LoginBonus = require("@self/LoginBonus"),
	PlaytimeRewards = require("@self/PlaytimeRewards"),
	MapEvents = require("@self/MapEvents"),
	Images = require("@self/Images"),
	BalanceTargets = require("@self/BalanceTargets"), -- バランスの目標（ツール用。MB）
}
