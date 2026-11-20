--!strict
-- テキスト版の表示（文章化のみ。ルールは持たない：D-066）

local Game = require("../../src/core/Game")

local Text = {}

local START_CLOCK = 1767225600
local RANK_NAME = { "コモン", "アンコモン", "レア", "エピック", "レジェンド" }
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
		`【{Text.clock(save)}】 所持金 {s.gold}G ／ ギルド経験値 {s.guild.exp}`,
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
	local byRank = { 0, 0, 0, 0, 0 }
	for _, c in s.chests do
		byRank[c.rank] += 1
	end
	local chestText = {}
	for r = 1, 5 do
		if byRank[r] > 0 then
			table.insert(chestText, `{RANK_NAME[r]}×{byRank[r]}`)
		end
	end
	local wh = Game.query.warehouse(s)
	table.insert(
		lines,
		`未開封の宝箱 {#s.chests}個{if #chestText > 0
			then "（" .. table.concat(chestText, "、") .. "）"
			else ""} ／ 倉庫 {wh.used}/{wh.size}`
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
		table.insert(lines, `{d.id} {d.name}（{d.floors}F・難度{d.tier}）{mark}`)
	end
	return table.concat(lines, "\n")
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
		`罠レベル {d.trapLevel} ／ 最低宝箱ランク {RANK_NAME[d.minChestRank]}`,
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
		elseif e.type == "Sold" then
			table.insert(lines, t .. `売却して {e.gold}G を得た`)
		end
	end
	return table.concat(lines, "\n")
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
		unopenedChests = #s.chests,
		warehouse = wh,
		unlockedDungeons = unlocked,
	}
end

return Text
