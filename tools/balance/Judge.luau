--!strict
-- 成績表の判定と書き出し（MB）。目標は src/data/BalanceTargets.luau、基準は Settings.baselinePath（D-295）

local Settings = require("./Settings")

local Judge = {}

-- values：seed の順の値（出なかった seed は false）。sd：標準偏差、se：平均の標準誤差（sd ÷ √n）
export type Agg = {
	mean: number?,
	min: number?,
	max: number?,
	n: number,
	missing: number,
	sd: number?,
	se: number?,
	values: { any }?,
}

-- seed ごとの値（数か、名前つきの数の表）を平均する
function Judge.aggregate(values: { any }, expected: number): any
	local isTable = false
	for _, v in values do
		if type(v) == "table" then
			isTable = true
		end
	end
	if not isTable then
		local sum, n, lo, hi = 0, 0, math.huge, -math.huge
		local list = {}
		for _, v in values do
			if type(v) == "number" then
				sum += v
				n += 1
				lo = math.min(lo, v)
				hi = math.max(hi, v)
				table.insert(list, v)
			else
				table.insert(list, false)
			end
		end
		local mean = if n > 0 then sum / n else nil
		local sd = nil
		if mean ~= nil and n > 1 then
			local ss = 0
			for _, v in list do
				if type(v) == "number" then
					ss += (v - mean) ^ 2
				end
			end
			sd = math.sqrt(ss / (n - 1))
		end
		return {
			mean = mean,
			min = if n > 0 then lo else nil,
			max = if n > 0 then hi else nil,
			n = n,
			missing = expected - n,
			sd = sd,
			se = if sd then sd / math.sqrt(n) else nil,
			values = list,
		} :: Agg
	end
	local keys: { [string]: { any } } = {}
	for _, v in values do
		if type(v) == "table" then
			for k, x in v do
				keys[k] = keys[k] or {}
				table.insert(keys[k], x)
			end
		end
	end
	local out = {}
	for k, list in keys do
		out[k] = Judge.aggregate(list, expected)
	end
	return out
end

local function fmt(x: number?, digits: number?): string
	if x == nil then
		return "—"
	end
	local d = digits or 2
	if math.abs(x) >= 100 then
		return string.format("%.0f", x)
	end
	return string.format(`%.{d}f`, x)
end

local function targetValue(t: any, profile: string?, key: string?): number?
	if key and t.byDungeon and t.byDungeon[key] ~= nil then
		return t.byDungeon[key]
	end
	if profile and t.byProfile and t.byProfile[profile] ~= nil then
		return t.byProfile[profile]
	end
	return t.value
end

-- 1つの数を判定する。戻り値：状態（"pass"・"fail"）と目標の書き方
local function judgeNumber(t: any, mean: number, goal: number): (string, string)
	if t.judge == "atLeast" then
		return if mean >= goal then "pass" else "fail", `≥ {fmt(goal)}`
	elseif t.judge == "atMost" then
		return if mean <= goal then "pass" else "fail", `≤ {fmt(goal)}`
	end
	local width = if t.tolAbs ~= nil then t.tolAbs else goal * (t.tol or 0)
	local ok = math.abs(mean - goal) <= width + 1e-9
	local text = if t.tolAbs ~= nil
		then `{fmt(goal)} ± {fmt(t.tolAbs)}`
		else `{fmt(goal)} ± {fmt((t.tol or 0) * 100, 0)}%`
	return if ok then "pass" else "fail", text
end

-- 基準との差。警告の幅を超えたら true
local function deviates(now: number, base: number, unit: string?): boolean
	local diff = math.abs(now - base)
	if unit == "days" and diff < Settings.baselineMinDays then
		return false
	end
	if unit == "pt" and diff < Settings.baselineMinPt then
		return false
	end
	if base == 0 then
		return diff > 0
	end
	return diff / math.abs(base) > Settings.baselineWarnRel
end

-- 揺れの範囲：今と基準の平均の差が、2つの標準誤差を合わせた幅の2倍以内なら、seed の揺れで説明できる差
function Judge.withinNoise(now: number?, base: number?, nowSe: number?, baseSe: number?): boolean
	if now == nil or base == nil or (nowSe == nil and baseSe == nil) then
		return false
	end
	local se = math.sqrt((nowSe or 0) ^ 2 + (baseSe or 0) ^ 2)
	return math.abs(now - base) <= 2 * se
