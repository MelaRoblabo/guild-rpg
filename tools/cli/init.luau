--!strict
-- テキスト版（docs/system/09_cli_sim_autoplay.md §1）
-- 1回の実行で1コマンド（または標準入力の複数行）を処理し、状態をファイルに保存する。
--   lune run tools/cli -- [--save out/save.json] [--json] <コマンド> [引数...]
--   lune run tools/cli -- --save out/save.json < script.txt      （1行1コマンド。# はコメント）
-- 時刻は仮想時計（セーブファイルに保存）。wait <秒> で進める。

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")

local Data = require("../../src/data")
local Game = require("../../src/core/Game")
local MasterData = require("../../src/core/MasterData")
local Migration = require("../../src/core/Migration")
local Text = require("./Text")

local master = MasterData.load(Data)

-- 引数 -----------------------------------------------------------------
local savePath = "out/save.json"
local jsonMode = false
local words = {}
do
	local a = process.args
	local i = 1
	while i <= #a do
		local v = a[i]
		if v == "--save" then
			savePath = a[i + 1]
			i += 1
		elseif v == "--json" then
			jsonMode = true
		elseif v ~= "--" then
			table.insert(words, v)
		end
		i += 1
	end
end

-- セーブ ---------------------------------------------------------------
local START_CLOCK = 1767225600 -- 仮想時計の開始（2026-01-01 00:00 UTC）

local save: any
local function newGame(seed: number)
	save = { clock = START_CLOCK, state = Game.newState(master, seed, START_CLOCK) }
end

if fs.isFile(savePath) then
	save = serde.decode("json", fs.readFile(savePath))
	Migration.migrate(save.state)
else
	newGame(1)
end

local function persist()
	local dir = string.match(savePath, "^(.*)/[^/]*$")
	if dir and not fs.isDir(dir) then
		fs.writeDir(dir)
	end
	fs.writeFile(savePath, serde.encode("json", save))
end

local function ctx()
	return { now = save.clock, master = master, online = true }
end

-- 出力 -----------------------------------------------------------------
local out: { string } = {}
local function say(s: string)
	table.insert(out, s)
end

-- コマンド ---------------------------------------------------------------
local function run(cmd: any): any
	local result = Game.execute(save.state, cmd, ctx())
	return result
end

local function parseTokens(line: string): { string }
	local t = {}
	for w in string.gmatch(line, "%S+") do
		table.insert(t, w)
	end
	return t
end

local HELP = [[
コマンド一覧
  new [seed]                 新しいゲームを始める
  status                     全体の状況
  roster                     冒険者一覧
  show <adv_uid>             冒険者の詳細
  warehouse                  倉庫（装備）
  items                      アイテム
  dungeons                   ダンジョン一覧
  hint <dng_id>              攻略ヒント
  party <n> <隊列1-4> <adv_uid|->   パーティに配置／外す
  equip <adv_uid> <eq_uid>   装備する
  unequip <adv_uid> <weapon|armor|sub>  外す
  go <n> <dng_id>            派遣
  repeat <n> <dng_id|off>    自動再派遣の設定
  watch <n>                  探索の様子（現在位置まで）
  wait <秒>                  仮想時計を進める
  open [all|ch_uid...]       宝箱を開ける（省略時 all）
  sell <eq_uid...>           装備を売る
  sell item <itm_id> [個数]   アイテムを売る
  lock <uid> / unlock <uid>  保護の切り替え
  hire                       雇用を始める（雇用費を支払い候補を表示）
  candidates                 候補と面接の状況を表示
  pick <番号>                面接する候補を選ぶ（ステータスを抽選）
  reroll [prev|cur]          ステータスを引き直す（無料回数→チケット）。残す方を指定（省略時は合計の高い方）
  choose <prev|cur>          採用する結果を選んで雇用する
  cancel                     雇用をやめる（雇用費は戻らない）
  rename <adv_uid> <名前>    名前を変える
  dismiss <adv_uid>          解雇する
  rebirth <adv_uid> [keep]   転生を始める（keep：見た目維持ポーションを使う）
  rb-reroll [prev|cur]       転生スロットを引き直す（残す方を指定、省略時は合計の高い方）
  rb-choose <prev|cur>       転生スロットの結果を確定する
  jobchange <adv_uid> <job_id>   転職ポーションで転職する
  looks <adv_uid>            見た目変更ポーションを使う
  looks-choose <prev|cur>    見た目を選ぶ（prev＝今の姿、cur＝新しい姿）
  expansions                 拡張の一覧（次の段階の条件と費用）
  expand <exp_id>            拡張を買う
  autosell <on|off> [最大レアリティ1-5] [keep|all]  自動売却（keep＝修飾語つきは残す）]]

