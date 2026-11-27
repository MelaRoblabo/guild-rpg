--!strict
-- テキスト版の表示（文章化のみ。ルールは持たない：D-066）

local Calendar = require("../../src/core/Calendar")
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
	ITEM_HOLDER_ON_EXPEDITION = "その品を装備している冒険者が探索中です",
	SLOT_EMPTY = "その枠には何も装備していません",
	WAREHOUSE_FULL = "倉庫がいっぱいです",
	DUNGEON_NOT_FOUND = "そのダンジョンはありません",
	DUNGEON_LOCKED = "そのダンジョンはまだ解放されていません",
	DUNGEON_ALREADY_UNLOCKED = "そのダンジョンはもう解放されています",
	DUNGEON_PREV_LOCKED = "前のダンジョンがまだ解放されていません",
	PARTY_EMPTY = "パーティに誰もいません",
	NO_CHEST = "開ける宝箱がありません",
	PILE_NOT_FOUND = "その宝箱の山はありません",
	NOTHING_TO_SELL = "今の装備より弱い品はありません",
	ITEM_LOCKED = "保護中の品です",
	ITEM_NOT_SELLABLE = "このアイテムは売れません",
	NOT_ENOUGH_ITEMS = "数が足りません",
	NOT_FOUND = "見つかりません",
	UNKNOWN_COMMAND = "不明なコマンドです",
	SESSION_EXISTS = "雇用・転生・見た目変更のどれかが途中です（candidates／rebirth の結果を確定するか cancel）",
	ROSTER_FULL = "所属枠がいっぱいです",
	NOT_ENOUGH_GOLD = "お金が足りません",
	NO_SESSION = "進行中の雇用・転生・見た目変更がありません",
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
	INBOX_EMPTY = "受け取り箱は空です",
	QUEST_NOT_FOUND = "そのクエストはありません",
	QUEST_NOT_DONE = "そのクエストはまだ達成していません",
	QUEST_ALREADY_CLAIMED = "そのクエストの報酬は受け取り済みです",
	HAUL_EMPTY = "そのパーティが持ち帰った宝箱はありません",
	NO_FRIEND = "同じサーバーに友達がいません（友達を誘いましょう）",
	FRIEND_NOT_READY = "まだ押せません（一定時間ごとに押せます）",
	DAILY_LIMIT = "今日はもう押せません（1日の上限）",
	ALREADY_REWARDED = "その紹介の報酬はもう受け取っています",
	ALREADY_CLAIMED = "その届け物はもう受け取っています",
	WEEKLY_LIMIT = "今週の紹介の報酬は上限です",
	EVENT_NOT_ACTIVE = "そのイベントは今は出ていません（event で確認）",
	EVENT_WINDOW_CLOSED = "そのイベントの受付は締め切られました（出発・購入できるのは出てから3分間）",
	EVENT_ALREADY_JOINED = "そのパーティはこのイベントにもう参加しました（1パーティ1回まで）",
	MERCHANT_NO_PARTY = "商人のところにパーティがいません（パーティを送って、着いてから買えます）",
	MERCHANT_NOT_ARRIVED = "パーティはまだ商人のところに着いていません",
	ALREADY_BOUGHT = "その品はもう買いました",
}

-- 宝箱の山の名前（普通の山はダンジョン名、特別な宝箱は種類の名前：D-166, D-171）
local SPECIAL_PILE_NAME = {
	["special:quest"] = "クエストの宝箱",
	["special:login"] = "ログインボーナスの宝箱",
	["special:playtime"] = "プレイ時間の宝箱",
	["special:raid"] = "レイドの宝箱",
}
local function pileName(pileKey: string, master: any): string
	local d = master.dungeons[pileKey]
	if d then
		return d.name
	end
	local rare = string.match(pileKey, "^special:rare:(.+)$")
	if rare and master.dungeons[rare] then
		return `レアダンジョンの宝箱（{master.dungeons[rare].name}）`
	end
	return SPECIAL_PILE_NAME[pileKey] or pileKey
