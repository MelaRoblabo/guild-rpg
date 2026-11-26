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
	-- 宝箱のレアリティはダンジョンごとの出現率の表で決める（Dungeons.chestRarityWeights、D-085）
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
	-- M7b-6：自動プレイで最大の育成までの暦日数（D-161, D-199）に合わせ、全周回を1.10倍にした（docs/reports/M7b6_balance.md）
	expBase = 100,
	expExponent = 1.5,
	expCycleMult = { 1.63, 1.136, 1.635, 2.701, 4, 6.438, 10.86, 13.02, 17.16 },
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
	-- 面接の Total（HP を除く4項目の合計：Q-006）の特別な演出の線（見せ方だけ。仮。D-283）
	hireTotalGreat = 110,
	hireTotalAmazing = 130,
	hireStatRange = {
		str = { min = 1, max = 40 }, -- D-086：引き直しに一喜一憂が出るよう幅を広げる
		mag = { min = 1, max = 40 },
		agi = { min = 1, max = 40 },
		dex = { min = 1, max = 40 },
		hp = { min = 20, max = 80 },
	},
	hireFreeRerolls = 3,
	specialVisitorChance = 0.005, -- 仮
	-- 今週の訪問者（D-158, D-170。06章 §18）：候補1人ごとに、まずこの確率で今週の訪問者を判定する
	weeklyVisitorChance = 0.03, -- 仮（M7b-6）

	-- 報酬のゴールド（D-190。06章 §22）：プレイ時間・クエスト・ログインボーナス・フレンドボタン
	--   ゴールド = floor(rewardGoldBase[基準のダンジョン] × 報酬ごとの係数)
	--   基準のダンジョン＝踏破した一番深いダンジョン（まだどこも踏破していなければ古い墓地：D-187）
	--   報酬ごとの係数は rewards の goldMult（Quests・PlaytimeRewards・LoginBonus）と friendRewardGoldMult
	--   基準額 rewardGoldBase はダンジョンごとに持つ（Dungeons。tools/sim/DungeonTemplates に書き calibrate が写す：D-198）

	-- フレンドボタン（D-157, D-190。06章 §20）。量は仮（M7b-6）
	--   ゴールド = floor(rewardGoldBase[基準のダンジョン] × friendRewardGoldMult
	--                    × (1 + friendRewardBonusPerFriend × (min(友達の数, friendRewardMaxFriends) − 1)))
	friendRewardIntervalSeconds = 600, -- 仮（M7b-6）。押したら次に押せるまでの秒（押さないとたまらない）
	friendRewardMaxFriends = 3, -- 報酬が増えるのは3人分まで
	friendRewardGoldMult = 7, -- M7b-6（配分 D-160 のフレンド約5%）。友達1人のときの係数（rewardGoldBase に掛ける）
	friendRewardBonusPerFriend = 0.25, -- 仮（M7b-6）。2人目から1人ごとに増える割合
	friendRewardDailyCap = 12, -- 仮（M7b-6）。1日に押せる回数

	-- 紹介（D-157, D-180, D-192。05章 GrantReferral）。報酬は受け取り箱へ（rewards の形はクエストと同じ）
	-- 報酬はステータススロットチケット。招待した側・された側とも、招待された人が referralProgressCondition に届いたときに渡す
	referralWeeklyCap = 3, -- 仮（M7b-6）。招待した側が報酬を受け取れる人数（週）
	referralRewards = {
		invitee = { items = { itm_slot_ticket = 2 } }, -- 量は仮（M7b-6）。招待された側（1回だけ）
		inviter = { items = { itm_slot_ticket = 2 } }, -- 量は仮（M7b-6）。招待した側（相手1人ごと）
	},
	-- 招待された人の進み具合の条件（D-192, D-195。Friend.referralProgressReached）。仮（M7b-6）
	--   kind = "rebirthsTotal"：これまでに転生した回数の累計（stats.rebirths。解雇で戻らない：D-195）が count 回以上
	--   （count = 1 で初転生：D-157 の例）
	referralProgressCondition = { kind = "rebirthsTotal", count = 1 },

	-- ゲーム外の通知（D-196）：「いつも遊ぶ時刻」は直近 notifyLoginHistoryCount 回のログイン時刻（1日の中の位置）の中央値
	notifyLoginHistoryCount = 7,

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
		{ id = "ticket", weight = 0.02 }, -- D-074 で約1/10、D-097 でさらに1/3（M6 テストプレイで余ったため）
		{ id = "sellable", weight = 0.98 },
	},
	sellRarityMult = { 1, 1.5, 2.5, 4, 7, 12 }, -- 仮。レアリティの数だけ並べる（D-085）
	sellGradeCoef = 0.5, -- 仮
	equipRarityMult = { 1.0, 1.3, 1.7, 2.2, 3.0, 4.0 }, -- 仮（Q-020）。レアリティの数だけ並べる（D-085）
	equipGradeCoef = 0.10, -- 仮（Q-020）
	equipTierMult = 1.30, -- アイテムレベルが1上がるごとの倍率（D-069）
	-- 装備の見た目（名前と絵：D-254）。強さには使わない
	equipLookTiersPerBand = 2, -- 武器・防具・盾はダンジョンの段を2つずつまとめて素材の段にする
	equipLookAccessoryTiersPerBand = 4, -- 指輪・護符は4つずつ（3段）
	equipLookNamedMinRarity = 4, -- エピック以上は銘入り
	-- 宝箱の保管は上限なし（D-084。旧 chestStorageMax は廃止）
	chestBatchOpen = 100, -- D-089：「まとめて開く」の個数（残りが少なければその数）
	-- 開封演出が入る割合の基準（D-090）：各ダンジョンで chestEffectMinRarity 以上が出る確率をこの範囲に収める
	chestEffectRate = { min = 0.10, max = 0.15 },

	-- 留守番（D-161, D-172。06章 §13）
	offlineTimeMult = 10, -- 留守番の探索1回の時間の倍率（効率10%）
	offlineMaxSeconds = 21600, -- 1回の留守で6時間まで。6時間までに最後の探索を帰還させる（拡張しない）

	pinchHpRatio = 0.3, -- ピンチの印：探索の今の時点で、メンバーの HP の合計／最大 HP の合計がこれより低い（仮。D-229）
	-- 能力の演出の線（見せ方だけ。結果は変えない）：上限（雇用は範囲、転生は加算分の上限）に対する割合
	statGoodRatio = 0.75, -- 良い値の演出（雇用 S-21c：D-220、転生 S-43b：D-224）
	rebirthGreatRatio = 0.9, -- 転生の加算分の特別な演出（07章・D-224）

	-- 日替わりの特性（D-156。06章 §16）
	dailyTraitBands = { -- 難度（ダンジョンの tier）の帯。帯ごとに毎日1つのダンジョンに特性が当たる
		{ min = 1, max = 4 },
		{ min = 5, max = 8 },
		{ min = 9, max = 12 },
	},
	calendarSeed = 20260101, -- 日替わり・今週の訪問者・マップイベントの共通の乱数の元（全員共通。値は任意の固定値）

	-- 特別な宝箱（D-166, D-171。06章 §19）
	rareDungeonEffectRate = { min = 0.20, max = 0.30 }, -- レアダンジョンの山の演出率の基準（D-171）

	-- マップイベント（D-152, D-179。06章 §12）。種類と出る場所は src/data/MapEvents.luau
	mapEventIntervalSeconds = 300, -- 5分ごとに1つ
	mapEventNoticeSeconds = 60, -- 1分前に予告
	mapEventWindowSeconds = 180, -- 出発・購入できるのは出てから3分間
	mapEventKindWeights = { -- 種類の割合（M7b-6：配分 D-160 のマップイベントとオンラインの価値 D-161 に合わせた）
		{ id = "mev_rare_dungeon", weight = 3 },
		{ id = "mev_raid", weight = 1 },
		{ id = "mev_merchant", weight = 6 },
	},
	-- レアダンジョン（D-152, D-171, D-173）
	rareDungeonChestMult = 1.5, -- 宝箱の数の倍率。1.5〜2 の範囲で仮（M7b-6）。端数は確率で切り上げ
	-- レイドボス（D-152, D-179。06章 §12）。HP とダメージの式は仮（M7b-6 で決める）
	--   HP     = floor(踏破済みの一番深いダンジョンの base.hp × raidHpMult × 一様乱数[raidHpSpread.min, max))（プレイヤーごと）
	--   ダメージ = floor(パーティ全員の攻撃力（出発時の実効値）の合計 × raidDamagePerAtk)
	raidHpMult = 3, -- M7b-6：1パーティでときどき・2パーティでたいてい・3パーティでほぼ倒せる（D-179）
	raidHpSpread = { min = 0.6, max = 1.4 }, -- M7b-6（同上）
	raidDamagePerAtk = 1, -- M7b-6（HP の側で合わせたので 1 のまま）
	raidTravelSeconds = 30, -- レイドへの片道秒（到着でダメージを入れ、同じ秒数で帰る）。M7b-6：オンラインの価値（D-161）のため 60→30
	-- 旅の商人（D-152。06章 §12）
	-- 品のレアリティは、そのダンジョンの宝箱の表からコモンを除いて引く（コモンしかない表ならコモン：D-189）
	merchantItemCount = { min = 3, max = 5 }, -- 品の数（プレイヤーごと）
	-- 品を引くダンジョン（D-202）：踏破済みのうち深い方からこの数（2 ＝ 一番深いダンジョンとその1つ浅いダンジョン）
	merchantDungeonCount = 2,
	-- 品のレアリティの重み（D-204）：宝箱の表の重み × merchantRarityBias ^ (rank − 2)（コモンは除く：D-189）。
	--   「誰かの今の装備より良い品」が約15%になるように自動プレイで合わせる（docs/reports/M7b6_balance.md）
	merchantRarityBias = 12,
	merchantPriceMult = 10, -- 価格 = 売却価格 × この倍率 × グレード・修飾語の倍率（約10：D-152）。M7b-6 で見直し、据え置き（D-198）
	merchantGradeCoef = 0.5, -- 仮（M7b-6）
	merchantModifierCoef = 0.5, -- 仮（M7b-6）
	-- 商人のところにとどまれる長さの上限（D-274）。Leave を押すかログアウトで帰り始める。押さないままでも、この秒数で帰り始める
	merchantStayMaxSeconds = 1800,

	-- クエスト（D-153。06章 §15）。お題の候補と報酬は src/data/Quests.luau
	questDailyCount = 3,
	questWeeklyCount = 4, -- 3〜5 のうち仮（M7b-6）
	-- 全部達成のボーナス（rewards の形は Quests と同じ）。量は M7b-6 で配分（D-160）に合わせた。ポーションは量を優先（D-201）
	questDailyBonus = {
		goldMult = 60,
		chests = { { pileKey = "special:quest", count = 150 } },
		items = { itm_slot_ticket = 12 },
	},
	questWeeklyBonus = {
		goldMult = 220,
		chests = { { pileKey = "special:quest", count = 700 } },
		items = { itm_slot_ticket = 46, itm_potion_appearance_change = 1, itm_potion_appearance_keep = 1 },
	},

	-- プレイ時間（D-154。06章 §20）。段階と報酬は src/data/PlaytimeRewards.luau
	playtimeDailyCapSeconds = 7200, -- 1日2時間まで

	-- ギルド（Q-017）
	guildExpPerFloor = 1,
	guildExpClearBonus = 5,
	guildExpFirstClear = 50,
	-- ギルドレベルの必要経験値と報酬は src/data/GuildLevels.luau（tools/sim/progression が生成：D-074）
	-- 設定の音量の段（0〜volumeSteps。S-61、D-237 ③）
	volumeSteps = 10,
	-- 画面の演出の秒数（D-238 ③。見るための値で、ゲームの結果は変えない）
	cutInSeconds = 3, -- カットインが自動で次へ進むまで（D-132）
	returnToastSeconds = 5, -- 帰還のトーストを出しておく時間（11章 §5）
	returnToastGroupSeconds = 0.6, -- この間に帰ったパーティは1つのトーストにまとめる（D-128）
	mapEventEndingSeconds = 30, -- マップイベントの「残りわずか」（輪の点滅・警告の色：D-213 ⑫）
}
