--!strict
-- マスターデータの束（docs/system/04_master_data.md）
-- ファイルを追加したらここに登録する。検証は src/core/MasterData.luau が行う。

return {
	Constants = require("./Constants"),
	Rarities = require("./Rarities"),
	Jobs = require("./Jobs"),
	Gifts = require("./Gifts"),
	Modifiers = require("./Modifiers"),
	EquipmentBases = require("./EquipmentBases"),
	Items = require("./Items"),
	Monsters = require("./Monsters"),
	Dungeons = require("./Dungeons"),
	LootTables = require("./LootTables"),
	StarterSet = require("./StarterSet"),
}
