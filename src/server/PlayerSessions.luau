--!strict
-- プレイヤーごとのセッション（11章 §2・§3）
-- 参加時の読み込み（ロック・移行・留守番・届け物）、定期保存、退出時・サーバー終了時の保存と解放。
--
-- 同じ留守を二重に計算しない（05章 §3、11章 §3.5、M7b-5）：
--   - 留守番の advance（ctx.online == false）は、ロックを取って読み込んだあと、ログイン1回につき loadPlayer の中で1回だけ呼ぶ。
--   - 保存のたびに state.lastSavedAt を書く（D-161 の留守の始まり）。留守番を計算していない記録（読み込み中の退出・移行の失敗）は、
--     中身を変えずにロックだけ解放する（lastSavedAt を進めない）。
--   - 同じプレイヤーの読み込み・保存は、このサーバーの中で1つずつ行う（withUser）。同じサーバーへすぐ入り直したとき、
--     退出時の保存が終わる前に古い記録を読んで留守を計算し直すのを防ぐ（同じ jobId のロックはすぐ取れるため）。

local HttpService = game:GetService("HttpService")

local Game = require("@game/ReplicatedStorage/Core/Game")
local Migration = require("@game/ReplicatedStorage/Core/Migration")
local Notify = require("@game/ReplicatedStorage/Core/Notify")
local Config = require("./Config")
local Deliveries = require("./Deliveries")
local FriendCounter = require("./FriendCounter")
local Persistence = require("./Persistence")
local Referral = require("./Referral")

local PlayerSessions = {}
PlayerSessions.__index = PlayerSessions

export type Session = {
	player: Player,
	userId: number,
	state: any,
	loadedAt: number,
	lastSavedAt: number,
	-- 通信（11章 §4、M7-3）
	seq: number, -- 最後に送った通知の連番
	lastView: any, -- 最後に送った要約（差分の元：D-103）
	commandTimes: { number }, -- 直近1秒に受けたコマンドの時刻（送りすぎの制限）
	busy: boolean, -- コマンド・時間経過の処理中
	lastWorld: any?, -- 他のプレイヤーへ最後に送った公開情報（WorldChanged、11章 §6.1）
	-- 紹介の届け物を書く処理（11章 §3.7、Referral）
	referralBusy: boolean?, -- 書いている途中
	referralRetryAt: number?, -- 書けなかったとき、次に試す時刻（箱がいっぱいなら math.huge：次のログインまで試さない。D-197）
}

local MSG_LOCKED =
	"別のサーバーでデータを使用中です。しばらくしてから入り直してください。"
local MSG_LOAD_FAILED =
	"データを読み込めませんでした。しばらくしてから入り直してください。"
local MSG_LOST = "別のサーバーで同じデータが使われたため、切断しました。"

-- 届け物を受け取り箱へ入れる（D-180、11章 §3.6）。core の Game.grantDelivery を使う。
--   受け取り箱へ入れたら (true, events)。前に受け取り済み（同じ id）なら消してよいので (true, {})。
--   それ以外（週の上限・知らない種類）は (false, {}) で、届け物は消さずに残す。
local function grantDelivery(state: any, delivery: Deliveries.Delivery, ctx: any): (boolean, { any })
	local ok, events = Game.grantDelivery(state, delivery, ctx)
	if ok then
		return true, events
	end
	local claimed = state.referral and state.referral.claimedDeliveries
	if claimed and claimed[delivery.id] then
		return true, {}
	end
	return false, {}
end

function PlayerSessions.new(master: any)
	local self = setmetatable({}, PlayerSessions)
	-- Studio のプレイテストでは JobId が空になるので、起動ごとに一意の文字列を作る（11章 §3.1）
	local jobId = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)
	self.master = master
	self.persistence = Persistence.new(jobId, game.PlaceId)
	self.deliveries = Deliveries.new()
	self.sessions = {} :: { [number]: Session }
	self.onLoaded = nil :: ((Session, { any }) -> ())?
	-- コマンド・時間経過以外で状態を変えたとき（紹介の報酬など）に、クライアントへ知らせる（Network が入れる）
	self.onChanged = nil :: ((Session, { any }) -> ())?
	-- 同じサーバーにいる友達の数（D-157、11章 §2.1）
	self.friends = FriendCounter.new()
	-- 処理中の読み込み・保存の数。サーバー終了時は、退出時の保存や読み込み中のものも終わるまで待つ（M7-5 で発見）
	self.inFlight = 0
	self.closing = false
	-- 読み込み・保存の処理中のプレイヤー（同じプレイヤーの処理を重ねない：withUser）
	self.userBusy = {} :: { [number]: boolean }
	return self
end

function PlayerSessions.ctx(self: any, online: boolean): any
	return { now = os.time(), master = self.master, online = online }
end

