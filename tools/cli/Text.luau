--!strict
-- テキスト版の表示（文章化のみ。ルールは持たない：D-066）

local Game = require("../../src/core/Game")

local Text = {}

local START_CLOCK = 1767225600
-- レアリティ名はマスターデータから作る（D-085：レアリティは増える）
local RANK_NAME: { string } = {}
for _, r in require("../../src/data/Rarities") do
	RANK_NAME[r.rank] = r.name
end
local SLOT_NAME = { weapon = "武器", armor = "防具", sub = "補助" }
local STAT_NAME = { str = "腕力", mag = "魔力", agi = "俊敏", dex = "技巧", hp = "HP" }

local ERRORS = {
	PARTY_NOT_FOUND = "そのパーティはありません",
	INVALID_SLOT = "隊列は1〜4です",
	PARTY_BUSY = "そのパーティは探索中です",
	ADVENTURER_NOT_FOUND = "その冒険者はいません",
	ADVENTURER_IN_OTHER_PARTY = "その冒険者は別のパーティにいます",
	ITEM_NOT_FOUND = "そのアイテムはありません",
	ADVENTURER_ON_EXPEDITION = "探索中は変更できません",
	JOB_CANNOT_EQUIP = "この職業では装備できません",
	ITEM_EQUIPPED = "装備中の品です",
	SLOT_EMPTY = "その枠には何も装備していません",
	WAREHOUSE_FULL = "倉庫がいっぱいです",
	DUNGEON_NOT_FOUND = "そのダンジョンはありません",
	DUNGEON_LOCKED = "そのダンジョンはまだ解放されていません",
	PARTY_EMPTY = "パーティに誰もいません",
	NO_CHEST = "開ける宝箱がありません",
	ITEM_LOCKED = "保護中の品です",
	ITEM_NOT_SELLABLE = "このアイテムは売れません",
	NOT_ENOUGH_ITEMS = "数が足りません",
	NOT_FOUND = "見つかりません",
	UNKNOWN_COMMAND = "不明なコマンドです",
	SESSION_EXISTS = "雇用の途中です（candidates で確認、cancel でやめる）",
	ROSTER_FULL = "所属枠がいっぱいです",
	NOT_ENOUGH_GOLD = "お金が足りません",
	NO_SESSION = "雇用を始めていません（hire）",
	ALREADY_PICKED = "面接する候補はもう選んでいます",
	CANDIDATE_NOT_FOUND = "その番号の候補はいません",
	NOT_PICKED = "まず面接する候補を選んでください（pick）",
	UNIQUE_FIXED_STATS = "特別な訪問者のステータスは固定です",
	NO_TICKET = "ステータススロットチケットがありません",
	INVALID_CHOICE = "prev か cur を指定してください",
	UNIQUE_CANNOT_RENAME = "ユニークキャラの名前は変えられません",
	INVALID_NAME = "名前は1〜12文字です",
	ADVENTURER_LOCKED = "保護中の冒険者です",
	LEVEL_NOT_AT_CAP = "レベル上限に達していません",
	MAX_REBIRTH = "これ以上転生できません",
	UNIQUE_APPEARANCE_FIXED = "ユニークキャラの見た目は固定です",
	NO_POTION = "ポーションがありません",
	ADVENTURER_IN_REBIRTH = "転生の途中の冒険者がいます",
	ADVENTURER_IN_SESSION = "転生・見た目変更の途中です",
	JOB_NOT_FOUND = "その職業はありません",
	SAME_JOB = "すでにその職業です",
	UNIQUE_JOB_RESTRICTED = "このユニークキャラはその職業に転職できません",
	UNIQUE_CANNOT_CHANGE = "ユニークキャラの見た目は変えられません",
	EXPANSION_NOT_FOUND = "その拡張はありません",
	EXPANSION_MAXED = "これ以上拡張できません",
	GUILD_LEVEL_TOO_LOW = "ギルドレベルが足りません",
	DUNGEON_NOT_CLEARED = "必要なダンジョンをまだ踏破していません",
	INVALID_RARITY = "レアリティは1〜5です",
	TRAINING_CAP = "トレーニングで上げられる上限です（トレーニング場の改修か、ダンジョンで育ててください）",
	INVALID_COUNT = "回数は1以上の整数です",
	CHEST_RANK_TOO_HIGH = "解錠技術が足りず開けられない宝箱です（expand exp_unlock）",
}

