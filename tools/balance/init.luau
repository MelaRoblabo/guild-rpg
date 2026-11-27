--!strict
-- バランスの成績表（MB。docs/system/09_cli_sim_autoplay.md §5）
-- 目標の表 src/data/BalanceTargets.luau だけを読み、自動プレイ（型 × seed）と探索シミュレーターを回して、
-- 目標ごとの合否と基準（D-295）との差を出す。目標の値はこのツールに書かない。
--
--   lune run tools/balance                              全部（型 × seed は目標の表のとおり）
--   lune run tools/balance -- --only sim                探索シミュレーターだけ（数十秒）
--   lune run tools/balance -- --only autoplay --profiles core --seeds 2
--   lune run tools/balance -- --targets bal_days_to_max_growth,bal_share_tools
--   lune run tools/balance -- --set Constants.expCycleMult.5=4.2 --set Dungeons.dng_ruins.unlockGold=500
--   lune run tools/balance -- --save-baseline           この結果を基準として保存（上書きがあるときは保存しない）
--   lune run tools/balance -- --label "後半の新しさ案1"  体験スコア（D-301）を名前つきで履歴に残す（out/balance/history.html に折れ線）
--   lune run tools/balance -- --no-experience           体験スコアを回さない
--   lune run tools/balance -- --quick                   動くかだけ確かめる（core・seed 1・3日・sim 50回。判定はしない）
-- 結果は out/balance/<日時>.md と .json。

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local Data = require("../src/data")
local MasterData = require("../src/core/MasterData")
local Judge = require("@self/Judge")
local Overrides = require("@self/Overrides")
local Settings = require("@self/Settings")
local History = require("@self/History")
local Score = require("@self/Score")
local SimMetrics = require("@self/SimMetrics")

-- 引数 ------------------------------------------------------------------------

local opts: any = { sets = {}, setTexts = {} }
do
	local a = process.args
	local i = 1
	while i <= #a do
		local k, v = a[i], a[i + 1]
		if k == "--" then
			i += 1
			continue
		elseif k == "--only" then
			opts.only = v
		elseif k == "--profiles" then
			opts.profiles = string.split(v, ",")
		elseif k == "--seeds" then
			opts.seeds = tonumber(v)
		elseif k == "--targets" then
			opts.targets = string.split(v, ",")
		elseif k == "--set" then
			table.insert(opts.sets, Overrides.parse(v))
			table.insert(opts.setTexts, v)
		elseif k == "--parallel" then
			opts.parallel = tonumber(v)
		elseif k == "--sim-runs" then
			opts.simRuns = tonumber(v)
		elseif k == "--days" then
			opts.days = tonumber(v)
		elseif k == "--save-baseline" then
			opts.saveBaseline = true
			i += 1
			continue
		elseif k == "--quick" then
			opts.quick = true
			i += 1
			continue
		elseif k == "--quiet" then
			opts.quiet = true
			i += 1
			continue
		elseif k == "--label" then
			opts.label = v
		elseif k == "--no-experience" then
			opts.noExperience = true
			i += 1
			continue
		else
			error(`未知の引数: {k}`)
		end
		i += 2
	end
end
if opts.quick then
	opts.profiles = opts.profiles or { "core" }
	opts.seeds = opts.seeds or 1
	opts.days = opts.days or 3
	opts.simRuns = opts.simRuns or 50
end

local started = os.clock()
Overrides.apply(Data, opts.sets)
local master = MasterData.load(Data)
local BT = master.balanceTargets
local seeds = opts.seeds or BT.seeds
local simRuns = opts.simRuns or Settings.simRuns

-- 回す目標を選ぶ ------------------------------------------------------------

local function wanted(t: any): boolean
	if opts.only and t.source ~= opts.only then
		return false
	end
	if opts.targets and not table.find(opts.targets, t.id) then
		return false
	end
	return true
end

local targets = {}
for _, t in BT.targets do
	if wanted(t) then
		table.insert(targets, t)
	end
