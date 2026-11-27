--!strict
-- サーバーとクライアントの間の約束事（11章 §4、D-101・D-103・D-087）
--   Protocol.validateCommand  クライアントから届いたコマンドの「形」の検証（中身の正しさは Game.execute）
--   Protocol.view             クライアントに送る状態の要約（乱数の元・宝箱のランクを隠す）
--   Protocol.redactEvents     events から宝箱のランクを除く（開封結果は除かない）
--   Protocol.diff / applyPatch  要約の差分（D-103）
-- Roblox API は使わない（サーバーとクライアントの両方、Lune のテストで使う）。

local Game = require("./Game")
local ListPrefs = require("./ListPrefs")
local Preferences = require("./Preferences")

local Protocol = {}

-- 値の種類 ------------------------------------------------------------------

type Field = { kind: string, optional: boolean?, min: number?, max: number?, maxLen: number?, values: { string }? }

local function int(min: number, max: number, optional: boolean?): Field
	return { kind = "int", min = min, max = max, optional = optional }
end
local function str(maxLen: number, optional: boolean?): Field
	return { kind = "str", maxLen = maxLen, optional = optional }
end
local function bool(optional: boolean?): Field
	return { kind = "bool", optional = optional }
end
local function enum(values: { string }, optional: boolean?): Field
	return { kind = "enum", values = values, optional = optional }
end
local function strList(maxCount: number, maxLen: number, optional: boolean?): Field
	return { kind = "strList", max = maxCount, maxLen = maxLen, optional = optional }
end

local ID = 64 -- uid・マスターID の長さの上限
local WHICH = enum({ "previous", "current" })

-- クライアントから受け付けるコマンドと引数（05章 M2〜M5b、M7b）。GrantPurchase・GrantReferral（サーバー専用）は含めない
Protocol.CLIENT_COMMANDS = {
	SetPartySlot = { partyIndex = int(1, 20), slot = int(1, 4), adventurerUid = str(ID, true) },
	SetPartyLeader = { partyIndex = int(1, 20), adventurerUid = str(ID) }, -- D-271
	Equip = { adventurerUid = str(ID), equipmentUid = str(ID) },
	Unequip = { adventurerUid = str(ID), slot = enum({ "weapon", "armor", "sub" }) },
	Dispatch = { partyIndex = int(1, 20), dungeonId = str(ID) },
	SetAutoRepeat = { partyIndex = int(1, 20), dungeonId = str(ID, true) },
	OpenChests = { pileKey = str(ID), count = int(1, 1000, true) }, -- 宝箱の山の鍵（D-166）
	Sell = { equipmentUids = strList(1000, ID, true), itemId = str(ID, true), count = int(1, 1000000, true) },
	BulkSell = { equipmentUids = strList(1000, ID) }, -- D-167
	SetLock = { uid = str(ID), locked = bool() },
	HireStart = {},
	HirePick = { candidateIndex = int(1, 20) },
	HireReroll = {},
	HireChoose = { which = WHICH },
	HireCancel = {},
	Rename = { adventurerUid = str(ID), name = str(64) },
	Dismiss = { adventurerUid = str(ID) },
	RebirthStart = { adventurerUid = str(ID) }, -- 見た目は確定の後に選ぶ（D-230）
	RebirthReroll = {},
	RebirthChoose = { which = WHICH },
	RebirthAppearanceChoose = { which = WHICH }, -- D-230
	ChangeJob = { adventurerUid = str(ID), jobId = str(ID) },
	ChangeAppearance = { adventurerUid = str(ID) },
	ChangeAppearanceChoose = { which = WHICH },
	BuyExpansion = { expansionId = str(ID) },
	UnlockDungeon = { dungeonId = str(ID) }, -- D-279。ゴールドでダンジョンを先に解放する
	SetAutoSell = { enabled = bool(), maxRarity = int(1, 100, true), keepModified = bool(true) },
	AutoEquip = { partyIndex = int(1, 20), adventurerUid = str(ID, true) }, -- D-120・D-231 ⑨・D-235 ③・D-266
	-- 設定（D-117・D-237 ③）。送った項目だけ変わる
	SetSettings = (function()
		local f: { [string]: Field } = {}
		for _, k in Preferences.VOLUMES do
			f[k] = int(0, 100, true)
		end
		for _, k in Preferences.SWITCHES do
			f[k] = bool(true)
		end
		return f
	end)(),
	-- 一覧の並べ方と一括売却の上限（D-117・D-119・D-231 ⑮）。送った項目だけ変わる
	SetListPrefs = {
		advSort = enum(ListPrefs.ADV_SORTS, true),
		advDesc = bool(true),
		whSort = enum(ListPrefs.WH_SORTS, true),
		whDesc = bool(true),
		bulkSellMaxRarity = int(1, 100, true),
	},
	Train = { adventurerUid = str(ID), sessions = int(1, 100000) },
	ClaimInbox = {}, -- D-164
	ClaimQuest = { period = enum({ "daily", "weekly" }), questId = str(ID) }, -- D-286。クエストの報酬をその場で受け取る
	ClaimQuestBonus = { period = enum({ "daily", "weekly" }) }, -- D-286
	AckHaul = { partyIndex = int(1, 20) }, -- D-287。帰還の獲得の吹き出しを押した
	ClaimFriendReward = {}, -- D-157。友達の数はサーバーが数えて ctx.friendCount で渡す（クライアントからは受け取らない）
	DispatchEvent = { partyIndex = int(1, 20), eventSlot = int(0, 2 ^ 40) }, -- D-152
	BuyFromMerchant = { eventSlot = int(0, 2 ^ 40), itemIndex = int(1, 20) }, -- D-152, D-179
	LeaveMerchant = { partyIndex = int(1, 20) }, -- D-274。商人のところから帰る
	MarkNotifyPrompt = { stage = enum({ "firstReturn", "loginDay2" }) }, -- D-196。通知の許可の画面を出した記録
	SetGuideStep = { step = int(1, 99) }, -- D-244 ①。初回の誘導の済んだ段の数
} :: { [string]: { [string]: Field } }

