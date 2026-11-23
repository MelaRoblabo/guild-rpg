--!strict
-- ゲーム外の通知（Roblox のエクスペリエンス通知。D-159・D-181、11章 §8）
--
-- 流れ：
--   1. 退出したとき（schedule）：送る時刻（その人がいつも遊ぶ時刻）と、その時刻に一番効く1つ（NotificationPicker）を選び、
--      MemoryStore の SortedMap に予約する（鍵 = UserId、並びの鍵 = 送る時刻）。1人1つ。退出のたびに置き換える。
--   2. 参加したとき（cancel）：予約を消す（遊んでいる人には送らない）。
--   3. どのサーバーも notifyPollSeconds ごとに、送る時刻が来た予約を取り出して送る（poll）。
--      送る前に、MemoryStore の HashMap で「最後に送った日」を UpdateAsync で書き換えられた1台だけが送る
--      （1人1日1通。日の区切りは Calendar = UTC 0時：D-168。サーバーが2台同時に取り出しても1通だけ）。
--   4. 13歳以上で通知を許可した人にだけ届く。これは Roblox 側が判定する（サーバーからは許可・年齢を確かめる API がない）。
-- 送る口は Open Cloud の CreateUserNotification（POST apis.roblox.com/cloud/v2/users/{userId}/notifications）。
-- ゲームのサーバーから HttpService で呼べる（In-game HTTP requests の「Supported Open Cloud endpoints」で確認、2026-11）。
-- 許可の画面（PromptOptIn）はクライアント専用の API なので、クライアントの NotificationPrompt から出す（D-181）。

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")

local Calendar = require("@game/ReplicatedStorage/Core/Calendar")
local Config = require("./Config")
local NotificationPicker = require("./NotificationPicker")

local Notifications = {}
Notifications.__index = Notifications

local MAX_EXPIRATION = 3888000 -- MemoryStore の寿命の上限（45日。Roblox の制限）
local SENT_EXPIRATION = 2 * 86400 -- 「最後に送った日」は翌日まで覚えていればよい

type Reservation = { userId: number, kind: string, count: number?, sendAt: number }

-- 文面の id を登録した種類（空の種類は送らない）
local function enabledKinds(): ({ [string]: boolean }, boolean)
	local out = {}
	local any = false
	for kind, id in Config.notifyMessageIds do
		if type(id) == "string" and id ~= "" then
			out[kind] = true
			any = true
		end
	end
	return out, any
end

function Notifications.new(master: any)
	local self = setmetatable({}, Notifications)
	self.master = master
	self.queue = MemoryStoreService:GetSortedMap(Config.notifyQueueName)
	self.sent = MemoryStoreService:GetHashMap(Config.notifySentMapName)
	self.warnedSecret = false
	return self
end

-- 退出したとき：予約する。session は退出したセッション（state は読むだけ）。待ちが入るので task.spawn から呼ぶ
function Notifications.schedule(self: any, session: any)
	if not Config.notifyEnabled then
		return
	end
	local enabled, any = enabledKinds()
	if not any then
		return
	end
	local now = os.time()
	-- いつも遊ぶ時刻＝直近のログイン時刻の中央値（D-196。ログインのたびに PlayerSessions が記録する）
	local timeOfDay = NotificationPicker.usualTimeOfDay(session.state, session.loadedAt)
	local sendAt = NotificationPicker.sendAt(timeOfDay, now, Config.notifyMinAwaySeconds)
	local okPick, pickOrErr = pcall(NotificationPicker.pick, session.state, self.master, now, sendAt, enabled)
	if not okPick then
		warn(`[Notifications] 通知の候補を選べなかった（{session.userId}）：{pickOrErr}`)
		return
	end
	if pickOrErr == nil then
		return
	end
	local value: Reservation =
		{ userId = session.userId, kind = pickOrErr.kind, count = pickOrErr.count, sendAt = sendAt }
	local expiration = math.min(sendAt - now + Config.notifyQueueExpirationSeconds, MAX_EXPIRATION)
	local ok, err = pcall(function()
		self.queue:SetAsync(tostring(session.userId), value, expiration, sendAt)
	end)
	if not ok then
		warn(`[Notifications] 通知を予約できなかった（{session.userId}）：{err}`)
	end