end

local SOURCE_NAME = {
	quest = "クエスト",
	playtime = "プレイ時間",
	login = "ログインボーナス",
	raid = "レイド",
	referral = "紹介",
}
local QUEST_KIND_NAME = {
	expeditions = "探索に出発する",
	chestsOpened = "宝箱を開ける",
	hires = "冒険者を雇う",
	trainings = "トレーニングする",
	clears = "ダンジョンを踏破する",
	rebirths = "転生する",
}

-- 報酬の中身の文章（ゴールド・アイテム・宝箱の山ごとの数・ユニーク）
local function rewardText(r: any, master: any): string
	local parts = {}
	if r.gold and r.gold > 0 then
		table.insert(parts, `{r.gold}G`)
	end
	local ids = {}
	for id in r.items or {} do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local it = master.items[id]
		table.insert(parts, `{if it then it.name else id}×{r.items[id]}`)
	end
	for _, c in r.chests or {} do
		table.insert(parts, `{pileName(c.pileKey, master)}×{c.count}`)
	end
	if r.uniqueId then
		local u = master.uniques[r.uniqueId]
		table.insert(parts, `★{if u then u.name else r.uniqueId}（仲間）`)
	end
	return if #parts > 0 then table.concat(parts, "、") else "なし"
end

function Text.errorText(code: string?): string
	return ERRORS[code or ""] or tostring(code)
end

