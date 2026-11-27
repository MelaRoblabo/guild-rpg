--!strict
-- 体験スコアとバランスの成績の履歴（MX。D-301）
-- tools/balance/History.json に「名前つきの回」を足していき、型ごとの折れ線（HTML）で前と比べる。

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local History = {}

History.PATH = "tools/balance/History.json"

function History.load(): { any }
	if not fs.isFile(History.PATH) then
		return {}
	end
	local ok, data = pcall(serde.decode, "json", fs.readFile(History.PATH))
	if ok and type(data) == "table" and type(data.entries) == "table" then
		return data.entries
	end
	return {}
end

function History.append(entry: any)
	local entries = History.load()
	table.insert(entries, entry)
	fs.writeFile(History.PATH, serde.encode("json", { entries = entries }, true))
end

local function esc(s: string): string
	return (string.gsub(s, '[&<>"]', { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }))
end

-- 線の色（分類の順）。総合は太い線
local COLORS = { "#4e79a7", "#f28e2b", "#59a14f", "#e15759", "#b07aa1", "#76b7b2", "#edc948" }

local function chart(es: any, entries: { any }, profile: string): string
	local W, H, L, R, T, B = 720, 300, 40, 16, 16, 64
	local n = #entries
	local function x(i: number): number
		if n <= 1 then
			return L + (W - L - R) / 2
		end
		return L + (i - 1) * (W - L - R) / (n - 1)
	end
	local function y(v: number): number
		return T + (100 - v) * (H - T - B) / 100
	end
	local parts = {
		`<svg viewBox="0 0 {W} {H}" role="img" aria-label="{esc(profile)} の体験スコアの推移">`,
	}
	for _, g in { 0, 25, 50, 75, 100 } do
		table.insert(parts, `<line x1="{L}" x2="{W - R}" y1="{y(g)}" y2="{y(g)}" class="grid"/>`)
		table.insert(parts, `<text x="{L - 6}" y="{y(g) + 4}" class="axis" text-anchor="end">{g}</text>`)
	end
	for i, e in entries do
		local label = esc(string.sub(e.label or "", 1, 24))
		table.insert(
			parts,
			`<text x="{x(i)}" y="{H - B + 16}" class="axis" text-anchor="end" transform="rotate(-30 {x(i)} {H - B + 16})">{label}</text>`
		)
	end
	local function series(get: (any) -> number?, color: string, width: number, title: string)
		local pts = {}
		for i, e in entries do
			local v = get(e)
			if v ~= nil then
				table.insert(pts, string.format("%.1f,%.1f", x(i), y(v)))
			end
		end
		if #pts == 0 then
			return
		end
		table.insert(
			parts,
			`<polyline points="{table.concat(pts, " ")}" fill="none" stroke="{color}" stroke-width="{width}"><title>{esc(
				title
			)}</title></polyline>`
		)
		for i, e in entries do
			local v = get(e)
			if v ~= nil then
				table.insert(
					parts,
					string.format(
						'<circle cx="%.1f" cy="%.1f" r="%d" fill="%s"><title>%s：%.0f</title></circle>',
						x(i),
						y(v),
						if width > 2 then 4 else 3,
						color,
						esc(title),
						v
					)
				)
			end
		end
	end
	for k, cat in es.categories do
		series(function(e)
			local s = e.scores and e.scores[profile]
			return s and s.categories and s.categories[cat.id]
		end, COLORS[(k - 1) % #COLORS + 1], 2, cat.name)
	end
	series(function(e)
		local s = e.scores and e.scores[profile]
		return s and s.total
	end, "var(--ink)", 4, "総合")
	table.insert(parts, "</svg>")
	return table.concat(parts, "\n")
end

-- 履歴の HTML（1枚、外部のファイルを使わない）
function History.html(es: any, entries: { any }): string
	local legend = {}
	for k, cat in es.categories do
		table.insert(
			legend,
			`<span class="key"><i style="background:{COLORS[(k - 1) % #COLORS + 1]}"></i>{esc(cat.name)}</span>`
		)
	end
	table.insert(legend, `<span class="key"><i class="total"></i>総合</span>`)
	local body = {}
	for _, p in es.profiles do
		table.insert(body, `<section><h2>{esc(p)}</h2>{chart(es, entries, p)}</section>`)
	end
	-- 表：回ごとの総合とバランスの成績
	local rows = {}
	for i = #entries, 1, -1 do
		local e = entries[i]
		local cells = { `<td>{esc(e.date or "")}</td><td>{esc(e.label or "")}</td><td>{esc(e.commit or "")}</td>` }
		for _, p in es.profiles do
			local s = e.scores and e.scores[p]
			table.insert(
				cells,
				`<td class="num">{if s and s.total then string.format("%.0f", s.total) else "—"}</td>`
			)
		end
		local b = e.balance or {}
		table.insert(cells, `<td class="num">{b.pass or "—"} / {b.fail or "—"}</td>`)
		table.insert(cells, `<td>{esc(table.concat(e.sets or {}, "、"))}</td>`)
		table.insert(rows, `<tr>{table.concat(cells)}</tr>`)
	end
	local profHead = {}
	for _, p in es.profiles do
		table.insert(profHead, `<th>{esc(p)}</th>`)
	end
	return table.concat({
		'<!doctype html><html lang="ja"><head><meta charset="utf-8">',
		'<meta name="viewport" content="width=device-width, initial-scale=1">',
		"<title>体験スコアの推移</title><style>",
		":root{--bg:#fbfaf7;--ink:#222;--sub:#666;--line:#ddd}",
		"@media (prefers-color-scheme: dark){:root{--bg:#1b1b1d;--ink:#eee;--sub:#aaa;--line:#3a3a3a}}",
		"body{margin:0;padding:16px;background:var(--bg);color:var(--ink);font-family:system-ui,sans-serif}",
		"main{max-width:780px;margin:auto}svg{width:100%;height:auto}.grid{stroke:var(--line)}",
		".axis{fill:var(--sub);font-size:11px}.key{display:inline-flex;align-items:center;gap:4px;margin-right:12px;font-size:13px}",
		".key i{width:14px;height:3px;display:inline-block}.key i.total{background:var(--ink);height:5px}",
		"table{border-collapse:collapse;width:100%;font-size:13px}td,th{border-bottom:1px solid var(--line);padding:4px 6px;text-align:left}",
		".num{text-align:right}.wrap{overflow-x:auto}",
		"</style></head><body><main>",
		"<h1>体験スコアの推移（D-301）</h1>",
		"<p>自動プレイの出来事から出した「理論上、続けたくなるか」の点数（0〜100）。本当に面白いかは人のテストプレイで確かめる。</p>",
		`<p>{table.concat(legend, "")}</p>`,
		table.concat(body, "\n"),
		'<h2>回ごと</h2><div class="wrap"><table><tr><th>日時</th><th>名前</th><th>コミット</th>',
		table.concat(profHead),
		"<th>バランス 合格/不合格</th><th>値の上書き</th></tr>",
		table.concat(rows, "\n"),
		"</table></div></main></body></html>",
	}, "\n")
end

return History
