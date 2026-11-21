--!strict
-- レアリティ（ゲーム仕様書06章、D-085）。rank は 1 からの連番。
-- ゲームを拡張するときは末尾に行を足す（D-085）。足したら次も合わせて伸ばす：
--   Constants.equipRarityMult / sellRarityMult、各ダンジョンの chestRarityWeights と chestEffectMinRarity
--   （tools/sim/DungeonTemplates。演出が入る割合は Constants.chestEffectRate に収める：D-090）
-- リリース時はミシック（6）が最上位。

return {
	{ id = "rar_common", rank = 1, name = "コモン" },
	{ id = "rar_uncommon", rank = 2, name = "アンコモン" },
	{ id = "rar_rare", rank = 3, name = "レア" },
	{ id = "rar_epic", rank = 4, name = "エピック" },
	{ id = "rar_legend", rank = 5, name = "レジェンド" },
	{ id = "rar_mythic", rank = 6, name = "ミシック" },
}
