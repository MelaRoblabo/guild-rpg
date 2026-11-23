--!strict
-- ゲーム外の通知のためにセーブに持つもの（D-196、docs/system/06_formulas.md §23、11章 §8）
--   Notify.recordLogin     ログインした時刻（1日の中の位置・秒）を直近 notifyLoginHistoryCount 回まで記録する。
--                          サーバーがログイン（読み込み）のたびに1回呼ぶ
--   Notify.usualTimeOfDay  「いつも遊ぶ時刻」＝記録したログイン時刻の中央値（1日の中の位置・秒）。記録がなければ nil
--   Notify.promptDue       通知の許可を求める画面を今出すか：初めての帰還（firstReturn）、
--                          そこで出したあとのログインボーナス2日目（loginDay2）。出さなければ nil
--   Notify.markPrompted    許可の画面を出した記録を付ける（設定と一緒にサーバーへ保存する：D-117）
-- 日の区切りは Calendar（UTC 0時：D-168）。時刻は引数で受け取る。状態を持たない（関数の集合）。

local Calendar = require("./Calendar")

local Notify = {}

-- 許可の画面を出す機会（D-196 ③）
Notify.STAGES = { "firstReturn", "loginDay2" }

-- settings.notifyPrompt の初期値：どの機会でもまだ出していない
function Notify.newPromptState(): any
	return { firstReturn = false, loginDay2 = false }
end

-- ログインした時刻を記録する（古いものから並べ、notifyLoginHistoryCount 回を超えたら一番古いものを捨てる）
function Notify.recordLogin(state: any, now: number, master: any)
	local list = state.loginTimes
	if type(list) ~= "table" then
		list = {}
		state.loginTimes = list
	end
	table.insert(list, now - Calendar.dayStart(now))
	local max = master.K.notifyLoginHistoryCount
	while #list > max do
		table.remove(list, 1)
	end
end

-- 「いつも遊ぶ時刻」：記録したログイン時刻（1日の中の位置）の中央値。
-- 数が偶数のときは、小さい順に並べた真ん中の2つのうち小さいほう（平均はとらない）
function Notify.usualTimeOfDay(state: any): number?
	local list = state.loginTimes
	if type(list) ~= "table" or #list == 0 then
		return nil
	end
	local sorted = table.clone(list)
	table.sort(sorted)
	return sorted[math.floor((#sorted + 1) / 2)]
end

-- ログインボーナスの2日目を受け取ったか（login.day は次に受け取る位置。2周目以降も受け取り済み）
local function loginDay2Received(state: any): boolean
	local L = state.login
	return L ~= nil and (L.cycle > 1 or L.day > 2)
end

local function promptState(state: any): any
	local p = state.settings and state.settings.notifyPrompt
	return p or Notify.newPromptState()
end

-- 許可の画面を今出すか（D-196 ③）。
--   firstReturn：初めての帰還（stats.firstReturnAt がある）のあと、まだ出していない
--   loginDay2  ：firstReturn で出したあと、ログインボーナスの2日目を受け取っていて、まだ出していない。
--                許可したかどうかはサーバーからは分からないので、出せるか（許可済みでないか）はクライアントが Roblox に確かめる
function Notify.promptDue(state: any): string?
	local p = promptState(state)
	if not p.firstReturn then
		if state.stats and state.stats.firstReturnAt ~= nil then
			return "firstReturn"
		end
		return nil
	end
	if not p.loginDay2 and loginDay2Received(state) then
		return "loginDay2"
	end
	return nil
end

-- 許可の画面を出した記録を付ける。今出す機会でなければエラーコード。
-- firstReturn を付けたときにログインボーナスの2日目をもう受け取っていたら、loginDay2 も付ける
-- （2日目は初めての帰還より後の機会。同じ日に続けて2回出さない）
function Notify.markPrompted(state: any, stage: string): string?
	if not table.find(Notify.STAGES, stage) then
		return "INVALID_STAGE"
	end
	if Notify.promptDue(state) ~= stage then
		return "NOT_DUE"
	end
	state.settings.notifyPrompt = state.settings.notifyPrompt or Notify.newPromptState()
	local p = state.settings.notifyPrompt
	p[stage] = true
	if stage == "firstReturn" and loginDay2Received(state) then
		p.loginDay2 = true
	end
	return nil
end

return Notify
