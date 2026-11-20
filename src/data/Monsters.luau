--!strict
-- モンスター（ゲーム仕様書05章、D-003, D-008, Q-005）
-- 強さは持たない（ダンジョンの基準値で決まる：D-003）。種族タグと攻撃種別のみ。
-- raceTag: undead / beast / construct / demon / spirit / knight / aquatic / plant / dragon
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
	-- 水没神殿
	{ id = "mon_merfolk_raider", name = "半魚の略奪者", raceTag = "aquatic", attackType = "physical" },
	{ id = "mon_drowned_sailor", name = "溺れた水夫", raceTag = "undead", attackType = "physical" },
	{ id = "mon_sea_witch", name = "海の魔女", raceTag = "aquatic", attackType = "magic" },
	{ id = "mon_tide_priestess", name = "潮の巫女", raceTag = "aquatic", attackType = "magic" },
	-- 霧の大森林
	{ id = "mon_dire_wolf", name = "ダイアウルフ", raceTag = "beast", attackType = "physical" },
	{ id = "mon_treant", name = "トレント", raceTag = "plant", attackType = "physical" },
	{ id = "mon_mist_sprite", name = "霧の精", raceTag = "spirit", attackType = "magic" },
	{ id = "mon_ancient_bear", name = "古の大熊", raceTag = "beast", attackType = "physical" },
	-- 地下大迷宮
	{ id = "mon_labyrinth_bull", name = "迷宮の牛頭", raceTag = "beast", attackType = "physical" },
	{ id = "mon_mimic", name = "ミミック", raceTag = "construct", attackType = "physical" },
	{ id = "mon_deep_sorcerer", name = "深淵の術師", raceTag = "demon", attackType = "magic" },
	{ id = "mon_labyrinth_warden", name = "迷宮の番人", raceTag = "construct", attackType = "physical" },
	-- 呪われた修道院
	{ id = "mon_fallen_monk", name = "堕ちた修道士", raceTag = "undead", attackType = "physical" },
	{ id = "mon_wraith", name = "レイス", raceTag = "undead", attackType = "magic" },
	{ id = "mon_abbot_lich", name = "院長リッチ", raceTag = "undead", attackType = "magic" },
	-- 鋼鉄の要塞
	{ id = "mon_iron_golem", name = "アイアンゴーレム", raceTag = "construct", attackType = "physical" },
	{ id = "mon_clockwork_soldier", name = "機巧兵", raceTag = "construct", attackType = "physical" },
	{ id = "mon_arcane_turret", name = "魔導砲台", raceTag = "construct", attackType = "magic" },
	{ id = "mon_fortress_colossus", name = "要塞巨兵", raceTag = "construct", attackType = "physical" },
	-- 竜の巣
	{ id = "mon_drake", name = "ドレイク", raceTag = "dragon", attackType = "physical" },
	{ id = "mon_wyvern", name = "ワイバーン", raceTag = "dragon", attackType = "physical" },
	{ id = "mon_dragon_cultist", name = "竜信奉者", raceTag = "knight", attackType = "magic" },
	{ id = "mon_elder_dragon", name = "古竜", raceTag = "dragon", attackType = "magic" },
	-- 魔界の門
	{ id = "mon_demon_knight", name = "魔騎士", raceTag = "demon", attackType = "physical" },
	{ id = "mon_hellhound", name = "ヘルハウンド", raceTag = "demon", attackType = "physical" },
	{ id = "mon_abyss_caster", name = "奈落の詠唱者", raceTag = "demon", attackType = "magic" },
	{ id = "mon_gate_keeper", name = "門の守護魔", raceTag = "demon", attackType = "magic" },
	-- 天空の玉座
	{ id = "mon_sky_sentinel", name = "天空の哨兵", raceTag = "construct", attackType = "physical" },
	{ id = "mon_storm_spirit", name = "嵐の精霊", raceTag = "spirit", attackType = "magic" },
	{ id = "mon_fallen_seraph", name = "堕ちた天翼", raceTag = "spirit", attackType = "magic" },
	{ id = "mon_sky_tyrant", name = "天空の暴君", raceTag = "dragon", attackType = "physical" },
}