end

local function baseDiffText(now: number?, base: number?, nowSe: number?, baseSe: number?): string
	if now == nil or base == nil then
		return "—"
	end
	local noise = if Judge.withinNoise(now, base, nowSe, baseSe) then "（揺れの範囲）" else ""
	if base == 0 then
		return (if now == 0 then "±0" else "新") .. noise
	end
	local d = (now - base) / math.abs(base) * 100
	return string.format("%+.0f%%", d) .. noise
end

local function seOf(x: any): number?
	return if type(x) == "table" then x.se else nil
end

local function unitOf(metric: string): string?
	if metric == "milestoneDays" or metric == "daysToMaxGrowth" then
		return "days"
	end
	if string.sub(metric, 1, 5) == "share" or metric == "friendGoldShare" then
		return "pt"
	end
	return nil
end

-- 1つの目標×1つのまとまり（型・友達の数、または sim）を判定する
-- agg：Judge.aggregate の結果。base：基準の同じ場所の値（あれば）
function Judge.judge(t: any, profile: string?, agg: any, base: any, cap: number?): any
	local res =
		{ target = t, profile = profile, status = "pass", details = {}, summary = "", goal = "", baseDiff = "—" }
	local unit = unitOf(t.metric)

	if t.judge == "baseline" then
		res.goal = "基準から大きくずれない（D-295）"
		if base == nil then
			res.status = "info"
			res.summary = "基準なし"
		end
		local function check(key: string, a: Agg, b: any)
			local bmean = if type(b) == "table" then b.mean else nil
			-- 揺れの範囲の差は警告しない（seed の揺れで説明できる）
			local warn = a.mean ~= nil
				and bmean ~= nil
				and deviates(a.mean, bmean, unit)
				and not Judge.withinNoise(a.mean, bmean, a.se, seOf(b))
			if warn then
				res.status = "warn"
			end
			table.insert(res.details, {
				key = key,
				now = a,
				goal = if bmean ~= nil then `基準 {fmt(bmean)}` else "—",
				status = if bmean == nil then "info" elseif warn then "warn" else "pass",
				baseDiff = baseDiffText(a.mean, bmean, a.se, seOf(b)),
			})
		end
		if agg.mean ~= nil or agg.n ~= nil then
			check("", agg, base)
			res.summary = fmt(agg.mean)
		else
			for key, a in agg do
				check(key, a, if type(base) == "table" then base[key] else nil)
			end
			if res.summary == "" then
				res.summary = `{#res.details}項目`
			end
		end
		return res
	end

	if t.judge == "share" then
		res.goal = `各列 ± {fmt(t.tolPt, 0)}pt`
		local fails = 0
		local cols = {}
		for k in t.columns do
			table.insert(cols, k)
		end
		table.sort(cols)
		for _, col in cols do
			local goal = t.columns[col]
			local a: Agg = agg[col] or { mean = 0, n = 0, missing = 0 }
			local ok = a.mean ~= nil and math.abs(a.mean - goal) <= t.tolPt + 1e-9
			if not ok then
				fails += 1
			end
			local bAgg = if type(base) == "table" then base[col] else nil
			local b = if type(bAgg) == "table" then bAgg.mean else nil
			table.insert(res.details, {
				key = col,
				now = a,
				goal = `{goal} ± {t.tolPt}`,
				status = if ok then "pass" else "fail",
				baseDiff = baseDiffText(a.mean, b, a.se, seOf(bAgg)),
			})
		end
		if fails > 0 then
			res.status = "fail"
		end
		res.summary = `{#cols - fails}/{#cols} 列が範囲内`
		return res
	end

	-- near・atLeast・atMost
	if agg.n ~= nil then
		local a: Agg = agg
		local goal = targetValue(t, profile, nil)
		assert(goal, `目標の値がない: {t.id}`)
		local status, text = "pass", ""
		if a.missing > 0 or a.mean == nil then
			status = "fail"
			_, text = judgeNumber(t, 0, goal)
			res.summary = if t.metric == "daysToMaxGrowth" and cap
				then `未到達 {a.missing}/{a.n + a.missing}（>{cap}日）`
				else `測れない {a.missing}/{a.n + a.missing}`
			if a.mean ~= nil then
				res.summary ..= `、届いた分の平均 {fmt(a.mean)}`
			end
		else
			status, text = judgeNumber(t, a.mean :: number, goal)
			res.summary = if a.n > 1 then `{fmt(a.mean)}（{fmt(a.min)}〜{fmt(a.max)}）` else fmt(a.mean)
		end
		res.status = status
		res.goal = text
		res.baseDiff = baseDiffText(a.mean, if type(base) == "table" then base.mean else nil, a.se, seOf(base))
		return res
	end

	-- 名前つき（sim のダンジョンごと）
	local keys = {}
	for k in agg do
		table.insert(keys, k)
	end
	table.sort(keys)
	local fails = 0
	for _, key in keys do
		local a: Agg = agg[key]
		local goal = targetValue(t, profile, key)
		if goal == nil or a.mean == nil then
			continue
		end
		local status, text = judgeNumber(t, a.mean :: number, goal)
		if status == "fail" then
			fails += 1
		end
		local b = if type(base) == "table" and base[key] then base[key].mean else nil
		table.insert(
			res.details,
			{ key = key, now = a, goal = text, status = status, baseDiff = baseDiffText(a.mean, b) }
		)
	end
	if fails > 0 then
		res.status = "fail"
	end
	res.summary = `{#res.details - fails}/{#res.details} が範囲内`
	res.goal = if t.value ~= nil then (select(2, judgeNumber(t, t.value, t.value))) else "ダンジョンごと"
	return res
