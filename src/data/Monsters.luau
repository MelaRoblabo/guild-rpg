--!strict
-- モンスター（ゲーム仕様書05章、D-003, D-008, Q-005）
-- 強さは持たない（ダンジョンの基準値で決まる：D-003）。種族タグと攻撃種別のみ。
-- raceTag: undead / beast / construct / demon / spirit / knight / aquatic / plant / dragon
-- attackType: physical / magic

return {
	-- 古い墓地
	{ id = "mon_skeleton", name = "スケルトン", nameEn = "Skeleton", raceTag = "undead", attackType = "physical" },
	{ id = "mon_ghost", name = "ゴースト", nameEn = "Ghost", raceTag = "undead", attackType = "magic" },
	{ id = "mon_ghoul", name = "グール", nameEn = "Ghoul", raceTag = "undead", attackType = "physical" },
	{ id = "mon_giant_rat", name = "大ネズミ", nameEn = "Giant Rat", raceTag = "beast", attackType = "physical" },
	{ id = "mon_bone_lord", name = "骨の君主", nameEn = "Bone Lord", raceTag = "undead", attackType = "physical" },
	-- 罠の遺跡
	{ id = "mon_ruin_wolf", name = "遺跡狼", nameEn = "Ruin Wolf", raceTag = "beast", attackType = "physical" },
	{
		id = "mon_clay_golem",
		name = "クレイゴーレム",
		nameEn = "Clay Golem",
		raceTag = "construct",
		attackType = "physical",
	},
	{ id = "mon_imp", name = "インプ", nameEn = "Imp", raceTag = "demon", attackType = "magic" },
	{
		id = "mon_stone_guardian",
		name = "石の守護者",
		nameEn = "Stone Guardian",
		raceTag = "construct",
		attackType = "physical",
	},
	-- 封印の塔
	{ id = "mon_wisp", name = "ウィスプ", nameEn = "Wisp", raceTag = "spirit", attackType = "magic" },
	{ id = "mon_gargoyle", name = "ガーゴイル", nameEn = "Gargoyle", raceTag = "demon", attackType = "physical" },
	{
		id = "mon_shade_sorcerer",
		name = "影の術師",
		nameEn = "Shade Sorcerer",
		raceTag = "spirit",
		attackType = "magic",
	},
	{
		id = "mon_sealed_archmage",
		name = "封じられた大魔導",
		nameEn = "Sealed Archmage",
		raceTag = "spirit",
		attackType = "magic",
	},
	-- 騎士の古城
	{
		id = "mon_cursed_knight",
		name = "呪われた騎士",
		nameEn = "Cursed Knight",
		raceTag = "knight",
		attackType = "physical",
	},
	{
		id = "mon_armored_hound",
		name = "鎧の猟犬",
		nameEn = "Armored Hound",
		raceTag = "beast",
		attackType = "physical",
	},
	{
		id = "mon_dark_chaplain",
		name = "闇の従軍司祭",
		nameEn = "Dark Chaplain",
		raceTag = "knight",
		attackType = "magic",
	},
	{
		id = "mon_fallen_lord",
		name = "堕ちた城主",
		nameEn = "Fallen Lord",
		raceTag = "knight",
		attackType = "physical",
	},
	-- 水没神殿
	{
		id = "mon_merfolk_raider",
		name = "半魚の略奪者",
		nameEn = "Merfolk Raider",
		raceTag = "aquatic",
		attackType = "physical",
	},
	{
		id = "mon_drowned_sailor",
		name = "溺れた水夫",
		nameEn = "Drowned Sailor",
		raceTag = "undead",
		attackType = "physical",
	},
	{ id = "mon_sea_witch", name = "海の魔女", nameEn = "Sea Witch", raceTag = "aquatic", attackType = "magic" },
	{
		id = "mon_tide_priestess",
		name = "潮の巫女",
		nameEn = "Tide Priestess",
		raceTag = "aquatic",
		attackType = "magic",
	},
	-- 霧の大森林
	{
		id = "mon_dire_wolf",
		name = "ダイアウルフ",
		nameEn = "Dire Wolf",
		raceTag = "beast",
		attackType = "physical",
	},
	{ id = "mon_treant", name = "トレント", nameEn = "Treant", raceTag = "plant", attackType = "physical" },
	{ id = "mon_mist_sprite", name = "霧の精", nameEn = "Mist Sprite", raceTag = "spirit", attackType = "magic" },
	{
		id = "mon_ancient_bear",
		name = "古の大熊",
		nameEn = "Ancient Bear",
		raceTag = "beast",
		attackType = "physical",
	},
	-- 地下大迷宮
	{
		id = "mon_labyrinth_bull",
		name = "迷宮の牛頭",
		nameEn = "Labyrinth Bull",
		raceTag = "beast",
		attackType = "physical",
	},
	{ id = "mon_mimic", name = "ミミック", nameEn = "Mimic", raceTag = "construct", attackType = "physical" },
	{
		id = "mon_deep_sorcerer",
		name = "深淵の術師",
		nameEn = "Deep Sorcerer",
		raceTag = "demon",
		attackType = "magic",
	},
	{
		id = "mon_labyrinth_warden",
		name = "迷宮の番人",
		nameEn = "Labyrinth Warden",
		raceTag = "construct",
		attackType = "physical",
	},
	-- 呪われた修道院
	{
		id = "mon_fallen_monk",
		name = "堕ちた修道士",
		nameEn = "Fallen Monk",
		raceTag = "undead",
		attackType = "physical",
	},
	{ id = "mon_wraith", name = "レイス", nameEn = "Wraith", raceTag = "undead", attackType = "magic" },
	{
		id = "mon_abbot_lich",
		name = "院長リッチ",
		nameEn = "Lich Abbot",
		raceTag = "undead",
		attackType = "magic",
	},
	-- 鋼鉄の要塞
	{
		id = "mon_iron_golem",
		name = "アイアンゴーレム",
		nameEn = "Iron Golem",
		raceTag = "construct",
		attackType = "physical",
	},
	{
		id = "mon_clockwork_soldier",
		name = "機巧兵",
		nameEn = "Clockwork Soldier",
		raceTag = "construct",
		attackType = "physical",
	},
	{
		id = "mon_arcane_turret",
		name = "魔導砲台",
		nameEn = "Arcane Turret",
		raceTag = "construct",
		attackType = "magic",
	},
	{
		id = "mon_fortress_colossus",
		name = "要塞巨兵",
		nameEn = "Fortress Colossus",
		raceTag = "construct",
		attackType = "physical",
	},
	-- 竜の巣
	{ id = "mon_drake", name = "ドレイク", nameEn = "Drake", raceTag = "dragon", attackType = "physical" },
	{ id = "mon_wyvern", name = "ワイバーン", nameEn = "Wyvern", raceTag = "dragon", attackType = "physical" },
	{
		id = "mon_dragon_cultist",
		name = "竜信奉者",
		nameEn = "Dragon Cultist",
		raceTag = "knight",
		attackType = "magic",
	},
	{ id = "mon_elder_dragon", name = "古竜", nameEn = "Elder Dragon", raceTag = "dragon", attackType = "magic" },
	-- 魔界の門
	{
		id = "mon_demon_knight",
		name = "魔騎士",
		nameEn = "Demon Knight",
		raceTag = "demon",
		attackType = "physical",
	},
	{
		id = "mon_hellhound",
		name = "ヘルハウンド",
		nameEn = "Hellhound",
		raceTag = "demon",
		attackType = "physical",
	},
	{
		id = "mon_abyss_caster",
		name = "奈落の詠唱者",
		nameEn = "Abyss Caster",
		raceTag = "demon",
		attackType = "magic",
	},
	{
		id = "mon_gate_keeper",
		name = "門の守護魔",
		nameEn = "Gate Keeper",
		raceTag = "demon",
		attackType = "magic",
	},
	-- 天空の玉座
	{
		id = "mon_sky_sentinel",
		name = "天空の哨兵",
		nameEn = "Sky Sentinel",
		raceTag = "construct",
		attackType = "physical",
	},
	{
		id = "mon_storm_spirit",
		name = "嵐の精霊",
		nameEn = "Storm Spirit",
		raceTag = "spirit",
		attackType = "magic",
	},
	{
		id = "mon_fallen_seraph",
		name = "堕ちた天翼",
		nameEn = "Fallen Seraph",
		raceTag = "spirit",
		attackType = "magic",
	},
	{
		id = "mon_sky_tyrant",
		name = "天空の暴君",
		nameEn = "Sky Tyrant",
		raceTag = "dragon",
		attackType = "physical",
	},
}