end

-- 参加したとき：予約を消す。待ちが入るので task.spawn から呼ぶ
function Notifications.cancel(self: any, userId: number)
	if not Config.notifyEnabled then
		return
	end
	local ok, err = pcall(function()
		self.queue:RemoveAsync(tostring(userId))
	end)
	if not ok then
		warn(`[Notifications] 通知の予約を消せなかった（{userId}）：{err}`)
	end
end

-- 今日まだ送っていなければ「今日送った」と書き、書けたら true（1人1日1通）
local function claimToday(self: any, userId: number, today: number): boolean
	local ok, result = pcall(function()
		return self.sent:UpdateAsync(tostring(userId), function(old: any)
			if old == today then
				return nil -- 今日はもう送った（書かない）
			end
			return today
		end, SENT_EXPIRATION)
	end)
	if not ok then
		warn(`[Notifications] 送った日を書けなかった（{userId}）：{result}`)
		return false
	end
	return result == today
end

-- Open Cloud で通知を1通送る。Roblox の送信の呼び出しはここだけ。
-- 要確認：API キーに要る権限の名前（ドキュメントに書かれていない）、エラーの状態コードの一覧（429 は1日の上限・送りすぎ）。
local function sendOne(self: any, r: Reservation): boolean
	local messageId = Config.notifyMessageIds[r.kind]
	if type(messageId) ~= "string" or messageId == "" then
		return false
	end
	if game.GameId == 0 then
		return false -- 公開していないプレイス（Studio の未公開）では送れない
	end
	local okSecret, secret = pcall(function()
		return HttpService:GetSecret(Config.notifySecretName)
	end)
	if not okSecret then
		if not self.warnedSecret then
			self.warnedSecret = true
			warn(`[Notifications] API キー（Secrets の {Config.notifySecretName}）を読めない：{secret}`)
		end
		return false
	end
	local payload: any = {
		message_id = messageId,
		type = "MOMENT",
		join_experience = { launch_data = `notify:{r.kind}` }, -- 通知から入ったときに開く画面（M8 でつなぐ：D-159）
		analytics_data = { category = r.kind },
	}
	if r.count ~= nil then
		payload.parameters = { count = { int64_value = r.count } }
	end
	local body = HttpService:JSONEncode({
		source = { universe = `universes/{game.GameId}` },
		payload = payload,
	})
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = `https://apis.roblox.com/cloud/v2/users/{r.userId}/notifications`,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json", ["x-api-key"] = secret },
			Body = body,
		})
	end)
	if not ok then
		warn(`[Notifications] 通知を送れなかった（{r.userId}、{r.kind}）：{response}`)
		return false
	end
	if not response.Success then
		warn(
			`[Notifications] 通知を送れなかった（{r.userId}、{r.kind}、{response.StatusCode}）：{response.Body}`
		)
		return false
	end
	return true
end

-- 送る時刻が来た予約を送る
function Notifications.poll(self: any)
	local now = os.time()
	local ok, items = pcall(function()
		return self.queue:GetRangeAsync(Enum.SortDirection.Ascending, Config.notifyBatch, nil, { sortKey = now + 1 })
	end)
	if not ok then
		warn(`[Notifications] 通知の予約を読めなかった：{items}`)
		return
	end
	local today = Calendar.dayIndex(now)
	for _, item in items do
		local r = item.value :: Reservation
		local key = item.key
		local playing = type(r) == "table" and Players:GetPlayerByUserId(r.userId) ~= nil
		if type(r) == "table" and not playing and claimToday(self, r.userId, today) then
			sendOne(self, r) -- 送れなくても今日の1通は使ったことにする（同じ日に何度も試さない）
		end
		pcall(function()
			self.queue:RemoveAsync(key)
		end)
	end
end

function Notifications.start(self: any)
	if not Config.notifyEnabled then
		return
	end
	task.spawn(function()
		while true do
			task.wait(Config.notifyPollSeconds)
			local ok, err = pcall(self.poll, self)
			if not ok then
				warn(`[Notifications] 通知の送信でエラー：{err}`)
			end
		end
	end)
end

return Notifications