-- そのプレイヤーのコマンド用の ctx。同じサーバーにいる友達の数を friendCount に入れる（D-157。ClaimFriendReward が読む）
function PlayerSessions.ctxFor(self: any, session: Session, online: boolean): any
	local ctx = self:ctx(online)
	ctx.friendCount = self.friends:count(session.userId)
	return ctx
end

-- 紹介の届け物を書く必要があれば、別の処理で書く（D-157・D-180・D-192、11章 §3.7）。
-- コマンド・時間経過・読み込みのあとに呼ぶ。待ちを入れない
function PlayerSessions.checkReferral(self: any, session: Session)
	if self.sessions[session.userId] ~= session then
		return
	end
	if not Referral.needsDelivery(session, self.master, os.time()) then
		return
	end
	task.spawn(Referral.deliver, session, {
		deliveries = self.deliveries,
		ctxFor = function(s: any): any
			return self:ctxFor(s, true)
		end,
		onChanged = function(s: any, events: { any })
			if self.onChanged then
				self.onChanged(s, events)
			end
		end,
		isCurrent = function(s: any): boolean
			return self.sessions[s.userId] == s
		end,
	})
end

function PlayerSessions.get(self: any, player: Player): Session?
	return self.sessions[player.UserId]
end

-- 同じプレイヤーの読み込み・保存を1つずつ行う。待っている間も inFlight に数える（サーバー終了時に待つため）。
local function withUser(self: any, userId: number, label: string, fn: () -> ())
	self.inFlight += 1
	while self.userBusy[userId] do
		task.wait()
	end
	self.userBusy[userId] = true
	local ok, err = pcall(fn)
	self.userBusy[userId] = nil
	self.inFlight -= 1
	if not ok then
		warn(`[PlayerSessions] {label}の処理でエラー（{userId}）：{err}`)
	end
end

-- セッションの状態を保存する。保存のたびに最後に保存した時刻を書く（D-161、03章 lastSavedAt）。
-- withUser の中から呼ぶ。
local function saveSession(self: any, session: Session, release: boolean): string
	session.state.lastSavedAt = os.time()
	local ok, resultOrErr = pcall(function()
		return self.persistence:save(session.userId, session.state, release)
	end)
	local result = if ok then resultOrErr else "error"
	if not ok then
		warn(`[PlayerSessions] 保存の処理でエラー（{session.userId}）：{resultOrErr}`)
	end
	if result == "ok" then
		session.lastSavedAt = session.state.lastSavedAt
	end
	return result
end

-- 届け物を読み出す。読めなくてもログインは止めない（届け物は残り、次のログインで受け取る）
local function readDeliveries(self: any, userId: number): { Deliveries.Delivery }
	local ok, okRead, items = pcall(self.deliveries.read, self.deliveries, userId)
	if not ok or not okRead then
		warn(`[PlayerSessions] 届け物を読めなかった（{userId}）`)
		return {}
	end
	return items
end

