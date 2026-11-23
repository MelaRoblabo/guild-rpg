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

local Data = require("../src/data")
local Game = require("../src/core/Game")
local MasterData = require("../src/core/MasterData")
local Migration = require("../src/core/Migration")
local CommandText = require("../src/core/CommandText")
local Text = require("@self/Text")

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
	Migration.migrate(save.state, master)
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

local function ctx(online: boolean?)
	return { now = save.clock, master = master, online = if online == nil then true else online }
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

-- 表示用のコマンド（状態を変えるコマンドの書式は CommandText.HELP と共通）
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
  watch <n>                  探索の様子（現在位置まで）
  wait <秒>                  仮想時計を進める
  days <日数>                仮想時計を日単位で進める（D-168）
  logout / login             ログアウト（最後に保存した時刻を書く）／ログイン（留守番と休息ボーナスを計算：D-161）
  daily                      今日・明日の日替わりの特性（D-156）
  inbox                      受け取り箱の中身（D-164。受け取りは claim）
  quests                     今日・今週のクエストと進み具合（D-153）
  calendar                   ログインボーナスのカレンダー・今日のプレイ時間・休息ボーナス（D-154, D-155）
  event                      今のマップイベントと予告（D-152。参加は eventgo）
  merchant                   旅の商人の品（D-152。買うのは buy）
  candidates                 候補と面接の状況を表示
  expansions                 拡張の一覧（次の段階の条件と費用）
  trainquote <adv_uid> <Lv>  そのレベルまでのトレーニング費用の見積もり
状態を変えるコマンド
]] .. CommandText.HELP

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

	-- ログアウト中（D-161）：時計を進めるだけ。進めた時間は login のときに留守番として計算する
	if save.loggedOut then
		if c == "wait" or c == "days" then
			local sec = if c == "days"
				then math.floor((tonumber(tokens[2]) or 0) * 86400)
				else math.floor(tonumber(tokens[2]) or 0)
			save.clock += math.max(0, sec)
			say(`ログアウト中に {sec} 秒経過しました（{Text.clock(save)}）`)
			return true, events
		elseif c == "login" then
			save.loggedOut = nil
			for _, e in Game.advance(save.state, ctx(false)) do
				table.insert(events, e)
			end
			say(
				`ログインしました（{Text.clock(save)}）。休息ボーナス 残り {Game.query.restBonus(
					save.state
				)} 秒`
			)
			return true, events
		elseif not (c == "status" or c == "daily" or c == "event" or c == "help" or c == nil) then
			-- 表示（status・daily・event・help）だけは許す。留守中はイベントに参加できない（D-161）
			say("ログアウト中です（login でログイン）")
			return false, events
		end
	else
		collectAdvance()
	end

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
	elseif c == "watch" then
		say(Text.watch(save, tonumber(tokens[2]) or 1, master))
	elseif c == "wait" then
		local sec = tonumber(tokens[2]) or 0
		save.clock += math.max(0, math.floor(sec))
		collectAdvance()
		say(`{sec} 秒経過しました（{Text.clock(save)}）`)
	elseif c == "days" then
		-- ツール用の時間の操作（05章 §3b）。ログイン中はオンラインのまま進める
		local n = tonumber(tokens[2]) or 0
		save.clock += math.max(0, math.floor(n * 86400))
		collectAdvance()
		say(`{n} 日経過しました（{Text.clock(save)}）`)
	elseif c == "logout" then
		-- 最後に保存した時刻を書く（本番はサーバーが保存のときに書く：03章、M7b-5）
		save.state.lastSavedAt = save.clock
		save.loggedOut = true
		say(`ログアウトしました（{Text.clock(save)}）`)
	elseif c == "login" then
		say("すでにログインしています")
	elseif c == "daily" then
		say(Text.daily(save, master))
	elseif c == "inbox" then
		say(Text.inbox(save, master))
	elseif c == "quests" then
		say(Text.quests(save, master))
	elseif c == "calendar" then
		say(Text.calendar(save, master))
	elseif c == "event" then
		say(Text.event(save, master))
	elseif c == "merchant" then
		say(Text.merchant(save, master))
	elseif c == "candidates" then
		say(Text.hiring(save, master))
	elseif c == "expansions" then
		say(Text.expansions(save, master))
	elseif c == "trainquote" then
		say(Text.trainQuote(save, tokens[2], tonumber(tokens[3]) or 1, master))
	else
		-- 状態を変えるコマンド（書式の解析は CommandText と共通：11章 §5）
		local cmd = CommandText.fromTokens(tokens)
		if cmd == nil then
			say(`不明なコマンド: {c}（help で一覧）`)
			return false, events
		end
		if (cmd.type == "DispatchEvent" or cmd.type == "BuyFromMerchant") and cmd.eventSlot == nil then
			-- 時間帯を省いたら今の時間帯（D-152）
			cmd.eventSlot = Game.query.mapEvent(save.clock, master).current.eventSlot
		end
		if cmd.type == "BulkSell" and #cmd.equipmentUids == 0 then
			-- sellweak の対象を省いたら直前の開封結果（09章、D-167）
			cmd.equipmentUids = save.lastOpenedEquipment or {}
		end
		result = run(cmd)
		if result.ok and cmd.type == "OpenChests" then
			-- 開封結果に残った装備を覚えておく（sellweak 用。ゲームの状態ではなくテキスト版のセーブに置く）
			local uids = {}
			for _, ev in result.events or {} do
				if ev.type == "ChestsOpened" then
					for _, list in { ev.normal, ev.special } do
						for _, r in list do
							for _, uid in r.equipmentUids do
								table.insert(uids, uid)
							end
						end
					end
				end
			end
			save.lastOpenedEquipment = uids
		end
		if result.ok then
			if c == "repeat" and tokens[3] ~= "off" then
				say(
					"※自動再派遣は次の帰還から働きます。待機中なら go で出発してください"
				)
			elseif c == "hire" or c == "pick" or c == "reroll" then
				say(Text.hiring(save, master))
			elseif c == "rebirth" or c == "rb-reroll" then
				say(Text.rebirth(save, master))
			end
		end
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
	local ok, events = handle(CommandText.tokens(line))
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
