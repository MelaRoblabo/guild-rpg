--!strict
-- デバッグ画面の文章（11章 §5、M7）。サーバーから届いた要約（view）を文章にする。
-- 見た目は作らない（UI は M8）。計算は Game.query に任せる。

local Game = require("@game/ReplicatedStorage/Core/Game")

local DebugView = {}

local PHASE = { outbound = "行き", floor = "探索中", inbound = "帰り", returned = "帰還済み" }

local function advName(view: any, uid: string): string
	local a = view.adventurers[uid]
	return if a then a.name else uid
end

local function expeditionOf(view: any, partyIndex: number): any?
	for _, e in view.expeditions do
		if e.partyIndex == partyIndex then
			return e
		end
	end
	return nil
end

local function sortedKeys(t: { [string]: any }): { string }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		local na, nb = tonumber(string.match(a, "%d+$")), tonumber(string.match(b, "%d+$"))
		if na and nb and na ~= nb then
			return na < nb
		end
		return a < b
	end)
	return keys
end

function DebugView.render(view: any, master: any, now: number): string
	local lines = {}
	local function add(s: string)
		table.insert(lines, s)
	end

	local g = view.guild
	local nextExp = master.raw.GuildLevels.levels[g.level]
	add(
		`所持金 {view.gold}G ／ ギルドLv{g.level}（{g.exp}/{if nextExp then nextExp.expToNext else "-"}） ／ チケット {view.items.itm_slot_ticket or 0}枚`
	)

	-- パーティと探索
	for i, p in view.parties do
		local names = {}
		for slot = 1, 4 do
			local uid = p.slots[slot]
			table.insert(names, if uid ~= "" then `{slot}:{advName(view, uid)}` else `{slot}:-`)
		end
		local e = expeditionOf(view, p.index or i)
		local status = "待機中"
		if e then
			local pr = Game.query.progress(e, now)
			local where = PHASE[pr.phase] or pr.phase
			if pr.phase == "floor" then
				where = `{pr.floorIndex}F`
			end
			status = `{master.dungeons[e.dungeonId].name} {where}（帰還まで {math.max(0, e.returnAt - now)} 秒）`
		end
		local rep = if p.autoRepeat then ` ／ 自動：{master.dungeons[p.autoRepeat.dungeonId].name}` else ""
		add(`パーティ{i} [{table.concat(names, " ")}] {status}{rep}`)
	end

	-- 宝箱（山ごとの数だけ。特別な宝箱の山も含む：D-087・D-166）と倉庫
	-- view.chests は { pileKey, count }（ランクなし。11章 §4.5）
	local chestText = {}
	for _, c in view.chests or {} do
		table.insert(chestText, `{c.pileKey}×{c.count}`)
	end
	local wh = Game.query.warehouse(view)
	add(`宝箱 {if #chestText > 0 then table.concat(chestText, " ") else "なし"} ／ 倉庫 {wh.used}/{wh.size}`)

	-- 冒険者
	add("── 冒険者 ──")
	for _, uid in sortedKeys(view.adventurers) do
		local a = view.adventurers[uid]
		local job = master.jobs[a.jobId]
		local eq = {}
		for _, slot in { "weapon", "armor", "sub" } do
			if a.equipment[slot] then
				table.insert(eq, a.equipment[slot])
			end
		end
		add(
			`{uid} {a.name}（{if job then job.name else a.jobId} Lv{a.level}/{a.levelCap} 転生{a.rebirthCount}）{if a.locked
				then " 保護"
				else ""} 装備[{table.concat(eq, ",")}]`
		)
	end

	-- 倉庫の中身（装備していないもの、先頭20件）
	add("── 倉庫 ──")
	local shown = 0
	for _, uid in sortedKeys(view.equipment) do
		local e = view.equipment[uid]
		if e.equippedBy == nil then
			shown += 1
			if shown <= 20 then
				local base = master.equipmentBases[e.baseId]
				add(
					`{uid} {if base then base.name else e.baseId} R{e.rarity} +{e.grade}{if e.modifierId
						then " " .. e.modifierId
						else ""}{if e.locked then " 保護" else ""}`
				)
			end
		end
	end
	if shown > 20 then
		add(`…ほか {shown - 20} 件`)
	end

	-- アイテム
	local items = {}
	for _, id in sortedKeys(view.items) do
		if view.items[id] > 0 then
			table.insert(items, `{id}×{view.items[id]}`)
		end
	end
	add(`アイテム {if #items > 0 then table.concat(items, " ") else "なし"}`)

	-- 途中の操作
	if view.hireSession then
		local h = view.hireSession
		add("── 面接中 ──")
		for i, c in h.candidates do
			add(`{i}: {c.name}（{c.jobId}）{if h.pickedIndex == i then " ←面接中" else ""}`)
		end
		local function stats(s: any?): string
			if s == nil then
				return "-"
			end
			return `腕{s.str} 魔{s.mag} 俊{s.agi} 技{s.dex} HP{s.hp}`
		end
		add(`前回 {stats(h.previousRoll)} ／ 今回 {stats(h.currentRoll)} ／ 無料あと{h.freeRerollsLeft}回`)
	end
	if view.rebirthSession then
		local r = view.rebirthSession
		add(`── 転生中（{r.adventurerUid}）── 無料あと{r.freeRerollsLeft}回`)
	end
	if view.appearanceSession then
		local s = view.appearanceSession
		add(`── 見た目の選択中（{s.adventurerUid}）── 前 {s.previousId} ／ 新 {s.currentId}`)
	end
	return table.concat(lines, "\n")
end

return DebugView
