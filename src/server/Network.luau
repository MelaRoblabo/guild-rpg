--!strict
-- 通信（11章 §4、D-101・D-103）
--   Command（RemoteFunction）：コマンドを受けて検証 → advance → execute。Sync は全体と連番を返す
--   Query（RemoteFunction）：読み取り専用の問い合わせ。状態の要約で隠している乱数の元（seed）から作るもの（旅の商人の品：D-152）を
--     サーバーで計算して返す。状態は変えない
--   StateChanged（RemoteEvent）：参加時は全体、以後は前回送った要約との差分と連番
--   定期の時間経過：帰還・自動再派遣が起きたら差分を送る
--   サーバーの都合で状態を変えたとき（紹介の報酬など：reason = "server"）も差分を送る

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = require("@game/ReplicatedStorage/Core/Game")
local Protocol = require("@game/ReplicatedStorage/Core/Protocol")
local Config = require("./Config")

local Network = {}

local function concat(a: { any }, b: { any }): { any }
	local out = table.clone(a)
	for _, x in b do
		table.insert(out, x)
	end
	return out
end

function Network.start(sessions: any)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local commandRemote = remotes:WaitForChild("Command") :: RemoteFunction
	local stateRemote = remotes:WaitForChild("StateChanged") :: RemoteEvent
	local queryRemote = remotes:WaitForChild("Query") :: RemoteFunction

	-- 読み取り専用の問い合わせ（seed を渡さずに、seed から作るものだけを返す）
	queryRemote.OnServerInvoke = function(player: Player, q: any): any
		local session = sessions:get(player)
		if session == nil or type(q) ~= "table" then
			return nil
		end
		if q.kind == "merchant" and type(q.eventSlot) == "number" then
			local ok, r = pcall(Game.query.merchant, session.state, q.eventSlot, os.time(), sessions.master)
			return if ok then r else nil
		end
		-- レイドのボスの HP も seed から作る（D-152）。出発済みのダメージは要約の raid にある
		if q.kind == "raid" and type(q.eventSlot) == "number" then
			local ok, r = pcall(Game.query.raid, session.state, q.eventSlot, sessions.master)
			return if ok then r else nil
		end
		return nil
	end

	-- 状態を通知する。load は全体、それ以外は差分（変化も events もなければ送らない）
	local function push(session: any, reason: string, events: { any })
		local view = Protocol.view(session.state, sessions.master)
		local redacted = Protocol.redactEvents(events)
		if reason == "load" or session.lastView == nil then
			session.seq += 1
			session.lastView = view
			stateRemote:FireClient(session.player, {
				reason = "load",
				seq = session.seq,
				view = view,
				events = redacted,
				serverTime = os.time(),
			})
			return
		end
		local patch = Protocol.diff(session.lastView, view)
		if #patch == 0 and #redacted == 0 then
			return
		end
		local baseSeq = session.seq
		session.seq += 1
		session.lastView = view
		stateRemote:FireClient(session.player, {
			reason = reason,
			seq = session.seq,
			baseSeq = baseSeq,
			patch = patch,
			events = redacted,
			serverTime = os.time(),
		})
	end

	sessions.onLoaded = function(session: any, offlineEvents: { any })
		push(session, "load", offlineEvents)
	end
	sessions.onChanged = function(session: any, events: { any })
		push(session, "server", events)
	end

	-- 送りすぎの制限（1人あたり1秒に commandRateLimit 回）
	local function rateLimited(session: any): boolean
		local now = os.clock()
		local kept = {}
		for _, t in session.commandTimes do
			if now - t < 1 then
				table.insert(kept, t)
			end
		end
		session.commandTimes = kept
		if #kept >= Config.commandRateLimit then
			return true
		end
		table.insert(kept, now)
		return false
	end

	commandRemote.OnServerInvoke = function(player: Player, command: any): any
		local session = sessions:get(player)
		if session == nil then
			return { ok = false, error = "NOT_READY" }
		end
		if rateLimited(session) then
			return { ok = false, error = "RATE_LIMITED" }
		end
		if type(command) == "table" and command.type == "Sync" then
			return { ok = true, seq = session.seq, view = session.lastView }
		end
		local valid, reason = Protocol.validateCommand(command)
		if not valid then
			return { ok = false, error = "BAD_REQUEST", detail = reason }
		end

		-- 1人のコマンドは1つずつ処理する（11章 §4.4）
		while session.busy do
			task.wait()
		end
		if sessions:get(player) ~= session then
			return { ok = false, error = "NOT_READY" }
		end
		session.busy = true
		local ok, resultOrErr = pcall(function()
			-- 同じサーバーにいる友達の数を ctx.friendCount に入れる（D-157。ClaimFriendReward が読む）
			local ctx = sessions:ctxFor(session, true)
			local advanced = Game.advance(session.state, ctx)
			local result = Game.execute(session.state, command, ctx)
			return { advanced = advanced, result = result }
		end)
		session.busy = false
		if not ok then
			warn(`[Network] コマンドの処理でエラー（{player.UserId}、{command.type}）：{resultOrErr}`)
			return { ok = false, error = "SERVER_ERROR" }
		end

		local result = resultOrErr.result
		push(session, "command", concat(resultOrErr.advanced, result.events or {}))
		sessions:checkReferral(session) -- 紹介の進み具合に届いたか（D-192）
		return { ok = result.ok, error = result.error, events = Protocol.redactEvents(result.events or {}) }
	end

	-- 定期の時間経過（11章 §2）
	task.spawn(function()
		while true do
			task.wait(Config.advanceIntervalSeconds)
			for _, session in sessions.sessions do
				if not session.busy then
					session.busy = true
					local ok, eventsOrErr = pcall(Game.advance, session.state, sessions:ctx(true))
					session.busy = false
					if not ok then
						warn(`[Network] 時間経過の処理でエラー（{session.userId}）：{eventsOrErr}`)
					elseif #eventsOrErr > 0 then
						push(session, "advance", eventsOrErr)
						sessions:checkReferral(session) -- 紹介の進み具合に届いたか（D-192）
					end
				end
			end
		end
	end)
end

return Network