local function loadPlayer(self: any, player: Player)
	local userId = player.UserId
	-- ロックが取れなければ、ここで待って再試行する（Persistence.load）。取れるまで留守番は計算しない
	local status, record, err = self.persistence:load(userId)

	if status == "locked" then
		player:Kick(MSG_LOCKED)
		return
	elseif status == "error" then
		warn(`[PlayerSessions] 読み込み失敗（{userId}）：{err}`)
		player:Kick(MSG_LOAD_FAILED)
		return
	end

	-- 届け物の読み出し（D-180）。待ちが入る処理は、退出の確認より前に済ませる
	local deliveries = readDeliveries(self, userId)

	-- 読み込み中に退出した、またはサーバーが終了中：取ったロックを、中身を変えずに解放する。
	-- 留守番を計算していないので lastSavedAt も変えない（次のログインで同じ留守を1回だけ計算する）
	if player.Parent == nil or self.closing then
		self.persistence:save(userId, record.state, true)
		return
	end

	local isNew = record.state == nil
	local ok, stateOrErr = pcall(function()
		if isNew then
			-- 新規プレイヤーの乱数の元。Roblox の Random を使うのはここだけ（11章 §2）
			local seed = Random.new():NextInteger(1, 2 ^ 31 - 1)
			return Game.newState(self.master, seed, os.time())
		end
		return Migration.migrate(record.state, self.master)
	end)
	if not ok then
		-- 移行に失敗したデータは上書きしない。ロックだけ解放して切断する
		warn(`[PlayerSessions] 移行失敗（{userId}）：{stateOrErr}`)
		self.persistence:save(userId, record.state, true)
		player:Kick(MSG_LOAD_FAILED)
		return
	end
	local state = stateOrErr
	-- 紹介：新規のプレイヤーなら招待した人（ReferredByPlayerId）を記録する（D-157、11章 §3.7）。待ちを入れない
	Referral.recordOnLoad(player, state, isNew)

	-- 留守番（05章 §3、06章 §13・§14、D-161・D-172・D-186）。ログイン1回につきここで1回だけ。
	-- 留守の始まりは core の Game.offlineStart（lastSavedAt と lastAdvancedAt の遅いほう）。
	-- ここから session を登録するまで待ちを入れない（途中で退出・定期の advance が割り込まないように）
	local ctx = self:ctx(false)
	local offlineEvents = Game.advance(state, ctx)
	-- ログインした時刻を記録する（「いつも遊ぶ時刻」＝直近7回の中央値：D-196、11章 §8.2）。ログイン1回につきここで1回だけ
	Notify.recordLogin(state, ctx.now, self.master)

	-- 届け物を受け取り箱へ（D-180）。入れたものの id だけを、保存できたあとで消す
	local granted: { string } = {}
	for _, d in deliveries do
		local okGrant, done, events = pcall(grantDelivery, state, d, ctx)
		if not okGrant then
			warn(`[PlayerSessions] 届け物を受け取れなかった（{userId}、{d.id}）：{done}`)
		elseif done then
			table.insert(granted, d.id)
			for _, e in events do
				table.insert(offlineEvents, e)
			end
		end
	end

	local now = os.time()
	local session: Session = {
		player = player,
		userId = userId,
		state = state,
		loadedAt = now,
		lastSavedAt = 0,
		seq = 0,
		lastView = nil,
		commandTimes = {},
		busy = false,
	}
	self.sessions[userId] = session
	print(
		`[PlayerSessions] {player.Name} を読み込み（{if isNew then "新規" else "既存"}、所持金 {state.gold}）`
	)

	if self.onLoaded then
		self.onLoaded(session, offlineEvents)
	end
	self:checkReferral(session)

	-- 届け物を受け取ったら、すぐ保存してから届け物を消す（保存より先に消すと、落ちたときに届け物を失う）
	if #granted > 0 then
		local result = saveSession(self, session, false)
		if result == "ok" then
			if not self.deliveries:remove(userId, granted) then
				warn(`[PlayerSessions] 受け取った届け物を消せなかった（{userId}）`)
			end
		elseif result == "lost" then
			if self.sessions[userId] == session then
				self.sessions[userId] = nil
			end
			player:Kick(MSG_LOST)
		else
			warn(`[PlayerSessions] 届け物を受け取ったあとの保存に失敗（{userId}）`)
		end
	end
end

function PlayerSessions.onPlayerAdded(self: any, player: Player)
	withUser(self, player.UserId, "読み込み", function()
		loadPlayer(self, player)
	end)
end

function PlayerSessions.onPlayerRemoving(self: any, player: Player)
	local userId = player.UserId
	local session = self.sessions[userId]
	if session == nil then
		return
	end
	self.sessions[userId] = nil
	withUser(self, userId, "退出時の保存", function()
		local result = saveSession(self, session, true)
		if result == "error" then
			warn(`[PlayerSessions] 退出時の保存に失敗（{userId}）`)
		end
	end)
end

-- すぐ保存する（管理者モードのデータの初期化：D-306）。待ちを入れない
function PlayerSessions.saveNow(self: any, session: Session)
	task.spawn(withUser, self, session.userId, "管理者の保存", function()
		if self.sessions[session.userId] == session then
			saveSession(self, session, false)
		end
	end)
end

-- 定期保存（11章 §3.3）。ロックを失っていたら書かずに切断する。
-- 保存の待ちの間に入れ替わる（退出・入り直し）ので、先に一覧を写し、保存の前後でセッションが同じか確かめる
function PlayerSessions.autosave(self: any)
	local list: { Session } = {}
	for _, session in self.sessions do
		table.insert(list, session)
	end
	for _, session in list do
		local userId = session.userId
		withUser(self, userId, "定期保存", function()
			if self.sessions[userId] ~= session then
				return -- 待っている間に退出した（退出時の保存で書いた）
			end
			local result = saveSession(self, session, false)
			if result == "lost" then
				if self.sessions[userId] == session then
					self.sessions[userId] = nil
				end
				session.player:Kick(MSG_LOST)
			elseif result == "error" then
				warn(`[PlayerSessions] 定期保存に失敗（{userId}）`)
			end
		end)
	end
end

-- サーバー終了時（BindToClose）：全員を並行して保存・解放し、終わるまで待つ。
-- 先に始まっている退出時の保存・読み込みも終わるまで待つ（待たないと、ロックが残ったまま終わる：M7-5 で発見）
function PlayerSessions.saveAll(self: any)
	self.closing = true
	for userId, session in self.sessions do
		self.sessions[userId] = nil
		task.spawn(withUser, self, userId, "終了時の保存", function()
			saveSession(self, session, true)
		end)
	end
	local started = os.clock()
	while self.inFlight > 0 and os.clock() - started < Config.closeWaitSeconds do
		task.wait()
	end
	if self.inFlight > 0 then
		warn(
			`[PlayerSessions] 終了時の保存が {Config.closeWaitSeconds} 秒で終わらなかった（残り {self.inFlight}）`
		)
	end
end

return PlayerSessions
