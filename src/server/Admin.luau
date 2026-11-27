--!strict
-- 管理者モード（D-306、11章 §9）。開発・確認のための道具で、プレイヤーのコマンド（Protocol）とは別の入口にする。
--   入口：ReplicatedStorage.Remotes.Admin（RemoteFunction）。{ op = "...", ... } を受けて { ok, result?, error? } を返す。
--   使える人（サーバーで毎回確かめる。端末からの申告は信じない）：
--     - Roblox Studio のテストプレイ（RunService:IsStudio()）
--     - Config.adminUserIds に登録したプレイヤー（ServerScriptService にあるので端末からは見えない）
--   それ以外の人の呼び出しは何もせず nil を返す（ボタンを出すかの問い合わせ hello 以外は警告を出す）。
--   Claude（Studio の MCP）からも、テストプレイ中の Client で Remotes.Admin:InvokeServer({ op = "setGold", gold = 99999 }) のように呼べる。
--
-- 操作（足すときは ops に1つ足し、端末の AdminTool にボタンを足す）：
--   hello                          管理者なら { gold? } を返す（端末が ⚙ ボタンを出すかを決める。読み込み前でも答え、gold は読み込み後だけ）
--   setGold { gold }               所持金を gold にする（0〜MAX_GOLD の整数）
--   resetData                      自分のデータを新規と同じ状態に戻す（乱数の元も引き直す）。すぐ保存する
--   forceEvent { kind }            今の時間帯にマップイベントを出す（"raid" / "rareDungeon"）。そのプレイヤーだけ（MapEvent.force）

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Game = require("@game/ReplicatedStorage/Core/Game")
local MapEvent = require("@game/ReplicatedStorage/Core/MapEvent")
local Config = require("./Config")

local Admin = {}

local MAX_GOLD = 1e12 -- 所持金の上限（DataStore と表示が壊れない範囲）
local RATE_LIMIT = 5 -- 1人あたり1秒の上限
local EVENT_KINDS = { raid = "mev_raid", rareDungeon = "mev_rare_dungeon" } -- 出せるマップイベント（端末の語 → マスターデータの id）

-- 管理者か（サーバーだけで判定する）
function Admin.isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return Config.adminUserIds[player.UserId] == true
end

type Op = (session: any, req: any, sessions: any) -> (any, string?)

local ops: { [string]: Op } = {}

ops.setGold = function(session, req)
	local g = req.gold
	if type(g) ~= "number" or g ~= g or g ~= math.floor(g) or g < 0 or g > MAX_GOLD then
		return nil, "BAD_GOLD"
	end
	session.state.gold = g
	return { gold = g }
end

ops.resetData = function(session, _req, sessions)
	-- 新規プレイヤーと同じ作り方（PlayerSessions の新規と同じく、乱数の元はここで Random から引く）
	local seed = Random.new():NextInteger(1, 2 ^ 31 - 1)
	session.state = Game.newState(sessions.master, seed, os.time())
	return { gold = session.state.gold }
end

ops.forceEvent = function(session, req, sessions)
	local kindId = if type(req.kind) == "string" then EVENT_KINDS[req.kind] else nil
	if kindId == nil then
		return nil, "BAD_KIND"
	end
	local ev = MapEvent.force(session.state, kindId, os.time(), sessions.master)
	return { kind = ev.kind, eventSlot = ev.eventSlot, closeAt = ev.closeAt, placeId = ev.placeId }
end

-- sessions：PlayerSessions。変えたあとは sessions.onAdminChanged(session, full) で端末へ知らせる（Network が入れる）
function Admin.start(sessions: any)
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Admin") :: RemoteFunction
	local calls: { [number]: { number } } = {}

	local function rateLimited(userId: number): boolean
		local now = os.clock()
		local kept = {}
		for _, t in calls[userId] or {} do
			if now - t < 1 then
				table.insert(kept, t)
			end
		end
		if #kept >= RATE_LIMIT then
			calls[userId] = kept
			return true
		end
		table.insert(kept, now)
		calls[userId] = kept
		return false
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		calls[player.UserId] = nil
	end)

	remote.OnServerInvoke = function(player: Player, req: any): any
		local op = if type(req) == "table" and type(req.op) == "string" then req.op else nil
		if not Admin.isAdmin(player) then
			if op ~= "hello" then
				warn(`[Admin] 権限のない呼び出しを拒否（{player.UserId}、{tostring(op)}）`)
			end
			return nil
		end
		if op == "hello" then
			local s = sessions:get(player)
			return { ok = true, result = { gold = if s then s.state.gold else nil } }
		end
		local fn = if op then ops[op] else nil
		if fn == nil then
			return { ok = false, error = "BAD_REQUEST" }
		end
		if rateLimited(player.UserId) then
			return { ok = false, error = "RATE_LIMITED" }
		end
		local session = sessions:get(player)
		if session == nil then
			return { ok = false, error = "NOT_READY" }
		end
		-- コマンド・時間経過と重ねない（Network と同じ busy を使う）
		while session.busy do
			task.wait()
		end
		if sessions:get(player) ~= session then
			return { ok = false, error = "NOT_READY" }
		end
		session.busy = true
		local ok, result, err = pcall(fn, session, req, sessions)
		session.busy = false
		if not ok then
			warn(`[Admin] {op} でエラー（{player.UserId}）：{result}`)
			return { ok = false, error = "SERVER_ERROR" }
		end
		if err then
			return { ok = false, error = err }
		end
		print(`[Admin] {player.Name}（{player.UserId}）が {op} を実行`)
		if op == "resetData" then
			sessions:saveNow(session)
		end
		if sessions.onAdminChanged then
			sessions.onAdminChanged(session, op == "resetData")
		end
		return { ok = true, result = result }
	end
end

return Admin
