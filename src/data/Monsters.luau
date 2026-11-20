--!strict
-- モンスター（ゲーム仕様書05章、D-003, D-008, Q-005）
-- 強さは持たない（ダンジョンの基準値で決まる：D-003）。種族タグと攻撃種別のみ。
-- raceTag: undead / beast / construct / demon / spirit / knight
-- attackType: physical / magic

return {
	-- 古い墓地
	{ id = "mon_skeleton", name = "スケルトン", raceTag = "undead", attackType = "physical" },
	{ id = "mon_ghost", name = "ゴースト", raceTag = "undead", attackType = "magic" },
	{ id = "mon_ghoul", name = "グール", raceTag = "undead", attackType = "physical" },
	{ id = "mon_giant_rat", name = "大ネズミ", raceTag = "beast", attackType = "physical" },
	{ id = "mon_bone_lord", name = "骨の君主", raceTag = "undead", attackType = "physical" },
	-- 罠の遺跡
	{ id = "mon_ruin_wolf", name = "遺跡狼", raceTag = "beast", attackType = "physical" },
	{ id = "mon_clay_golem", name = "クレイゴーレム", raceTag = "construct", attackType = "physical" },
	{ id = "mon_imp", name = "インプ", raceTag = "demon", attackType = "magic" },
	{ id = "mon_stone_guardian", name = "石の守護者", raceTag = "construct", attackType = "physical" },
	-- 封印の塔
	{ id = "mon_wisp", name = "ウィスプ", raceTag = "spirit", attackType = "magic" },
	{ id = "mon_gargoyle", name = "ガーゴイル", raceTag = "demon", attackType = "physical" },
	{ id = "mon_shade_sorcerer", name = "影の術師", raceTag = "spirit", attackType = "magic" },
	{ id = "mon_sealed_archmage", name = "封じられた大魔導", raceTag = "spirit", attackType = "magic" },
	-- 騎士の古城
	{ id = "mon_cursed_knight", name = "呪われた騎士", raceTag = "knight", attackType = "physical" },
	{ id = "mon_armored_hound", name = "鎧の猟犬", raceTag = "beast", attackType = "physical" },
	{ id = "mon_dark_chaplain", name = "闇の従軍司祭", raceTag = "knight", attackType = "magic" },
	{ id = "mon_fallen_lord", name = "堕ちた城主", raceTag = "knight", attackType = "physical" },
}