function Text.errorText(code: string?): string
	return ERRORS[code or ""] or tostring(code)
end

local function hms(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d:%02d", sec // 3600, (sec % 3600) // 60, sec % 60)
end

function Text.clock(save: any): string
	return "経過 " .. hms(save.clock - START_CLOCK)
end

local function advName(save: any, uid: string): string
	local a = save.state.adventurers[uid]
	return if a then a.name else uid
end

local function equipName(e: any, master: any): string
	local base = master.equipmentBases[e.baseId]
	local mod = if e.modifierId then master.modifiers[e.modifierId].name else ""
	local grade = if e.grade > 0 then `+{e.grade}` else ""
	return `{mod}{base.name}{grade}［{RANK_NAME[e.rarity]}・IL{e.itemLevel or 1}］`
end

local function partyStatus(save: any, i: number, master: any): string
	local e = Game.query.expeditionOf(save.state, i)
	if not e then
		return "待機中"
	end
	local d = master.dungeons[e.dungeonId]
	local p = Game.query.progress(e, save.clock)
	local remain = e.returnAt - save.clock
	local where
	if p.phase == "outbound" then
		where = "移動中（行き）"
	elseif p.phase == "floor" then
		local f = e.log.floors[p.floorIndex]
		where = `{f.floor}F {if f.kind == "battle" then "戦闘中" else "イベント"}`
	elseif p.phase == "inbound" then
		where = "帰還中"
	else
		where = "帰還済み"
	end
	return `{d.name}を探索中：{where}（帰還まで {remain} 秒）`
end

function Text.status(save: any, master: any): string
	local s = save.state
	local lines = {
		`【{Text.clock(save)}】 所持金 {s.gold}G ／ ギルドLv{s.guild.level}（次まで {s.guild.exp}/{master.raw.GuildLevels.levels[s.guild.level].expToNext}） ／ チケット {s.items.itm_slot_ticket or 0}枚`,
	}
	for i, p in s.parties do
		local names = {}
		for slot = 1, 4 do
			local uid = p.slots[slot]
			table.insert(names, if uid ~= "" then `{slot}:{advName(save, uid)}` else `{slot}:-`)
		end
		local rep = if p.autoRepeat then ` ／ 自動再派遣：{master.dungeons[p.autoRepeat.dungeonId].name}` else ""
		table.insert(lines, `パーティ{i} [{table.concat(names, " ")}] {partyStatus(save, i, master)}{rep}`)
	end
	local byRank = Game.query.chestsByRank(s, master)
	local totalChests = 0
	for _, n in byRank do
		totalChests += n
	end
	local chestText = {}
	for r = 1, #byRank do
		if byRank[r] > 0 then
			table.insert(chestText, `{RANK_NAME[r]}×{byRank[r]}`)
		end
	end
	local wh = Game.query.warehouse(s)
	table.insert(
		lines,
		`未開封の宝箱 {totalChests}個{if #chestText > 0
			then "（" .. table.concat(chestText, "、") .. "）"
			else ""} ／ 開けられるのは{RANK_NAME[s.expansions.unlockRank]}まで ／ 倉庫 {wh.used}/{wh.size}`
	)
	local fac = master.K.trainingFacility[s.expansions.trainingLevel]
	table.insert(
		lines,
		`トレーニング場 Lv{s.expansions.trainingLevel}（Lv{fac.levelCap}まで、1回 経験値{fac.expPerSession}）`
	)
	return table.concat(lines, "\n")
end

function Text.roster(save: any, master: any): string
	local list = {}
	for _, a in save.state.adventurers do
		table.insert(list, a)
	end
	table.sort(list, function(a, b)
		return tonumber(string.sub(a.uid, 5)) < tonumber(string.sub(b.uid, 5))
	end)
	local lines = {}
	for _, a in list do
		local snap = Game.query.snapshot(save.state, a.uid, master)
		table.insert(
			lines,
			`{a.uid} {a.name}（{master.jobs[a.jobId].name} Lv{a.level}/{a.levelCap}）HP{snap.maxHp} 攻{snap.atk} 物防{snap.pdef} 魔防{snap.mdef} 俊{snap.agi} 技{snap.dex}{if a.locked
				then " 🔒"
				else ""}`
		)
	end
	return table.concat(lines, "\n")
end

function Text.adventurer(save: any, uid: string, master: any): string
	local a = save.state.adventurers[uid]
	if not a then
		return Text.errorText("ADVENTURER_NOT_FOUND")
	end
	local snap = Game.query.snapshot(save.state, uid, master)
	local job = master.jobs[a.jobId]
	local growth = {}
	for _, k in { "str", "mag", "agi", "dex", "hp" } do
		table.insert(growth, `{STAT_NAME[k]}{job.growth[k]}`)
	end
	local gifts = {}
	for _, g in a.giftIds do
		table.insert(gifts, master.gifts[g].name)
	end
	local lines = {
		`{a.name}（{job.name}・{if job.attackType == "physical" then "物理攻撃職" else "魔法攻撃職"}） Lv{a.level}/{a.levelCap} 経験値 {a.exp}/{Game.query.expToNext(
			a.level,
			master,
			a.rebirthCount
		)} 転生{a.rebirthCount}回`,
		`基礎：腕力{a.baseStats.str} 魔力{a.baseStats.mag} 俊敏{a.baseStats.agi} 技巧{a.baseStats.dex} HP{a.baseStats.hp}`,
		`実効：HP{snap.maxHp} 攻撃力{snap.atk} 物理防御{snap.pdef} 魔法防御{snap.mdef} 俊敏{snap.agi} 技巧{snap.dex}`,
		`成長の型：{table.concat(growth, " ")}`,
		`ギフト：{if #gifts > 0 then table.concat(gifts, "・") else "なし"}`,
		`経験値補正：+{math.floor(snap.expRate * 100 + 0.5)}% ／ トレーニング1回 {Game.query.trainingSessionCost(
			a.level,
			master
		)}G ／ 転生費用 {Game.query.rebirthCost(save.state, uid, master)}G`,
	}
	for _, slot in { "weapon", "armor", "sub" } do
		local eu = a.equipment[slot]
		table.insert(
			lines,
			`{SLOT_NAME[slot]}：{if eu then eu .. " " .. equipName(save.state.equipment[eu], master) else "なし"}`
		)
	end
	return table.concat(lines, "\n")
end

function Text.warehouse(save: any, master: any): string
	local list = {}
	for _, e in save.state.equipment do
		if e.equippedBy == nil then
			table.insert(list, e)
		end
	end
	table.sort(list, function(a, b)
		if a.rarity ~= b.rarity then
			return a.rarity > b.rarity
		end
		return tonumber(string.sub(a.uid, 4)) < tonumber(string.sub(b.uid, 4))
	end)
	local wh = Game.query.warehouse(save.state)
	local lines = { `倉庫 {wh.used}/{wh.size}` }
	for _, e in list do
		local base = master.equipmentBases[e.baseId]
		local mod = ""
		if e.modifierId then
			local m = master.modifiers[e.modifierId]
			mod = if m.effect.kind == "flatStat"
				then ` {m.name}：{STAT_NAME[m.effect.stat]}+{e.modifierValue}`
				else ` {m.name}：+{math.floor(e.modifierValue * 100 + 0.5)}%`
		end
		table.insert(
			lines,
			`{e.uid} {equipName(e, master)} 枠:{SLOT_NAME[base.slot]}{mod} 売値{Game.query.sellPrice(e, master)}G{if e.locked
				then " 🔒"
				else ""}`
		)
	end
	return table.concat(lines, "\n")
end

function Text.items(save: any, master: any): string
	local lines = {}
	for id, n in save.state.items do
		if n > 0 then
			table.insert(lines, `{id} {master.items[id].name} ×{n}`)
		end
	end
	table.sort(lines)
	return if #lines > 0 then table.concat(lines, "\n") else "アイテムはありません"
end

function Text.dungeons(save: any, master: any): string
	local lines = {}
	for _, d in master.dungeonList do
		local s = save.state
		local mark = if s.clearedDungeons[d.id]
			then "踏破済"
			elseif s.unlockedDungeons[d.id] then "解放済"
			else "未解放"
		local fee = if d.dispatchFee then `・派遣費{d.dispatchFee}G` else ""
		table.insert(lines, `{d.id} {d.name}（{d.floors}F・難度{d.tier}{fee}）{mark}`)
	end
	return table.concat(lines, "\n")
end

-- 宝箱のレアリティの出現率（D-085）
local function rarityOdds(d: any): string
	local total = 0
	for _, w in d.chestRarityWeights do
		total += w
	end
	local parts = {}
	for r, w in d.chestRarityWeights do
		if w > 0 then
			table.insert(parts, `{RANK_NAME[r]}{math.floor(w / total * 100 + 0.5)}%`)
		end
	end
	return table.concat(parts, "・")
end

function Text.hint(id: string, master: any): string
	local d = master.dungeons[id]
	if not d then
		return Text.errorText("DUNGEON_NOT_FOUND")
	end
	local total, magic = 0, 0
	local races = {}
	for _, m in d.monsters do
		local mon = master.monsters[m.id]
		total += m.weight
		if mon.attackType == "magic" then
			magic += m.weight
		end
		races[mon.raceTag] = (races[mon.raceTag] or 0) + m.weight
	end
	local raceText = {}
	for r, w in races do
		table.insert(raceText, `{r} {math.floor(w / total * 100 + 0.5)}%`)
	end
	table.sort(raceText)
	return table.concat({
		`{d.name}（{d.floors}F・難度{d.tier}）`,
		`攻撃：物理 {math.floor((total - magic) / total * 100 + 0.5)}% ／ 魔法 {math.floor(
			magic / total * 100 + 0.5
		)}%`,
		`種族：{table.concat(raceText, "、")}`,
		`罠レベル {d.trapLevel} ／ 宝箱 {rarityOdds(d)}`,
		`敵の目安：HP{d.base.hp} 攻撃{d.base.atk} 物防{d.base.pdef} 魔防{d.base.mdef}（戦闘ごとに+20%）`,
	}, "\n")
end

local EVENT_NAME =
	{ chest = "宝箱", item = "アイテム", trap = "罠", fountain = "回復の泉", none = "なにもなし" }

function Text.watch(save: any, partyIndex: number, master: any): string
	local e = Game.query.expeditionOf(save.state, partyIndex)
	if not e then
		return `パーティ{partyIndex}は待機中です`
	end
	local t = save.clock - e.departAt
	local lines = { partyStatus(save, partyIndex, master) }
	for _, f in e.log.floors do
		if f.startOffset > t then
			break
		end
		local done = f.startOffset + f.duration <= t
		local text
		if f.kind == "battle" then
			text = `{f.floor}F {master.monsters[f.monsterId].name}と戦闘`
				.. if done
					then `→ {if f.outcome == "win" then "勝利" else "敗北"}（{#f.turns}ターン）`
					else "…"
		else
			text = `{f.floor}F {EVENT_NAME[f.event]}`
			if done and f.event == "trap" then
				text ..= if f.detail.evaded then "→ 回避" else "→ ダメージ"
			elseif done and f.event == "chest" then
				local r = {}
				for _, x in f.detail.ranks do
					table.insert(r, RANK_NAME[x])
				end
				text ..= `→ {table.concat(r, "・")}の宝箱を確保`
			end
		end
		for _, g in f.giftTriggers do
			if done then
				text ..= ` ✨{advName(save, g.uid)}の{master.gifts[g.giftId].name}`
			end
		end
		table.insert(lines, "  " .. text)
	end
	return table.concat(lines, "\n")
end

function Text.events(events: { any }, save: any, master: any): string
	local lines = {}
	for _, e in events do
		local t = "[" .. hms(e.at - START_CLOCK) .. "] "
		if e.type == "ExpeditionReturned" then
			local d = master.dungeons[e.dungeonId]
			table.insert(
				lines,
				t
					.. `パーティ{e.partyIndex}が{d.name}から帰還：{if e.result == "clear"
						then "踏破"
						else "撤退（" .. e.reachedFloor .. "F）"} 宝箱{e.chests}個 {e.gold}G`
			)
		elseif e.type == "LevelUp" then
			table.insert(lines, t .. `{advName(save, e.uid)} が Lv{e.level} に上がった`)
		elseif e.type == "FirstClear" then
			table.insert(lines, t .. `初踏破：{master.dungeons[e.dungeonId].name}`)
		elseif e.type == "DungeonUnlocked" then
			table.insert(lines, t .. `新しいダンジョンが解放された：{master.dungeons[e.dungeonId].name}`)
		elseif e.type == "AutoDispatched" then
			table.insert(
				lines,
				t
					.. `パーティ{e.partyIndex}を{master.dungeons[e.dungeonId].name}へ自動再派遣（帰還 {hms(
						e.returnAt - START_CLOCK
					)}）`
			)
		elseif e.type == "AutoRepeatStopped" then
			table.insert(
				lines,
				t .. `パーティ{e.partyIndex}の自動再派遣を停止：{Text.errorText(e.reason)}`
			)
		elseif e.type == "Dispatched" then
			table.insert(
				lines,
				t
					.. `パーティ{e.partyIndex}が{master.dungeons[e.dungeonId].name}へ出発（帰還 {hms(
						e.returnAt - START_CLOCK
					)}）`
			)
		elseif e.type == "ChestOpened" then
			local r = e.result
			local got = {}
			for _, uid in r.equipmentUids do
				table.insert(got, uid .. " " .. equipName(save.state.equipment[uid], master))
			end
			for id, n in r.items do
				table.insert(got, `{master.items[id].name}×{n}`)
			end
			if r.gold > 0 then
				table.insert(got, `{r.gold}G`)
			end
			table.insert(lines, t .. `{RANK_NAME[r.rank]}の宝箱を開けた：{table.concat(got, "、")}`)
		elseif e.type == "HireStarted" then
			table.insert(lines, t .. `雇用を始めた（雇用費 {e.cost}G）`)
		elseif e.type == "Hired" then
			table.insert(lines, t .. `{advName(save, e.uid)}（{e.uid}）を雇用した`)
		elseif e.type == "HireCanceled" then
			table.insert(lines, t .. "雇用をやめた")
		elseif e.type == "Dismissed" then
			table.insert(lines, t .. `{e.name} を解雇した`)
		elseif e.type == "Reborn" then
			local gift = if e.giftAdded then `、ギフト「{master.gifts[e.giftAdded].name}」を獲得` else ""
			table.insert(
				lines,
				t
					.. `{advName(save, e.uid)} が転生した（{e.rebirthCount}回目・レベル上限 {e.levelCap}）{gift}`
			)
		elseif e.type == "JobChanged" then
			table.insert(
				lines,
				t .. `{advName(save, e.uid)} が{master.jobs[e.from].name}から{master.jobs[e.to].name}に転職した`
			)
		elseif e.type == "AppearanceRolled" then
			table.insert(lines, t .. `新しい見た目：{e.appearanceId}（looks-choose prev|cur で選ぶ）`)
		elseif e.type == "AppearanceChanged" then
			table.insert(lines, t .. `{advName(save, e.uid)} の見た目：{e.appearanceId}`)
		elseif e.type == "GuildLevelUp" then
			local got = {}
			for id, n in e.rewards do
				table.insert(got, `{master.items[id].name}×{n}`)
			end
			table.sort(got)
			table.insert(
				lines,
				t
					.. `ギルドが Lv{e.level} に上がった！ 報酬：{if #got > 0
						then table.concat(got, "、")
						else "なし"}`
			)
		elseif e.type == "Expanded" then
			table.insert(
				lines,
				t .. `{master.expansions[e.expansionId].name}を拡張した（→ {e.value}、{e.gold}G）`
			)
		elseif e.type == "Trained" then
			table.insert(
				lines,
				t .. `{advName(save, e.uid)} がトレーニング{e.sessions}回（{e.gold}G）→ Lv{e.level}`
			)
		elseif e.type == "RebirthStarted" and (e.cost or 0) > 0 then
			table.insert(lines, t .. `転生費用 {e.cost}G を払った`)
		elseif e.type == "UniqueJoined" then
			table.insert(lines, t .. `★ {master.uniques[e.uniqueId].name} が仲間に加わった！`)
		elseif e.type == "Sold" then
			table.insert(lines, t .. `売却して {e.gold}G を得た`)
		end
	end
	return table.concat(lines, "\n")
end

local LOOKS_NAME = { bea = "美形", nor = "普通", ugl = "ブサイク", dem = "亜人" }
local RACE_NAME = {
	elf = "エルフ",
	beastkin = "獣人",
	dwarf = "ドワーフ",
	halforc = "ハーフオーク",
	halfgoblin = "ハーフゴブリン",
}
local STAT_ORDER = { "str", "mag", "agi", "dex", "hp" }

-- D-046：成長の型（基準値の大きい2項目）
local function growthType(jobId: string, master: any): string
	local g = master.jobs[jobId].growth
	local keys = { "str", "mag", "agi", "dex", "hp" }
	table.sort(keys, function(a, b)
		return g[a] > g[b]
	end)
	return `{STAT_NAME[keys[1]]}・{STAT_NAME[keys[2]]}が伸びる`
end

local function statLine(stats: any): string
	local parts = {}
	for _, k in STAT_ORDER do
		if k ~= "hp" then
			table.insert(parts, `{STAT_NAME[k]}{stats[k]}`)
		end
	end
	local total = stats.str + stats.mag + stats.agi + stats.dex
	return `{table.concat(parts, " ")} ／ 合計 {total} ／ HP {stats.hp}`
end

function Text.hiring(save: any, master: any): string
	local h = save.state.hireSession
	if not h then
		return "雇用していません（hire で開始）"
	end
	local lines = { "候補：" }
	for i, c in h.candidates do
		local gifts = {}
		for _, g in c.giftIds do
			table.insert(gifts, master.gifts[g].name)
		end
		local a = master.appearances[c.appearanceId]
		local look = if a then LOOKS_NAME[a.looks] .. (if a.race then "・" .. RACE_NAME[a.race] else "") else "固有"
		local mark = if c.kind == "unique" then "★特別な訪問者 " else ""
		local picked = if h.pickedIndex == i then " ← 面接中" else ""
		table.insert(
			lines,
			`  {i}. {mark}{c.name}（{master.jobs[c.jobId].name}・{look}）ギフト：{table.concat(gifts, "・")} ／ 成長：{growthType(
				c.jobId,
				master
			)}{picked}`
		)
	end
	if h.currentRoll then
		table.insert(lines, "面接の結果：")
		if h.previousRoll then
			table.insert(lines, `  残した結果（prev）：{statLine(h.previousRoll)}`)
		end
		table.insert(lines, `  今回（cur） ：{statLine(h.currentRoll)}`)
		table.insert(
			lines,
			`  無料の引き直し 残り{h.freeRerollsLeft}回 ／ チケット {save.state.items.itm_slot_ticket or 0}枚`
		)
	end
	return table.concat(lines, "\n")
end

function Text.rebirth(save: any, _master: any): string
	local r = save.state.rebirthSession
	if not r then
		return "転生していません"
	end
	local function line(bonus: any): string
		local parts = {}
		for _, k in STAT_ORDER do
			table.insert(parts, `{STAT_NAME[k]}{r.inherited[k] + bonus[k]}(+{bonus[k]}/{r.bonusMax[k]})`)
		end
		local total = bonus.str + bonus.mag + bonus.agi + bonus.dex
		return table.concat(parts, " ") .. ` ／ 加算合計 {total}`
	end
	local lines = {
		`{advName(save, r.adventurerUid)} の転生 ／ 新しい見た目：{r.newAppearanceId}`,
		"表示：転生後の値(＋加算分/加算の上限)",
	}
	if r.previousBonus then
		table.insert(lines, `  残した結果（prev）：{line(r.previousBonus)}`)
	end
	table.insert(lines, `  今回（cur）       ：{line(r.currentBonus)}`)
	table.insert(
		lines,
		`  無料の引き直し 残り{r.freeRerollsLeft}回 ／ チケット {save.state.items.itm_slot_ticket or 0}枚`
	)
	return table.concat(lines, "\n")
end

function Text.expansions(save: any, master: any): string
	local lines = {}
	for _, e in master.raw.Expansions do
		local cur = save.state.expansions[e.kind]
		local nextStep = Game.nextExpansionStep(save.state, e.id, master)
		if nextStep then
			local cond = `ギルドLv{nextStep.guildLevel}`
			if nextStep.requiresClear then
				cond ..= `・{master.dungeons[nextStep.requiresClear].name}を踏破`
			end
			table.insert(lines, `{e.id} {e.name}：{cur} → {nextStep.value}（{cond}、{nextStep.gold}G）`)
		else
			table.insert(lines, `{e.id} {e.name}：{cur}（最大）`)
		end
	end
	return table.concat(lines, "\n")
end

function Text.trainQuote(save: any, uid: string, target: number, master: any): string
	local a = save.state.adventurers[uid]
	if not a then
		return Text.errorText("ADVENTURER_NOT_FOUND")
	end
	local q = Game.query.trainingQuote(save.state, uid, target, master)
	return `{a.name}：Lv{a.level} → Lv{q.toLevel} トレーニング{q.sessions}回 {q.gold}G`
end

-- JSON モード用の要約（AIエージェントが毎回 status を叩かなくてよいように）
function Text.view(save: any, master: any): any
	local s = save.state
	local parties = {}
	for i, p in s.parties do
		local e = Game.query.expeditionOf(s, i)
		table.insert(parties, {
			index = i,
			slots = p.slots,
			autoRepeat = if p.autoRepeat then p.autoRepeat.dungeonId else nil,
			busy = e ~= nil,
			dungeonId = if e then e.dungeonId else nil,
			returnIn = if e then e.returnAt - save.clock else nil,
		})
	end
	local wh = Game.query.warehouse(s)
	local unlocked = {}
	for _, d in master.dungeonList do
		if s.unlockedDungeons[d.id] then
			table.insert(unlocked, d.id)
		end
	end
	return {
		elapsedSeconds = save.clock - START_CLOCK,
		gold = s.gold,
		guildExp = s.guild.exp,
		parties = parties,
		unopenedChests = Game.query.chestsByRank(s, master),
		warehouse = wh,
		unlockedDungeons = unlocked,
	}
end

return Text