end

local MARK = { pass = "✅", fail = "❌", warn = "⚠️", info = "—" }

-- 成績表（Markdown）
function Judge.render(results: { any }, meta: any): string
	local counts = { pass = 0, fail = 0, warn = 0, info = 0 }
	for _, r in results do
		counts[r.status] += 1
	end
	local lines = {
		"# バランスの成績表",
		"",
		`- 日時：{meta.date} ／ コミット：{meta.commit}{if meta.dirty
			then "（未コミットの変更あり）"
			else ""}`,
		`- 目標：src/data/BalanceTargets.luau ／ 基準：{meta.baselineText}`,
		`- 自動プレイ：型 {meta.profiles} × seed {meta.seeds}（{meta.runCount}回、方針 greedy）／ 探索シミュレーター：1ダンジョン {meta.simRuns}回`,
		`- 値の上書き：{if #meta.sets > 0 then table.concat(meta.sets, "、") else "なし"}`,
		`- 実行時間：{string.format("%.0f", meta.elapsed)}秒`,
		"",
		string.format(
			"**合格 %d ／ 不合格 %d ／ 警告 %d ／ 基準なし %d**",
			counts.pass,
			counts.fail,
			counts.warn,
			counts.info
		),
		"",
		"| | 目標 | 決定 | 型 | 実測（平均・最小〜最大） | 目標値 | 基準との差 |",
		"| --- | --- | --- | --- | --- | --- | --- |",
	}
	for _, r in results do
		table.insert(
			lines,
			string.format(
				"| %s | %s | %s | %s | %s | %s | %s |",
				MARK[r.status],
				r.target.name,
				r.target.decision,
				r.profile or "—",
				r.summary,
				r.goal,
				r.baseDiff
			)
		)
	end
	for _, r in results do
		if #r.details > 0 then
			table.insert(lines, "")
			table.insert(lines, `## {MARK[r.status]} {r.target.name}{if r.profile then `（{r.profile}）` else ""}`)
			table.insert(lines, "")
			table.insert(lines, "| | 項目 | 実測（平均・最小〜最大） | 目標 | 基準との差 |")
			table.insert(lines, "| --- | --- | --- | --- | --- |")
			table.sort(r.details, function(a, b)
				local am, bm = a.now.mean or math.huge, b.now.mean or math.huge
				if r.target.metric == "milestoneDays" then
					return am < bm
				end
				return a.key < b.key
			end)
			for _, d in r.details do
				local a = d.now
				local v = if a.n
						and a.n > 1
						and a.min ~= a.max
					then `{fmt(a.mean)}（{fmt(a.min)}〜{fmt(a.max)}）`
					else fmt(a.mean)
				if a.missing and a.missing > 0 then
					v ..= `（出なかった seed {a.missing}）`
				end
				table.insert(
					lines,
					string.format("| %s | %s | %s | %s | %s |", MARK[d.status], d.key, v, d.goal, d.baseDiff)
				)
			end
		end
	end
	return table.concat(lines, "\n") .. "\n"
end

return Judge