local function hms(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d:%02d", sec // 3600, (sec % 3600) // 60, sec % 60)
end

function Text.clock(save: any): string
	-- 日は UTC 0時（日本の朝9時）で区切る（D-168）。仮想時計の開始日を1日目と数える
	local day = Calendar.dayIndex(save.clock) - Calendar.dayIndex(START_CLOCK) + 1
	local out = "経過 " .. hms(save.clock - START_CLOCK) .. `（{day}日目）`
	if save.loggedOut then
		out ..= "［ログアウト中］"
	end
	return out
end

-- 日替わりの特性の説明（D-156）
local function traitText(traitId: string?, master: any): string
	local tr = if traitId then master.dailyTraits[traitId] else nil
	if tr == nil then
		return ""
	end
	if tr.effect == "chestMult" then
		return `宝箱×{tr.value}`
	elseif tr.effect == "expMult" then
		return `経験値×{tr.value}`
	elseif tr.effect == "atkPctPhysical" then
		return `物理攻撃職の攻撃力+{math.floor(tr.value * 100 + 0.5)}%`
	elseif tr.effect == "atkPctMagic" then
		return `魔法攻撃職の攻撃力+{math.floor(tr.value * 100 + 0.5)}%`
	elseif tr.effect == "travelMult" then
		return `移動時間-{math.floor((1 - tr.value) * 100 + 0.5)}%`
	end
	return tr.id
end

-- 今日・明日の日替わりの特性（D-156）
function Text.daily(save: any, master: any): string
	local q = Game.query.dailyTraits(save.clock, master)
	local lines = {}
	for _, pair in { { "今日", q.today }, { "明日", q.tomorrow } } do
		table.insert(lines, `【{pair[1]}の日替わり】`)
		for _, p in pair[2] do
			local band = master.K.dailyTraitBands[p.band]
			table.insert(
				lines,
				`  難度{band.min}〜{band.max}：{master.dungeons[p.dungeonId].name}（{p.dungeonId}） {traitText(
					p.traitId,
					master
				)}`
			)
		end
	end
	table.insert(lines, `次の日の区切りまで {hms(q.nextDayAt - save.clock)}`)
	return table.concat(lines, "\n")
end

-- 受け取り箱（D-164）
function Text.inbox(save: any, master: any): string
	local list = Game.query.inbox(save.state)
	if #list == 0 then
		return "受け取り箱は空です"
	end
	local lines =
		{ `【受け取り箱】{#list}件（claim でまとめて受け取る。受け取れないものは残る）` }
	for _, e in list do
		table.insert(lines, `  {SOURCE_NAME[e.source] or e.source}：{rewardText(e, master)}`)
	end
	return table.concat(lines, "\n")
end

-- 今日・今週のクエスト（D-153）
function Text.quests(save: any, master: any): string
	local q = Game.query.quests(save.state, master)
	local lines = {}
	for _, pair in { { "daily", "今日のクエスト" }, { "weekly", "今週のクエスト" } } do
		local book = q[pair[1]]
		table.insert(
			lines,
			`【{pair[2]}】{if book.bonusDone then "（全部達成のボーナス受け取り済み）" else ""}`
		)
		if #book.entries == 0 then
			table.insert(lines, "  （まだありません）")
		end
		for _, e in book.entries do
			local row = master.quests[e.questId]
			table.insert(
				lines,
				`  {if e.done then "✓" else "・"} {QUEST_KIND_NAME[e.kind] or e.questId} {e.progress}/{e.target}  報酬：{rewardText(
					row.rewards,
					master
				)}`
			)
		end
	end
	return table.concat(lines, "\n")
end

-- ログインボーナスのカレンダー・今日のプレイ時間・休息ボーナス（D-154, D-155, D-161）
function Text.calendar(save: any, master: any): string
	local s = save.state
	local L = Game.query.loginCalendar(s, save.clock, master)
	local lines = { `【ログインボーナス】{L.cycle}周目` }
	for day = 1, 7 do
		local mark = if day < L.day then "済" elseif day == L.day then "次" else "  "
		local reward = if day < 7
			then rewardText(master.loginBonus.days[day], master)
			elseif L.uniqueId then `★{master.uniques[L.uniqueId].name}（仲間）`
			else rewardText(master.loginBonus.fallback, master)
		table.insert(lines, `  {mark} {day}日目：{reward}`)
	end
	if L.receivedToday then
		table.insert(lines, "  今日の分は受け取り済み（次の日の区切りで進む）")
	end
	local P = Game.query.playtime(s, master)
	table.insert(
		lines,
		`【今日のプレイ時間】{hms(P.seconds)} / {hms(P.capSeconds)}{if P.nextMinutes
			then ` ／ 次の報酬は {P.nextMinutes}分`
			else " ／ 今日の報酬はすべて受け取り済み"}`
	)
	return table.concat(lines, "\n")
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

local EVENT_KIND_NAME = { rareDungeon = "レアダンジョン", raid = "レイドボス", merchant = "旅の商人" }

-- 今と次のマップイベント（D-152）
function Text.event(save: any, master: any): string
	local q = Game.query.mapEvent(save.clock, master)
	local c = q.current
	local lines = {
		`【マップイベント】今：{EVENT_KIND_NAME[c.kind]}（{c.placeId}、時間帯 {c.eventSlot}）{if c.open
			then ` 受付中 残り {hms(c.closesIn)}`
			else " 受付終了"}`,
	}
	if c.kind == "rareDungeon" then
		local r = Game.query.rareDungeon(save.state, c.eventSlot, master)
		local joined = if #r.joined > 0 then `（参加済み：パーティ{table.concat(r.joined, "・")}）` else ""
		table.insert(
			lines,
			`  強さ：{master.dungeons[r.dungeonId].name} ／ 宝箱：{pileName(r.pileKey, master)}{joined}（eventgo <n>）`
		)
	elseif c.kind == "raid" then
		local r = Game.query.raid(save.state, c.eventSlot, master)
		table.insert(
			lines,
			`  HP {r.hp} ／ 入ったダメージ {r.damage}{if r.defeated then " 討伐済み" else ""}（出発 {#r.parties}・到着 {r.arrived}）（eventgo <n>）`
		)
		for i = 1, #save.state.parties do
			table.insert(
				lines,
				`  パーティ{i}のダメージの見込み：{Game.query.raidDamage(save.state, i, master)}`
			)
		end
	else
		table.insert(
			lines,
			"  パーティを送って（eventgo <n>）、着いたら品を merchant で表示（buy <番号>・leave <n>）"
		)
	end
	if q.next then
		table.insert(
			lines,
			`【予告】次：{EVENT_KIND_NAME[q.next.kind]}（{q.next.placeId}） あと {hms(q.next.startsIn)}`
		)
	else
		table.insert(lines, `次のイベントまで {hms(q.nextAt - save.clock)}（1分前に予告）`)
	end
	return table.concat(lines, "\n")
end

-- 旅の商人の品（D-152）
function Text.merchant(save: any, master: any): string
	-- パーティが向かっている・とどまっている商人があればそちら（D-274）
	local slot = Game.query.mapEvent(save.clock, master).current.eventSlot
	for _, p in Game.query.merchantPresence(save.state, save.clock, master) do
		if p.phase ~= "open" then
			slot = p.eventSlot
		end
	end
	local m = Game.query.merchant(save.state, slot, save.clock, master)
	if m == nil then
		return "今は旅の商人は出ていません（event で確認）"
	end
	local lines = {
		`【旅の商人】{if m.open
			then "パーティが着いている（買える）"
			elseif m.partyIndex then "パーティが向かっている"
			else "パーティを送ると買える"}（所持金 {save.state.gold}G）`,
	}
	for i, it in m.items do
		table.insert(
			lines,
			`  {i}. {equipName(it, master)} {it.price}G{if it.bought then " ［購入済み］" else ""}`
		)
	end
	return table.concat(lines, "\n")
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
	if e.raidDamage then
		return `レイドボスへ派遣中（ダメージ {e.raidDamage}、帰還まで {remain} 秒）`
	end
	return `{if e.chestPile then "レアダンジョン（" .. d.name .. "）" else d.name}を探索中：{where}（帰還まで {remain} 秒）`
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
	-- D-087, D-166：見せるのは宝箱の山ごとの数だけ（レアリティは開けるまで分からない）
	local piles = Game.query.chestsByPile(s, master)
	local totalChests = 0
	local chestText = {}
	for _, c in piles do
		totalChests += c.count
		table.insert(chestText, `{pileName(c.pileKey, master)}×{c.count}`)
	end
	local wh = Game.query.warehouse(s)
	table.insert(
		lines,
		`未開封の宝箱 {totalChests}個{if #chestText > 0
			then "（" .. table.concat(chestText, "、") .. "）"
			else ""} ／ 倉庫 {wh.used}/{wh.size}`
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
		table.insert(lines, `{d.id} {d.name}（{d.floors}F・難度{d.tier}）{mark}`)
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
				text ..= `→ 宝箱を{#f.detail.ranks}個確保` -- D-087：レアリティは開けるまで見せない
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
						else "撤退（" .. e.reachedFloor .. "F）"} 宝箱{e.chests}個 {e.gold}G{if (
							e.itemsSoldGold or 0
						) > 0
						then `（素材を売却 {e.itemsSoldGold}G）`
						else ""}`
					.. (if e.offline then " ［留守番］" else "")
					.. (if e.interrupted then " ［途中で帰還］" else "")
					.. (if e.dailyTraitId then ` ［日替わり：{traitText(e.dailyTraitId, master)}］` else "")
			)
		elseif e.type == "EventDispatched" then
			if e.kind == "merchant" then
				table.insert(
					lines,
					t
						.. `パーティ{e.partyIndex}が旅の商人へ出発（到着 {hms(e.arriveAt - START_CLOCK)}。着いたら buy・leave {e.partyIndex}）`
				)
			elseif e.kind == "raid" then
				table.insert(
					lines,
					t
						.. `パーティ{e.partyIndex}がレイドボスへ出発（ダメージ {e.damage} ／ HP {e.hp}、到着 {hms(
							e.arriveAt - START_CLOCK
						)}・帰還 {hms(e.returnAt - START_CLOCK)}）`
				)
			else
				table.insert(
					lines,
					t
						.. `パーティ{e.partyIndex}がレアダンジョン（強さ：{master.dungeons[e.dungeonId].name}）へ出発（宝箱は{pileName(
							e.pileKey,
							master
						)}、帰還 {hms(e.returnAt - START_CLOCK)}）`
				)
			end
		elseif e.type == "RaidHit" then
			table.insert(
				lines,
				t
					.. `パーティ{e.partyIndex}がレイドボスに {e.damage} ダメージ（合計 {e.total} / HP {e.hp}）{if e.defeated
						then " 討伐済み"
						else ""}`
			)
		elseif e.type == "RaidDefeated" then
			table.insert(lines, t .. "レイドボスを討伐した！")
		elseif e.type == "RaidReward" then
			table.insert(lines, t .. "レイドの宝箱が受け取り箱に届いた")
		elseif e.type == "RaidReturned" then
			table.insert(lines, t .. `パーティ{e.partyIndex}がレイドから帰還`)
		elseif e.type == "MerchantLeft" then
			table.insert(
				lines,
				t
					.. `パーティ{e.partyIndex}が旅の商人のところを出発（帰還 {hms(
						e.returnAt - START_CLOCK
					)}）`
			)
		elseif e.type == "MerchantReturned" then
			table.insert(lines, t .. `パーティ{e.partyIndex}が旅の商人から帰還`)
		elseif e.type == "MerchantBought" then
			local eq = save.state.equipment[e.equipmentUid]
			table.insert(
				lines,
				t
					.. `旅の商人から買った：{e.equipmentUid} {if eq then equipName(eq, master) else ""}（{e.price}G）`
			)
		elseif e.type == "LevelUp" then
			table.insert(lines, t .. `{advName(save, e.uid)} が Lv{e.level} に上がった`)
		elseif e.type == "FirstClear" then
			table.insert(lines, t .. `初踏破：{master.dungeons[e.dungeonId].name}`)
		elseif e.type == "DungeonUnlocked" then
			table.insert(
				lines,
				t
					.. `新しいダンジョンが解放された：{master.dungeons[e.dungeonId].name}`
					.. (if e.gold then `（{e.gold}G）` else "")
			)
		elseif e.type == "AutoDispatched" then
			table.insert(
				lines,
				t
					.. `パーティ{e.partyIndex}を{master.dungeons[e.dungeonId].name}へ自動再派遣（帰還 {hms(
						e.returnAt - START_CLOCK
					)}）`
					.. (if e.offline then " ［留守番］" else "")
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
		elseif e.type == "ChestsOpened" then
			-- D-089：演出なしをまとめて一覧 → 演出ありを1つずつ（レアリティの低い順、最後が一番派手）
			local function contents(r: any): string
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
				if r.autoSoldGold and r.autoSoldGold > 0 then
					table.insert(got, `（自動売却 {#r.autoSold}個 {r.autoSoldGold}G）`)
				end
				if r.soldItemsGold and r.soldItemsGold > 0 then
					local names = {}
					for id, n in r.soldItems do
						table.insert(names, `{master.items[id].name}×{n}`)
					end
					table.sort(names)
					table.insert(got, `（素材を売却 {table.concat(names, "・")} {r.soldItemsGold}G）`)
				end
				return table.concat(got, "、")
			end
			table.insert(
				lines,
				t
					.. `{pileName(e.pileKey, master)}の宝箱を{e.opened}個開けた（残り{e.remaining}個）`
					.. (
						if e.stoppedBy == "WAREHOUSE_FULL"
							then " ※倉庫がいっぱいで途中で止めました"
							else ""
					)
			)
			if #e.normal > 0 then
				table.insert(lines, `  ── 通常 {#e.normal}個 ──`)
				for _, r in e.normal do
					table.insert(lines, `  {RANK_NAME[r.rank]}：{contents(r)}`)
				end
			end
			for _, r in e.special do
				local stars = string.rep("★", r.rank)
				table.insert(lines, `  {stars} 演出！ {RANK_NAME[r.rank]}の宝箱：{contents(r)}`)
			end
		elseif e.type == "HireStarted" then
			table.insert(lines, t .. `雇用を始めた（雇用費 {e.cost}G）`)
		elseif e.type == "Hired" then
			table.insert(lines, t .. `{advName(save, e.uid)}（{e.uid}）を雇用した`)
		elseif e.type == "HireCandidatesRerolled" then
			table.insert(lines, t .. `求人票を引き直した（{e.cost}G）`)
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
		elseif e.type == "QuestCompleted" then
			local row = master.quests[e.questId]
			table.insert(
				lines,
				t
					.. `クエスト達成：{QUEST_KIND_NAME[row and row.kind or ""] or e.questId}（qclaim で受け取る）`
			)
		elseif e.type == "QuestBonus" then
			table.insert(
				lines,
				t
					.. `{if e.period == "daily" then "今日" else "今週"}のクエストを全部達成！ボーナスは qbonus で受け取る`
			)
		elseif e.type == "QuestClaimed" or e.type == "QuestBonusClaimed" then
			local r = e.rewards or {}
			local n = 0
			for _, c in r.chests or {} do
				n += c.count
			end
			table.insert(lines, t .. `クエストの報酬を受け取った：{r.gold or 0}G・宝箱 {n} 個`)
		elseif e.type == "LoginBonus" then
			table.insert(
				lines,
				t
					.. `ログインボーナス {e.day}日目（{e.cycle}周目）{if e.uniqueId
						then "：★仲間が受け取り箱に届いた"
						else ""}（受け取り箱へ）`
			)
		elseif e.type == "FriendReward" then
			table.insert(
				lines,
				t
					.. `フレンドボタン：友達{e.friendCount}人で {e.gold}G を得た（今日{e.todayCount}回目）`
			)
		elseif e.type == "ReferralGranted" then
			table.insert(lines, t .. `紹介の報酬（受け取り箱へ）`)
		elseif e.type == "PlaytimeReward" then
			table.insert(lines, t .. `プレイ時間 {e.minutes}分の報酬（受け取り箱へ）`)
		elseif e.type == "InboxClaimed" then
			table.insert(
				lines,
				t
					.. `受け取り箱から受け取った：{rewardText(e, master)}{if e.remaining > 0
						then `（{e.remaining}件は残った：{Text.errorText(e.blocked)}）`
						else ""}`
			)
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

-- 今週の訪問者（D-158, D-170）
function Text.visitor(save: any, master: any): string
	local q = Game.query.weeklyVisitor(save.state, save.clock, master)
	if q.uniqueId == nil then
		return "今週の訪問者はいません"
	end
	local u = master.uniques[q.uniqueId]
	local job = master.jobs[u.jobId]
	local gifts = {}
	for _, id in u.giftIds do
		table.insert(gifts, master.gifts[id].name)
	end
	if u.exclusiveGiftId then
		table.insert(gifts, `★{master.gifts[u.exclusiveGiftId].name}`)
	end
	local lines = {
		`【今週の訪問者】{u.name}（{if job then job.name else u.jobId}）ギフト：{table.concat(
			gifts,
			"・"
		)}`,
		if q.owned
			then "  仲間済み（雇用の候補には出ません）"
			else string.format(
				"  出現率：候補1人ごとに %.1f%%（候補 %d 人ぶん判定）",
				q.chance * 100,
				q.candidateSlots
			),
		`  次の週の区切りまで {hms(q.nextWeekAt - save.clock)}`,
	}
	return table.concat(lines, "\n")
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
		`{advName(save, r.adventurerUid)} の転生（見た目は確定の後に選ぶ：D-230）`,
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
		unopenedChests = Game.query.chestsByPile(s, master),
		inboxCount = #Game.query.inbox(s), -- 受け取り箱の件数（D-164）
		warehouse = wh,
		unlockedDungeons = unlocked,
	}
end

return Text
