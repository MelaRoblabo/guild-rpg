--!strict
-- 成績表のツールの設定（MB）。ゲームの数値でも目標でもないので src/data に置かない。
-- 目標の値は src/data/BalanceTargets.luau。

return {
	-- 自動プレイを回す最大の日数：暦日数の目標 × この倍率（届かなければ「未到達」）
	daysCapFactor = 1.5,
	-- 暦日数の目標がない型の最大の日数
	daysCapDefault = 45,
	-- 同時に起動する自動プレイの数
	parallel = 8,
	-- 探索シミュレーターの1ダンジョンあたりの回数
	simRuns = 1000,
	simSeed = 777,
	-- 基準との差を警告する幅（D-295：ずれの幅はツールの設定で決める）。割合（0.15 = 15%）
	baselineWarnRel = 0.15,
	-- 日数の指標は小さい値で割合が大きく振れるので、差がこの日数未満なら警告しない
	baselineMinDays = 0.5,
	-- 配分など % の指標は、差がこのポイント未満なら警告しない
	baselineMinPt = 3,
	-- 基準のファイル
	baselinePath = "tools/balance/Baseline.json",
}