local function handle(tokens: { string }): (boolean, any)
	local c = tokens[1]
	local events = {}
	local function collectAdvance()
		for _, e in Game.advance(save.state, ctx()) do
			table.insert(events, e)
		end
	end

	if c == "new" then
		newGame(tonumber(tokens[2]) or 1)
		say("新しいゲームを始めました。")
		return true, events
	end

	collectAdvance()

	local result: any = nil
	if c == nil or c == "help" then
		say(HELP)
	elseif c == "status" then
		say(Text.status(save, master))
	elseif c == "roster" then
		say(Text.roster(save, master))
	elseif c == "show" then
		say(Text.adventurer(save, tokens[2], master))
	elseif c == "warehouse" then
		say(Text.warehouse(save, master))
	elseif c == "items" then
		say(Text.items(save, master))
	elseif c == "dungeons" then
		say(Text.dungeons(save, master))
	elseif c == "hint" then
		say(Text.hint(tokens[2], master))
	elseif c == "party" then
		local uid = tokens[4]
		result = run({
			type = "SetPartySlot",
			partyIndex = tonumber(tokens[2]),
			slot = tonumber(tokens[3]),
			adventurerUid = if uid == "-" then nil else uid,
		})
	elseif c == "equip" then
		result = run({ type = "Equip", adventurerUid = tokens[2], equipmentUid = tokens[3] })
	elseif c == "unequip" then
		result = run({ type = "Unequip", adventurerUid = tokens[2], slot = tokens[3] })
	elseif c == "go" then
		result = run({ type = "Dispatch", partyIndex = tonumber(tokens[2]), dungeonId = tokens[3] })
	elseif c == "repeat" then
		result = run({
			type = "SetAutoRepeat",
			partyIndex = tonumber(tokens[2]),
			dungeonId = if tokens[3] == "off" then nil else tokens[3],
		})
	elseif c == "watch" then
		say(Text.watch(save, tonumber(tokens[2]) or 1, master))
	elseif c == "wait" then
		local sec = tonumber(tokens[2]) or 0
		save.clock += math.max(0, math.floor(sec))
		collectAdvance()
		say(`{sec} 秒経過しました（{Text.clock(save)}）`)
	elseif c == "open" then
		local uids: any = "all"
		if tokens[2] and tokens[2] ~= "all" then
			uids = table.move(tokens, 2, #tokens, 1, {})
		end
		result = run({ type = "OpenChests", chestUids = uids })
	elseif c == "sell" then
		if tokens[2] == "item" then
			result = run({ type = "Sell", itemId = tokens[3], count = tonumber(tokens[4]) or 1 })
		else
			result = run({ type = "Sell", equipmentUids = table.move(tokens, 2, #tokens, 1, {}) })
		end
	elseif c == "hire" then
		result = run({ type = "HireStart" })
		if result.ok then
			say(Text.hiring(save, master))
		end
	elseif c == "candidates" then
		say(Text.hiring(save, master))
	elseif c == "pick" then
		result = run({ type = "HirePick", candidateIndex = tonumber(tokens[2]) })
		if result.ok then
			say(Text.hiring(save, master))
		end
	elseif c == "reroll" then
		local keep = if tokens[2] == "prev" then "previous" elseif tokens[2] == "cur" then "current" else nil
		result = run({ type = "HireReroll", keep = keep })
		if result.ok then
			say(Text.hiring(save, master))
		end
	elseif c == "choose" then
		local which = if tokens[2] == "prev" then "previous" elseif tokens[2] == "cur" then "current" else tokens[2]
		result = run({ type = "HireChoose", which = which })
	elseif c == "cancel" then
		result = run({ type = "HireCancel" })
	elseif c == "rename" then
		result = run({ type = "Rename", adventurerUid = tokens[2], name = tokens[3] })
	elseif c == "rebirth" then
		result = run({ type = "RebirthStart", adventurerUid = tokens[2], useKeepPotion = tokens[3] == "keep" })
		if result.ok then
			say(Text.rebirth(save, master))
		end
	elseif c == "rb-reroll" then
		local keep = if tokens[2] == "prev" then "previous" elseif tokens[2] == "cur" then "current" else nil
		result = run({ type = "RebirthReroll", keep = keep })
		if result.ok then
			say(Text.rebirth(save, master))
		end
	elseif c == "rb-choose" then
		local which = if tokens[2] == "prev" then "previous" elseif tokens[2] == "cur" then "current" else tokens[2]
		result = run({ type = "RebirthChoose", which = which })
	elseif c == "jobchange" then
		result = run({ type = "ChangeJob", adventurerUid = tokens[2], jobId = tokens[3] })
	elseif c == "looks" then
		result = run({ type = "ChangeAppearance", adventurerUid = tokens[2] })
	elseif c == "looks-choose" then
		local which = if tokens[2] == "prev" then "previous" elseif tokens[2] == "cur" then "current" else tokens[2]
		result = run({ type = "ChangeAppearanceChoose", which = which })
	elseif c == "expansions" then
		say(Text.expansions(save, master))
	elseif c == "expand" then
		result = run({ type = "BuyExpansion", expansionId = tokens[2] })
	elseif c == "autosell" then
		result = run({
			type = "SetAutoSell",
			enabled = tokens[2] == "on",
			maxRarity = tonumber(tokens[3]),
			keepModified = tokens[4] ~= "all",
		})
	elseif c == "dismiss" then
		result = run({ type = "Dismiss", adventurerUid = tokens[2] })
	elseif c == "lock" or c == "unlock" then
		result = run({ type = "SetLock", uid = tokens[2], locked = c == "lock" })
	else
		say(`不明なコマンド: {c}（help で一覧）`)
		return false, events
	end

	if result then
		for _, e in result.events or {} do
			table.insert(events, e)
		end
		if not result.ok then
			say(`✗ {Text.errorText(result.error)}`)
			return false, events
		end
		say("✓ OK")
	end
	return true, events
end

-- 実行 -----------------------------------------------------------------
local lines = {}
if #words > 0 then
	table.insert(lines, table.concat(words, " "))
else
	for line in string.gmatch(stdio.readToEnd(), "[^\r\n]+") do
		local trimmed = string.match(line, "^%s*(.-)%s*$") or ""
		if trimmed ~= "" and string.sub(trimmed, 1, 1) ~= "#" then
			table.insert(lines, trimmed)
		end
	end
end

local anyFailed = false
for _, line in lines do
	out = {}
	local ok, events = handle(parseTokens(line))
	anyFailed = anyFailed or not ok
	if jsonMode then
		print(serde.encode("json", {
			command = line,
			ok = ok,
			events = events,
			messages = out,
			view = Text.view(save, master),
		}))
	else
		if #lines > 1 then
			print(`> {line}`)
		end
		local evText = Text.events(events, save, master)
		if evText ~= "" then
			print(evText)
		end
		print(table.concat(out, "\n"))
	end
	persist()
end

process.exit(if anyFailed then 1 else 0)