end
assert(#targets > 0, "回す目標がない（--only・--targets を確かめる）")

-- 型 × 友達の数ごとに、必要な指標と日数を集める
local groups: { [string]: any } = {}
local groupOrder = {}
local simMetricNames = {}
for _, t in targets do
	if t.source == "autoplay" then
		for _, prof in t.profiles do
			if opts.profiles and not table.find(opts.profiles, prof) then
				continue
			end
			local friends = t.friends or 0
			local key = `{prof}/f{friends}`
			local g = groups[key]
			if g == nil then
				g = { key = key, profile = prof, friends = friends, metrics = {}, days = 0 }
				groups[key] = g
				table.insert(groupOrder, key)
			end
			if not table.find(g.metrics, t.metric) then
				table.insert(g.metrics, t.metric)
			end
		end
	elseif not table.find(simMetricNames, t.metric) then
		table.insert(simMetricNames, t.metric)
	end
end
-- 体験スコア（MX。D-301）：スコアの表の型の自動プレイ（友達なし）に体験の指標を足す。
-- その型を回す目標がなければ、体験スコアのためだけに回す（--only sim のときは回さない）
local ES = master.experienceScores
local expMetrics = Score.metrics(ES)
if opts.only ~= "sim" and not opts.noExperience then
	for _, prof in ES.profiles do
		if opts.profiles and not table.find(opts.profiles, prof) then
			continue
		end
		local key = `{prof}/f0`
		local g = groups[key]
		if g == nil then
			g = { key = key, profile = prof, friends = 0, metrics = {}, days = 0 }
			groups[key] = g
			table.insert(groupOrder, key)
		end
		for _, m in expMetrics do
			if not table.find(g.metrics, m) then
				table.insert(g.metrics, m)
			end
		end
	end
end
-- 日数：暦日数の目標 × 倍率（届かなければ未到達）
local daysTarget: { [string]: number } = {}
for _, t in BT.targets do
	if t.metric == "daysToMaxGrowth" and t.byProfile then
		for prof, v in t.byProfile do
			daysTarget[prof] = v
		end
	end
end
for _, g in groups do
	g.days = opts.days
		or (
			if daysTarget[g.profile]
				then math.ceil(daysTarget[g.profile] * Settings.daysCapFactor)
				else Settings.daysCapDefault
		)
end

-- 自動プレイを別のプロセスで並べて回す ----------------------------------------

local stamp = os.date("%Y%m%d-%H%M%S")
local workDir = `out/balance/{stamp}`
fs.writeDir(workDir)

local jobs = {}
for _, key in groupOrder do
	local g = groups[key]
	for seed = 1, seeds do
		table.insert(jobs, { group = g, seed = seed, out = `{workDir}/{g.profile}-f{g.friends}-seed{seed}.json` })
	end
end

local results: { [string]: { any } } = {}
local running, nextJob, done, failures = 0, 1, 0, {}
local parallel = opts.parallel or Settings.parallel

local function runJob(job: any)
	local args = {
		"run",
		"tools/balance/worker",
		"--",
		"--profile",
		job.group.profile,
		"--seed",
		tostring(job.seed),
		"--days",
		tostring(job.group.days),
		"--friends",
		tostring(job.group.friends),
		"--metrics",
		table.concat(job.group.metrics, ","),
		"--out",
		job.out,
	}
	for _, s in opts.setTexts do
		table.insert(args, "--set")
		table.insert(args, s)
	end
	local r = process.exec("lune", args)
	if r.ok then
		local data = serde.decode("json", fs.readFile(job.out))
		results[job.group.key] = results[job.group.key] or {}
		results[job.group.key][job.seed] = data.metrics -- seed の順に置く（出なかった seed は空き）
	else
		table.insert(failures, `{job.group.key} seed{job.seed}: {r.stderr}`)
	end
	done += 1
	running -= 1
	if not opts.quiet then
		print(`  自動プレイ {done}/{#jobs}（{job.group.key} seed{job.seed}{if r.ok then "" else " 失敗"}）`)
	end
end

if #jobs > 0 then
	print(`自動プレイ {#jobs}回を最大{parallel}本ずつ回す`)
end
local function pump()
	while running < parallel and nextJob <= #jobs do
		local job = jobs[nextJob]
		nextJob += 1
		running += 1
		task.spawn(runJob, job)
	end
end
pump()

-- 待っている間に探索シミュレーター
local simValues: { [string]: any } = {}
if #simMetricNames > 0 then
	print(`探索シミュレーター（1ダンジョン {simRuns}回）`)
	simValues = SimMetrics.compute(master, simMetricNames, simRuns, Settings.simSeed)
end

while done < #jobs do
	pump()
	task.wait(0.5)
end
if #failures > 0 then
	print("自動プレイの失敗：\n" .. table.concat(failures, "\n"))
end

-- 判定 ------------------------------------------------------------------------

local baseline: any = nil
if fs.isFile(Settings.baselinePath) then
	baseline = serde.decode("json", fs.readFile(Settings.baselinePath))
end

local judged = {}
local aggregated: { [string]: { [string]: any } } = {}
for _, t in targets do
	aggregated[t.id] = {}
	if t.source == "autoplay" then
		for _, prof in t.profiles do
			local key = `{prof}/f{t.friends or 0}`
			local g = groups[key]
			if g == nil then
				continue
			end
			local values = {}
			local bySeed = results[key] or {}
			for seed = 1, seeds do
				local m = bySeed[seed]
				table.insert(values, if m then m[t.metric] or false else false)
			end
			local agg = Judge.aggregate(values, seeds)
			aggregated[t.id][key] = agg
			local base = baseline and baseline.values[t.id] and baseline.values[t.id][key]
			table.insert(judged, Judge.judge(t, prof, agg, base, g.days))
		end
	else
		local agg = Judge.aggregate({ simValues[t.metric] }, 1)
		aggregated[t.id].sim = agg
		local base = baseline and baseline.values[t.id] and baseline.values[t.id].sim
		table.insert(judged, Judge.judge(t, nil, agg, base, nil))
	end
end

-- 書き出し ----------------------------------------------------------------------

local function git(args: { string }): string
	local r = process.exec("git", args)
	return if r.ok then (string.gsub(r.stdout, "%s+$", "")) else "?"
end
local commit = git({ "rev-parse", "--short", "HEAD" })
local dirty = git({ "status", "--porcelain", "--", "src", "tools" }) ~= ""

local profileNames = {}
for _, key in groupOrder do
	table.insert(profileNames, key)
end
local md = Judge.render(judged, {
	date = os.date("%Y-%m-%d %H:%M"),
	commit = commit,
	dirty = dirty,
	baselineText = if baseline
		then `{Settings.baselinePath}（{baseline.savedAt}、コミット {baseline.commit}）`
		else "なし（--save-baseline で保存）",
	profiles = if #profileNames > 0 then table.concat(profileNames, "・") else "なし",
	seeds = seeds,
	runCount = #jobs,
	simRuns = if #simMetricNames > 0 then simRuns else 0,
	sets = opts.setTexts,
	elapsed = os.clock() - started,
})
-- 体験スコア（D-301）：型ごとに seed の平均 → 点数。履歴の最後と比べる
local scores: { [string]: any } = {}
local expMeans: { [string]: any } = {}
for _, prof in ES.profiles do
	local bySeed = results[`{prof}/f0`]
	if bySeed and next(bySeed) ~= nil then
		local means = {}
		for _, m in expMetrics do
			local values = {}
			for seed = 1, seeds do
				local r = bySeed[seed]
				table.insert(values, if r then r[m] or false else false)
			end
			means[m] = Judge.aggregate(values, seeds).mean
		end
		expMeans[prof] = means
		-- 点数は seed の平均の指標から出す。揺れの幅は seed ごとの点数のばらつき（標準誤差）
		local perSeed = {}
		for seed = 1, seeds do
			if bySeed[seed] then
				table.insert(perSeed, Score.profile(ES, bySeed[seed]))
			end
		end
		scores[prof] = Score.profile(ES, means)
		scores[prof].se = Score.noise(ES, perSeed)
	end
end
local history = History.load()
md ..= Score.render(ES, scores, expMeans, history[#history])

local balanceCounts = { pass = 0, fail = 0, warn = 0 }
for _, r in judged do
	if balanceCounts[r.status] then
		balanceCounts[r.status] += 1
	end
end
local base = `out/balance/{stamp}`
fs.writeFile(base .. ".md", md)
fs.writeFile(
	base .. ".json",
	serde.encode(
		"json",
		{ commit = commit, sets = opts.setTexts, seeds = seeds, values = aggregated, scores = scores },
		true
	)
)
-- 履歴（--label）：名前つきで点数とバランスの成績を残し、折れ線の HTML を作り直す
if opts.label then
	if opts.quick then
		print("履歴には残さない（--quick）")
	elseif next(scores) == nil then
		print("履歴には残さない（体験スコアを回していない）")
	else
		History.append({
			label = opts.label,
			date = os.date("%Y-%m-%d %H:%M"),
			commit = commit .. (if dirty then "+" else ""),
			sets = opts.setTexts,
			seeds = seeds,
			scores = scores,
			balance = balanceCounts,
		})
		history = History.load()
		print(`履歴に残した: {History.PATH}（{opts.label}）`)
	end
end
if #history > 0 then
	fs.writeFile("out/balance/history.html", History.html(ES, history))
	print("履歴の折れ線: out/balance/history.html")
end
if not opts.quiet then
	print(md)
end
print(`保存: {base}.md / {base}.json`)

if opts.saveBaseline then
	if #opts.sets > 0 or opts.quick then
		print("基準は保存しない（値の上書き・--quick のときは保存しない）")
	else
		-- 今回回した目標だけ置き換え、ほかの目標の基準は残す
		local values = if baseline then baseline.values else {}
		for id, v in aggregated do
			values[id] = v
		end
		fs.writeFile(
			Settings.baselinePath,
			serde.encode(
				"json",
				{ savedAt = os.date("%Y-%m-%d %H:%M"), commit = commit, seeds = seeds, values = values },
				true
			)
		)
		print(`基準を保存: {Settings.baselinePath}`)
	end
end

if opts.quick then
	-- 動くかの確認：失敗した実行や計算できなかった指標があれば止める
	process.exit(if #failures > 0 then 1 else 0)
end
process.exit(0)
