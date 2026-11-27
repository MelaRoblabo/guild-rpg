--!strict
-- 体験スコア（MX。D-301）：体験の指標の平均を、src/data/ExperienceScores.luau の線で0〜100点にする
-- 線や重みはここに書かない。

local Score = {}

-- good で100点、bad で0点、その間は直線（範囲の外は0か100）
function Score.item(value: number?, good: number, bad: number): number?
	if value == nil then
		return nil
	end
	local t = (value - bad) / (good - bad)
	return math.clamp(t, 0, 1) * 100
end

-- 表で使う指標の名前の一覧
function Score.metrics(es: any): { string }
	local out = {}
	for _, cat in es.categories do
		for _, item in cat.items do
			if not table.find(out, item.metric) then
				table.insert(out, item.metric)
			end
		end
	end
	return out
end

-- means：指標の名前 → 平均（seed の平均）。戻り値：{ total, categories = { [id] = 点 }, items = { [metric] = 点 } }
function Score.profile(es: any, means: { [string]: number? }): any
	local cats = {}
	local items = {}
	local sum, wsum = 0, 0
	for _, cat in es.categories do
		local s, n = 0, 0
		for _, item in cat.items do
			local v = Score.item(means[item.metric], item.good, item.bad)
			items[item.metric] = v
			if v ~= nil then
				s += v
				n += 1
			end
		end
		if n > 0 then
			cats[cat.id] = s / n
			sum += cats[cat.id] * cat.weight
			wsum += cat.weight
		end
	end
	return { total = if wsum > 0 then sum / wsum else nil, categories = cats, items = items }
end

local function fmt(x: number?): string
	return if x == nil then "—" else string.format("%.0f", x)
end

local function diff(now: number?, before: number?): string
	if now == nil or before == nil then
		return ""
	end
	local d = now - before
	if math.abs(d) < 0.5 then
		return "（±0）"
	end
	return string.format("（%+.0f）", d)
end

-- 成績表に足す Markdown。scores：型 → Score.profile の結果。prev：履歴の最後の項目（比べる相手）
function Score.render(es: any, scores: { [string]: any }, means: { [string]: any }, prev: any?): string
	local profs = {}
	for _, p in es.profiles do
		if scores[p] then
			table.insert(profs, p)
		end
	end
	if #profs == 0 then
		return ""
	end
	local lines = {
		"",
		"## 体験スコア（D-301。理論上、続けたくなるか）",
		"",
		if prev
			then `（ ）内は履歴の最後「{prev.label}」（{prev.date}）との差`
			else "履歴はまだない（--label で残す）",
		"",
	}
	local header, sep = "| 分類 |", "| --- |"
	for _, p in profs do
		header ..= ` {p} |`
		sep ..= " --- |"
	end
	table.insert(lines, header)
	table.insert(lines, sep)
	local function prevOf(p: string, id: string?): number?
		local ps = prev and prev.scores and prev.scores[p]
		if ps == nil then
			return nil
		end
		return if id then ps.categories and ps.categories[id] else ps.total
	end
	for _, cat in es.categories do
		local row = `| {cat.name} |`
		for _, p in profs do
			local v = scores[p].categories[cat.id]
			row ..= ` {fmt(v)}{diff(v, prevOf(p, cat.id))} |`
		end
		table.insert(lines, row)
	end
	local row = "| **総合** |"
	for _, p in profs do
		row ..= ` **{fmt(scores[p].total)}**{diff(scores[p].total, prevOf(p, nil))} |`
	end
	table.insert(lines, row)

	-- 指標ごとの値と点
	table.insert(lines, "")
	table.insert(lines, "| 分類 | 指標 | 良い線／悪い線 | " .. table.concat(profs, " | ") .. " |")
	table.insert(lines, "| --- | --- | --- |" .. string.rep(" --- |", #profs))
	for _, cat in es.categories do
		for _, item in cat.items do
			local r = `| {cat.name} | {item.name} | {item.good}／{item.bad} |`
			for _, p in profs do
				local m = means[p] and means[p][item.metric]
				local v = scores[p].items[item.metric]
				r ..= if m == nil then " — |" else string.format(" %.2f → %s点 |", m, fmt(v))
			end
			table.insert(lines, r)
		end
	end
	return table.concat(lines, "\n") .. "\n"
end

return Score
