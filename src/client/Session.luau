--!strict
-- 状態の受け取りとコマンドの送り先（11章 §4、D-103）。デバッグ画面と M8 の画面が同じものを使う。
--   - 起動時に Sync で全体を取り、以後は StateChanged の差分を当てる。連番が飛んだら取り直す。
--   - changed：状態が変わった（または取り直した）とき。events：サーバーで起きたこと。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require("@game/ReplicatedStorage/Core/Protocol")
local Signal = require("./ui/Signal")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local commandRemote = remotes:WaitForChild("Command") :: RemoteFunction
local stateRemote = remotes:WaitForChild("StateChanged") :: RemoteEvent
local queryRemote = remotes:WaitForChild("Query") :: RemoteFunction

local Session = {}

Session.view = nil :: any
Session.seq = 0
Session.changed = Signal.new() :: Signal.Signal<any>
Session.events = Signal.new() :: Signal.Signal<string, { any }>
Session.notice = Signal.new() :: Signal.Signal<string>

local syncing = false

function Session.now(): number
	return math.floor(workspace:GetServerTimeNow())
end

-- 読み取り専用の問い合わせ（旅の商人の品など、seed から作るもの）。通信に失敗したら nil
function Session.query(q: any): any?
	local ok, r = pcall(function()
		return queryRemote:InvokeServer(q)
	end)
	return if ok then r else nil
end

-- コマンドを送る。通信に失敗したら nil
function Session.send(command: any): any?
	local ok, r = pcall(function()
		return commandRemote:InvokeServer(command)
	end)
	return if ok then r else nil
end

-- コマンドを送り、成功したら状態の差分が届くまで待つ（届いた状態で次の画面を作るため）。最大 2 秒
function Session.sendAndWait(command: any): any?
	local before = Session.seq
	local r = Session.send(command)
	if r and r.ok then
		local deadline = os.clock() + 2
		while Session.seq == before and os.clock() < deadline do
			task.wait()
		end
	end
	return r
end

function Session.resync()
	if syncing then
		return
	end
	syncing = true
	while true do
		local r = Session.send({ type = "Sync" })
		if r and r.ok and r.view then
			Session.view, Session.seq = r.view, r.seq
			break
		end
		task.wait(0.5)
	end
	syncing = false
	Session.changed:fire(Session.view)
end

stateRemote.OnClientEvent:Connect(function(msg: any)
	if #(msg.events or {}) > 0 then
		Session.events:fire(msg.reason, msg.events)
	end
	if syncing then
		return -- 取り直しの結果に含まれる
	end
	if msg.reason == "load" then
		Session.view, Session.seq = msg.view, msg.seq
	elseif Session.view == nil or msg.seq <= Session.seq then
		return
	elseif msg.baseSeq ~= Session.seq then
		Session.notice:fire("（通知の取りこぼし。全体を取り直します）")
		task.spawn(Session.resync)
		return
	else
		Protocol.applyPatch(Session.view, msg.patch)
		Session.seq = msg.seq
	end
	Session.changed:fire(Session.view)
end)

return Session
