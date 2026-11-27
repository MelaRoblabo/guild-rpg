--!strict
-- 体験スコアの表（MX。D-301、docs/system/04_master_data.md §15、docs/reports/MX_engagement.md §4）
-- ゲームの動きには使わない。成績表のツール（tools/balance）がこの表だけを読んで点数を出す。
-- 各指標は good（良い線）で100点、bad（悪い線）で0点、その間は直線（good < bad でもよい：小さいほど良い指標）。
-- 分類の点数は指標の平均、型ごとの総合は分類の平均（weight で重みを付ける。今は全部1）。
-- metric は tools/balance/Experience.luau が出す指標の名前（Metrics.EXPERIENCE）。

return {
	profiles = { "light", "core", "heavy" },
	categories = {
		{
			id = "hook",
			name = "A つかみ",
			weight = 1,
			items = {
				{ metric = "firstChestSec", name = "最初の開封までの秒", good = 60, bad = 180 },
				{
					metric = "firstUpgradeSec",
					name = "最初に装備が強くなるまでの秒",
					good = 120,
					bad = 600,
				},
				{ metric = "firstSessionBig", name = "最初のプレイの節目の数", good = 5, bad = 1 },
			},
		},
		{
			id = "rhythm",
			name = "B ごほうびのリズム",
			weight = 1,
			items = {
				{
					metric = "rewardGapP90Sec",
					name = "プレイ中のごほうびの間隔（90%点、秒）",
					good = 60,
					bad = 300,
				},
				{
					metric = "longestGapMedianSec",
					name = "1回のプレイで一番長く何もなかった秒（中央値）",
					good = 180,
					bad = 900,
				},
			},
		},
		{
			id = "payoff",
			name = "C 毎回の手応え",
			weight = 1,
			items = {
				{ metric = "sessionsWithBigShare", name = "節目のあるプレイの割合", good = 0.6, bad = 0.2 },
				{
					metric = "bigPerSessionLate",
					name = "後半の1回のプレイあたりの節目",
					good = 0.5,
					bad = 0.1,
				},
			},
		},
		{
			id = "novelty",
			name = "D 新しさの続き方",
			weight = 1,
			items = {
				{
					metric = "noveltyDroughtShare",
					name = "新しさのない最長の期間 ÷ 全日数",
					good = 0.10,
					bad = 0.40,
				},
				{ metric = "noveltyLateHalf", name = "後半の新しさの数", good = 8, bad = 0 },
			},
		},
		{
			id = "flow",
			name = "E 停滞のなさ",
			weight = 1,
			items = {
				{ metric = "flatDaysLongest", name = "節目のない日の連続の最長", good = 2, bad = 10 },
				{ metric = "flatDaysShare", name = "節目のない日の割合", good = 0.15, bad = 0.50 },
			},
		},
		{
			id = "return",
			name = "F 戻る理由",
			weight = 1,
			items = {
				{
					metric = "loginPayoffShare",
					name = "留守の宝箱が届いているログインの割合",
					good = 0.9,
					bad = 0.5,
				},
			},
		},
		{
			id = "habit",
			name = "G 毎日の習慣",
			weight = 1,
			items = {
				{ metric = "dailyQuestsPerDay", name = "1日に達成できるデイリーの数", good = 3, bad = 1 },
			},
		},
	},
}
