--!strict
-- 基本アイテム（ゲーム仕様書06章 §4、Q-020）
-- slot: weapon / armor / sub
-- kind: 職業の equipKinds と照合する
-- 性能値は rarity・grade の倍率を掛ける前の基本値（06章 §2）
--   atk  攻撃力補正 / pdef 物理防御 / mdef 魔法防御 / stats 基礎ステータス補正
--   expPct 獲得経験値の補正（D-082）。レアリティ・グレードの倍率は掛かるが、アイテムレベルでは伸びない
-- minRarity: 宝箱から出る最低レアリティ（M2 で中身の抽選に使う）
-- 試作用の最小セット（仮）。コンテンツは M2 以降で追加する

return {
	-- 武器
	{
		id = "eq_wpn_sword",
		name = "ロングソード",
		slot = "weapon",
		kind = "sword",
		minRarity = 1,
		sellPrice = 20,
		atk = 6,
	},
	{
		id = "eq_wpn_dagger",
		name = "ダガー",
		slot = "weapon",
		kind = "dagger",
		minRarity = 1,
		sellPrice = 16,
		atk = 4,
	},
	{
		id = "eq_wpn_staff",
		name = "オークの杖",
		slot = "weapon",
		kind = "staff",
		minRarity = 1,
		sellPrice = 20,
		atk = 6,
	},
	{ id = "eq_wpn_mace", name = "メイス", slot = "weapon", kind = "mace", minRarity = 1, sellPrice = 18, atk = 5 },
	-- 防具
	{
		id = "eq_arm_chainmail",
		name = "チェインメイル",
		slot = "armor",
		kind = "heavy_armor",
		minRarity = 1,
		sellPrice = 22,
		pdef = 6,
		mdef = 1,
	},
	{
		id = "eq_arm_leather",
		name = "レザーアーマー",
		slot = "armor",
		kind = "light_armor",
		minRarity = 1,
		sellPrice = 16,
		pdef = 3,
		mdef = 2,
	},
	{
		id = "eq_arm_robe",
		name = "ローブ",
		slot = "armor",
		kind = "robe",
		minRarity = 1,
		sellPrice = 16,
		pdef = 1,
		mdef = 5,
	},
	{
		id = "eq_arm_vestment",
		name = "法衣",
		slot = "armor",
		kind = "vestment",
		minRarity = 1,
		sellPrice = 18,
		pdef = 2,
		mdef = 4,
	},
	-- 補助
	{
		id = "eq_sub_buckler",
		name = "バックラー",
		slot = "sub",
		kind = "shield",
		minRarity = 1,
		sellPrice = 14,
		pdef = 3,
	},
	{
		id = "eq_sub_ring_power",
		name = "力の指輪",
		slot = "sub",
		kind = "accessory",
		minRarity = 1,
		sellPrice = 15,
		stats = { str = 3 },
	},
	{
		id = "eq_sub_ring_wisdom",
		name = "知恵の指輪",
		slot = "sub",
		kind = "accessory",
		minRarity = 1,
		sellPrice = 15,
		stats = { mag = 3 },
	},
	{
		id = "eq_sub_ring_wind",
		name = "風の指輪",
		slot = "sub",
		kind = "accessory",
		minRarity = 1,
		sellPrice = 15,
		stats = { agi = 3 },
	},
	{
		id = "eq_sub_amulet_learning",
		name = "修練の護符",
		slot = "sub",
		kind = "accessory",
		minRarity = 1,
		sellPrice = 15,
		expPct = 0.20, -- D-082（仮）
	},
}