-- 読み取り専用のコマンド（状態を変えない。Game.execute を通さず、サーバーが答える。回数制限の対象：11章（システム）§6.2）
Protocol.READ_COMMANDS = {
	-- D-108・D-121。他のプレイヤーの馬車の詳細。Studio のテストのプレイヤーは番号がマイナス（Player1＝-1）なので負も受け付ける
	Inspect = { userId = int(-(2 ^ 53), 2 ^ 53), partyIndex = int(1, 20) },
} :: { [string]: { [string]: Field } }

-- サーバーだけが受け付けるコマンド（Game にはあるがクライアントからは受け付けない）
Protocol.SERVER_ONLY = { GrantPurchase = true, GrantReferral = true }

local function checkField(name: string, f: Field, v: any): string?
	if v == nil then
		return if f.optional then nil else `{name} がない`
	end
	if f.kind == "int" then
		if type(v) ~= "number" or v ~= v or v ~= math.floor(v) then
			return `{name} は整数`
		end
		if v < (f.min :: number) or v > (f.max :: number) then
			return `{name} が範囲外`
		end
	elseif f.kind == "str" then
		if type(v) ~= "string" or #v == 0 or #v > (f.maxLen :: number) then
			return `{name} は1〜{f.maxLen}バイトの文字列`
		end
	elseif f.kind == "bool" then
		if type(v) ~= "boolean" then
			return `{name} は真偽値`
		end
	elseif f.kind == "enum" then
		if type(v) ~= "string" or not table.find(f.values :: { string }, v) then
			return `{name} の値が不正`
		end
	elseif f.kind == "strList" then
		if type(v) ~= "table" then
			return `{name} は文字列の配列`
		end
		local n = 0
		for k, x in v do
			n += 1
			if type(k) ~= "number" or type(x) ~= "string" or #x == 0 or #x > (f.maxLen :: number) then
				return `{name} は文字列の配列`
			end
		end
		if n ~= #v or n > (f.max :: number) then
			return `{name} の要素数が不正`
		end
	end
	return nil
end

-- 形の検証。ok なら true、だめなら false とエラー文（エラーコードはサーバーが BAD_REQUEST にする）
function Protocol.validateCommand(command: any): (boolean, string?)
	if type(command) ~= "table" or type(command.type) ~= "string" then
		return false, "コマンドの形が不正"
	end
	local schema = Protocol.CLIENT_COMMANDS[command.type] or Protocol.READ_COMMANDS[command.type]
	if schema == nil then
		return false, `受け付けないコマンド: {command.type}`
	end
	for k in command do
		if k ~= "type" and (type(k) ~= "string" or schema[k] == nil) then
			return false, `知らない引数: {tostring(k)}`
		end
	end
	for name, f in schema do
		local err = checkField(name, f, command[name])
		if err then
			return false, err
		end
	end
	return true, nil
end

-- 表の道具 ------------------------------------------------------------------

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end
Protocol.deepCopy = deepCopy

-- 1から連番のキーだけを持つ空でない表を配列とみなす（空の表は辞書として扱う：11章 §4.3）
local function isArray(t: any): boolean
	local n = #t
	if n == 0 then
		return false
	end
	local count = 0
	for k in t do
		if type(k) ~= "number" then
			return false
		end
		count += 1
	end
	return count == n
