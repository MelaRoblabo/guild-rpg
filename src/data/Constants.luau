--!strict
-- ゲーム定数（docs/system/04_master_data.md §3）
-- 確率・重みの表は「配列」で持つ（辞書は走査順が不定で、乱数の結果が変わるため）。
-- 「仮」の値は M6 で調整する。

return {
	-- 戦闘（D-005, D-007, D-009, D-010, D-003）
	hitWeights = { 0.45, 0.25, 0.20, 0.10 },
	critCoef = 200,
	critCap = 0.30,
	critMult = 1.5,
	maxTurns = 30,
	monsterScalePerBattle = 0.20,

	-- イベント（D-014, D-015, D-017, D-018）
	eventWeights = {
		{ id = "chest", weight = 0.40 },
		{ id = "item", weight = 0.15 },
		{ id = "trap", weight = 0.20 },
		{ id = "fountain", weight = 0.10 },
		{ id = "none", weight = 0.15 },
	},
	chestRankOffsets = {
		{ id = "+0", offset = 0, weight = 0.60 },
		{ id = "+1", offset = 1, weight = 0.25 },
		{ id = "+2", offset = 2, weight = 0.10 },
		{ id = "+3", offset = 3, weight = 0.05 },
	},
	fountainHealRate = 0.25,
	trapK = 40, -- D-067
	trapDamageRate = 0.20, -- D-067。ダンジョンごとに上書き可（Dungeons.trapDamageRate）

	-- 支援系（D-034, Q-004）
	healThreshold = 0.70,
	healCoef = 0.30, -- 仮

	-- 幸運（D-019, Q-004）
	luckyChancePerHolder = 0.30, -- D-070
	luckyChanceCap = 0.60, -- D-070

	-- 移動・再生（D-021, D-026, Q-004）
	travelSecondsPerDistance = 10, -- 仮
	-- 片道秒 = 距離 × travelSecondsPerDistance × clamp(ダンジョンの基準俊敏 ÷ 平均俊敏, Min, Max)（D-069）
	travelSpeedMin = 0.8, -- D-075：強くなって速くなる幅を抑える（帰還間隔30秒の目標）
	travelSpeedMax = 1.4,
	replaySecondsPerTurn = 1,
	replaySecondsPerEvent = 2,

	-- 個体補正（D-033）
	personalBonusCap = 0.50, -- D-070
	-- 経験値補正（ギフト＋装備）の合計の上限（D-082）。personalBonusCap とは別枠
	expBonusCap = 1.00, -- 仮

	-- 成長（D-043, 07章）
	growthVariance = 1,
	-- 必要経験値 = floor(expBase × Lv^expExponent × expCycleMult[転生回数+1])（D-071）
	-- expCycleMult は tools/sim/progression.luau が「各周回の所要時間」に合わせて書き換える
	expBase = 100,
	expExponent = 1.5,
	expCycleMult = { 1.179, 0.8121, 1.333, 2.228, 3.312, 5.418, 6.867, 11.84, 15.6 },
	levelCapInitial = 20, -- D-071
	levelCapPerRebirth = 10,
	levelCapMax = 100,
	rebirthExpBonusPerCount = 0.5, -- 仮

	-- 転生（D-024, Q-009）
	rebirthGiftAddAt = { 2, 4, 6 },
	giftMax = 4,
	-- 転生スロットの加算分（D-072）
	--   上限 = floor(転生前の値 × rebirthBonusMaxRate)
	--   加算分 = floor(上限 × u ^ p)、u は [0,1) の一様乱数、p = SkewBase + SkewPerRebirth × (転生回数 − 1)
	--   p が大きいほど大きな値が出にくい（後半の転生ほど何度も回す）
	rebirthBonusMaxRate = 0.30,
	-- D-074：上限比70%以上（4項目平均）に届く期待回数が 1回目 約100回 → 8回目 約300回
	rebirthBonusSkewBase = 2.073,
	rebirthBonusSkewPerRebirth = 0.116,
	rebirthFreeRerolls = 3,
	-- 転生費用（D-080）：[i] = 転生回数 i−1 → i の転生にかかるゴールド。RebirthStart で払う（仮）
	rebirthCost = { 2000, 5000, 20000, 80000, 300000, 1000000, 3000000, 8000000 },

	-- トレーニング（D-076, D-077）
	--   1回の費用 = floor(trainGoldCoef × Lv ^ trainGoldExponent)（Lv が上がるほど跳ね上がる）
	--   1回の経験値 = trainingFacility[トレーニング場のレベル].expPerSession（転生・ギフト・装備の倍率は掛けない）
	--   トレーニングで上げられるのは trainingFacility[...].levelCap まで（本人の上限レベルも超えない）
	trainGoldCoef = 10, -- 仮
	trainGoldExponent = 2, -- 仮
	trainingFacility = {
		{ levelCap = 10, expPerSession = 430 },
		{ levelCap = 20, expPerSession = 820 },
		{ levelCap = 30, expPerSession = 1200 },
		{ levelCap = 40, expPerSession = 1630 },
		{ levelCap = 50, expPerSession = 2060 },
	},

	-- 雇用（Q-006）。ステータスの範囲はギルドの成長に関係なく一定（D-081）
	hireCost = 300,
	hireStatRange = {
		str = { min = 5, max = 20 },
		mag = { min = 5, max = 20 },
		agi = { min = 5, max = 20 },
		dex = { min = 5, max = 20 },
		hp = { min = 30, max = 60 },
	},
	hireFreeRerolls = 3,
	specialVisitorChance = 0.005, -- 仮

	-- 見た目（D-050）
	appearanceGenderWeights = {
		{ id = "m", weight = 0.5 },
		{ id = "f", weight = 0.5 },
	},
	appearanceLooksWeights = {
		{ id = "bea", weight = 0.15 },
		{ id = "nor", weight = 0.50 },
		{ id = "ugl", weight = 0.20 },
		{ id = "dem", weight = 0.15 },
	},

	-- 宝箱の中身（06章, Q-011, Q-020）
	gradeWeights = {
		{ id = "+0", grade = 0, weight = 0.74 },
		{ id = "+1", grade = 1, weight = 0.20 },
		{ id = "+2", grade = 2, weight = 0.05 },
		{ id = "+3", grade = 3, weight = 0.01 },
	},
	modifierChance = 0.40, -- 仮
	potionChanceRarePlus = 0.05, -- 仮
	potionKindWeights = {
		{ id = "job_change", weight = 0.40 },
		{ id = "appearance_change", weight = 0.30 },
		{ id = "appearance_keep", weight = 0.30 },
	},
	itemEventWeights = {
		{ id = "ticket", weight = 0.06 }, -- D-074：遊んで出る量を約1/10に。主な入手はギルドレベル報酬
		{ id = "sellable", weight = 0.94 },
	},
	sellRarityMult = { 1, 1.5, 2.5, 4, 7 }, -- 仮
	sellGradeCoef = 0.5, -- 仮
	equipRarityMult = { 1.0, 1.3, 1.7, 2.2, 3.0 }, -- 仮（Q-020）
	equipGradeCoef = 0.10, -- 仮（Q-020）
	equipTierMult = 1.30, -- アイテムレベルが1上がるごとの倍率（D-069）
	chestStorageMax = 500, -- D-071

	-- ギルド（Q-017）
	guildExpPerFloor = 1,
	guildExpClearBonus = 5,
	guildExpFirstClear = 50,
	-- ギルドレベルの必要経験値と報酬は src/data/GuildLevels.luau（tools/sim/progression が生成：D-074）
}
