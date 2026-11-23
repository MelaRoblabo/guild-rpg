--!strict
-- プレイヤーごとのセッション（11章 §2・§3）
-- 参加時の読み込み（ロック・移行・オフライン中の帰還）、定期保存、退出時・サーバー終了時の保存と解放。
-- コマンドと通知は M7-3 で追加する。

local HttpService = game:GetService("HttpService")

local Game = require("@game/ReplicatedStorage/Core/Game")
local Migration = require("@game/ReplicatedStorage/Core/Migration")
local Config = require("./Config")
local Persistence = require("./Persistence")

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
}

local MSG_LOCKED =
	"別のサーバーでデータを使用中です。しばらくしてから入り直してください。"
local MSG_LOAD_FAILED =
	"データを読み込めませんでした。しばらくしてから入り直してください。"
local MSG_LOST = "別のサーバーで同じデータが使われたため、切断しました。"

function PlayerSessions.new(master: any)
	local self = setmetatable({}, PlayerSessions)
	-- Studio のプレイテストでは JobId が空になるので、起動ごとに一意の文字列を作る（11章 §3.1）
	local jobId = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)
	self.master = master
	self.persistence = Persistence.new(jobId, game.PlaceId)
	self.sessions = {} :: { [number]: Session }
	self.onLoaded = nil :: ((Session, { any }) -> ())?
	-- 処理中の読み込み・保存の数。サーバー終了時は、退出時の保存や読み込み中のものも終わるまで待つ（M7-5 で発見）
	self.inFlight = 0
	self.closing = false
	return self
end

function PlayerSessions.ctx(self: any, online: boolean): any
	return { now = os.time(), master = self.master, online = online }
end

function PlayerSessions.get(self: any, player: Player): Session?
	return self.sessions[player.UserId]
end

local function loadPlayer(self: any, player: Player)
	local userId = player.UserId
	local status, record, err = self.persistence:load(userId)

	if status == "locked" then
		player:Kick(MSG_LOCKED)
		return
	elseif status == "error" then
		warn(`[PlayerSessions] 読み込み失敗（{userId}）：{err}`)
		player:Kick(MSG_LOAD_FAILED)
		return
	end

	-- 読み込み中に退出した、またはサーバーが終了中：取ったロックを、中身を変えずに解放する
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

	-- オフライン中に帰還した探索だけを処理する（05章 §3、企画書§16.8 案A）
	local offlineEvents = Game.advance(state, self:ctx(false))

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
end

function PlayerSessions.onPlayerAdded(self: any, player: Player)
	self.inFlight += 1
	local ok, err = pcall(loadPlayer, self, player)
	self.inFlight -= 1
	if not ok then
		warn(`[PlayerSessions] 読み込みの処理でエラー（{player.UserId}）：{err}`)
	end
end

local function saveSession(self: any, session: Session, release: boolean): string
	self.inFlight += 1
	local ok, resultOrErr = pcall(function()
		return self.persistence:save(session.userId, session.state, release)
	end)
	self.inFlight -= 1
	local result = if ok then resultOrErr else "error"
	if result == "ok" then
		session.lastSavedAt = os.time()
	end
	return result
end

function PlayerSessions.onPlayerRemoving(self: any, player: Player)
	local session = self.sessions[player.UserId]
	if session == nil then
		return
	end
	self.sessions[player.UserId] = nil
	local result = saveSession(self, session, true)
	if result == "error" then
		warn(`[PlayerSessions] 退出時の保存に失敗（{player.UserId}）`)
	end
end

-- 定期保存（11章 §3.3）。ロックを失っていたら書かずに切断する
function PlayerSessions.autosave(self: any)
	for userId, session in self.sessions do
		local result = saveSession(self, session, false)
		if result == "lost" then
			self.sessions[userId] = nil
			session.player:Kick(MSG_LOST)
		elseif result == "error" then
			warn(`[PlayerSessions] 定期保存に失敗（{userId}）`)
		end
	end
end

-- サーバー終了時（BindToClose）：全員を並行して保存・解放し、終わるまで待つ。
-- 先に始まっている退出時の保存・読み込みも終わるまで待つ（待たないと、ロックが残ったまま終わる：M7-5 で発見）
function PlayerSessions.saveAll(self: any)
	self.closing = true
	for userId, session in self.sessions do
		self.sessions[userId] = nil
		task.spawn(saveSession, self, session, true)
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
