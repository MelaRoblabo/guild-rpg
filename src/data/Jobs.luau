--!strict
-- 職業（ゲーム仕様書03章、D-036, D-037, D-043, D-044）
-- line: warrior=戦士系 / scout=探索系 / mage=魔法系 / support=支援系
-- attackType: physical=腕力で攻撃し物理防御を引く / magic=魔力で攻撃し魔法防御を引く
-- growth: レベルアップ1回あたりの基準値（±growthVariance の振れ幅を乗せる）
-- レア職の成長値は仮（D-044）

return {
	{
		id = "job_warrior",
		name = "戦士",
		nameEn = "Warrior",
		line = "warrior",
		attackType = "physical",
		isRare = false,
		hireWeight = 1, -- 雇用候補に出る重み
		heals = false,
		outfitClass = "phy",
		growth = { str = 4, mag = 0, agi = 1, dex = 0, hp = 5 },
		equipKinds = { "sword", "heavy_armor", "shield", "accessory" },
	},
	{
		id = "job_thief",
		name = "盗賊",
		nameEn = "Thief",
		line = "scout",
		attackType = "physical",
		isRare = false,
		hireWeight = 1, -- 雇用候補に出る重み
		heals = false,
		outfitClass = "phy",
		growth = { str = 2, mag = 0, agi = 3, dex = 4, hp = 3 },
		equipKinds = { "dagger", "light_armor", "accessory" },
	},
	{
		id = "job_mage",
		name = "魔法使い",
		nameEn = "Mage",
		line = "mage",
		attackType = "magic",
		isRare = false,
		hireWeight = 1, -- 雇用候補に出る重み
		heals = false,
		outfitClass = "mag",
		growth = { str = 0, mag = 5, agi = 2, dex = 1, hp = 2 },
		equipKinds = { "staff", "robe", "accessory" },
	},
	{
		id = "job_priest",
		name = "僧侶",
		nameEn = "Priest",
		line = "support",
		attackType = "magic",
		isRare = false,
		hireWeight = 1, -- 雇用候補に出る重み
		heals = true,
		outfitClass = "mag",
		growth = { str = 1, mag = 4, agi = 1, dex = 1, hp = 3 },
		equipKinds = { "mace", "vestment", "accessory" },
	},
	{
		id = "job_knight",
		name = "ナイト",
		nameEn = "Knight",
		line = "warrior",
		attackType = "physical",
		isRare = true,
		hireWeight = 0, -- レア職は雇用では出ない（転職ポーションでなる）
		heals = false,
		outfitClass = "phy",
		growth = { str = 5, mag = 0, agi = 1, dex = 0, hp = 6 },
		equipKinds = { "sword", "heavy_armor", "shield", "accessory" },
	},
	{
		id = "job_ninja",
		name = "忍者",
		nameEn = "Ninja",
		line = "scout",
		attackType = "physical",
		isRare = true,
		hireWeight = 0, -- レア職は雇用では出ない（転職ポーションでなる）
		heals = false,
		outfitClass = "phy",
		growth = { str = 2, mag = 0, agi = 4, dex = 5, hp = 3 },
		equipKinds = { "dagger", "light_armor", "accessory" },
	},
	{
		id = "job_sage",
		name = "賢者",
		nameEn = "Sage",
		line = "mage",
		attackType = "magic",
		isRare = true,
		hireWeight = 0, -- レア職は雇用では出ない（転職ポーションでなる）
		heals = false,
		outfitClass = "mag",
		growth = { str = 0, mag = 6, agi = 2, dex = 2, hp = 2 },
		equipKinds = { "staff", "robe", "accessory" },
	},
	{
		id = "job_bishop",
		name = "司祭",
		nameEn = "Bishop",
		line = "support",
		attackType = "magic",
		isRare = true,
		hireWeight = 0, -- レア職は雇用では出ない（転職ポーションでなる）
		heals = true,
		outfitClass = "mag",
		growth = { str = 1, mag = 5, agi = 1, dex = 1, hp = 4 },
		equipKinds = { "mace", "vestment", "accessory" },
	},
}