end
Protocol.isArray = isArray

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, x in a do
		if not deepEqual(x, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end
Protocol.deepEqual = deepEqual

-- 隠す情報（11章 §4.5、D-087） -----------------------------------------------

-- lastAdvancedAt は時間経過のたびに変わるだけで表示に使わないので送らない（差分が毎秒出るのを防ぐ）
-- loginTimes（直近のログイン時刻：D-196）はサーバーが通知の時刻を決めるのに使うだけなので送らない
local HIDDEN_STATE_KEYS =
	{ seed = true, rngCounter = true, nextUid = true, stats = true, lastAdvancedAt = true, loginTimes = true }

-- 探索ログから宝箱のランクを除き、個数だけ残す
function Protocol.redactLog(log: any): any
	local out = deepCopy(log)
	for _, f in out.floors or {} do
		if type(f.detail) == "table" and f.detail.ranks ~= nil then
			f.detail.chestCount = #f.detail.ranks
			f.detail.ranks = nil
		end
	end
	if out.rewards and out.rewards.chests ~= nil then
		out.rewards.chestCount = #out.rewards.chests
		out.rewards.chests = nil
	end
	if out.clearChestRanks ~= nil then
		out.clearChestCount = #out.clearChestRanks
		out.clearChestRanks = nil
	end
	return out
end

local RANK_KEYS = { rank = true, ranks = true, clearChestRanks = true }

local function stripRanks(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		if not RANK_KEYS[k] then
			out[k] = stripRanks(x)
		end
	end
	return out
end

-- events から宝箱のランクを除く。開封結果（ChestsOpened）は開けた後なのでそのまま（演出に使う）
-- 紹介の結果（ReferralGranted）からは相手の UserId を除く（D-192）
function Protocol.redactEvents(events: { any }): { any }
	local out = {}
	for _, e in events do
		local x = if e.type == "ChestsOpened" then deepCopy(e) else stripRanks(e)
		if e.type == "ReferralGranted" then
			x.userId = nil
		end
		table.insert(out, x)
	end
	return out
end

-- 紹介の状態のうちクライアントに送らないもの：他のプレイヤーの UserId を含む（D-192）
--   rewardedInvitees（報酬済みの相手の UserId）・claimedDeliveries（届け物の id。UserId を含む）・referredBy（招待した人）
local HIDDEN_REFERRAL_KEYS = { rewardedInvitees = true, claimedDeliveries = true, referredBy = true }

-- クライアントに送る状態の要約
function Protocol.view(state: any, master: any): any
	local v = {}
	for k, x in state do
		if not HIDDEN_STATE_KEYS[k] then
			v[k] = deepCopy(x)
		end
	end
	if type(v.referral) == "table" then
		for k in HIDDEN_REFERRAL_KEYS do
			v.referral[k] = nil
		end
	end
	-- 未開封の宝箱：特別な宝箱を含む全部の山の { { pileKey, count } } の配列。ランクは隠す（D-087, D-166）
	v.chests = Game.query.chestsByPile(state, master)
	-- 受け取り箱の宝箱はランクを隠し、山ごとの数だけにする（D-087, D-164）
	v.inbox = Game.query.inbox(state)
	-- 通知の許可の画面を今出すか（D-196。"firstReturn" / "loginDay2" / nil）。初めての帰還は stats にあり送らないので、ここで判定して渡す
	v.notifyPromptDue = Game.query.notifyPromptDue(state)
	-- 初回の誘導の済んだ段の数（D-244 ①）。誘導の前からのセーブかは stats（送らない）で判定するので、ここで渡す
	v.guideStep = Game.query.guideStep(state)
	for _, e in v.expeditions or {} do
		e.seed = nil
		e.log = Protocol.redactLog(e.log)
	end
	return v
end

-- 差分（D-103、11章 §4.3） ----------------------------------------------------

local function append(path: { any }, k: any): { any }
	local p = table.clone(path)
	table.insert(p, k)
	return p
end

-- a を b にする操作の列。辞書は要素ごと、配列は変わったら丸ごと置き換える
function Protocol.diff(a: any, b: any): { any }
	local patch = {}
	local function walk(path: { any }, x: any, y: any)
		for k, yv in y do
			local xv = x[k]
			local p = append(path, k)
			local bothDicts = type(xv) == "table" and type(yv) == "table" and not isArray(xv) and not isArray(yv)
			if bothDicts then
				walk(p, xv, yv)
			elseif not deepEqual(xv, yv) then -- 追加（xv == nil）も含む
				table.insert(patch, { path = p, value = deepCopy(yv) })
			end
		end
		for k in x do
			if y[k] == nil then
				table.insert(patch, { path = append(path, k), delete = true })
			end
		end
	end
	walk({}, a, b)
	return patch
end

-- 差分を target に当てる（target を書き換えて返す）
function Protocol.applyPatch(target: any, patch: { any }): any
	for _, op in patch do
		local path = op.path
		assert(type(path) == "table" and #path >= 1, "差分の path が不正")
		local t = target
		for i = 1, #path - 1 do
			local nxt = t[path[i]]
			if type(nxt) ~= "table" then
				nxt = {}
				t[path[i]] = nxt
			end
			t = nxt
		end
		local last = path[#path]
		if op.delete then
			t[last] = nil
		else
			t[last] = deepCopy(op.value)
		end
	end
	return target
end

return Protocol
