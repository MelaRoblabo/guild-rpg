--!strict
-- クライアントの入口：デバッグ用の簡易画面（11章 §5、M7）。見た目は作らない（UI は M8）。
-- 状態の一覧・テキスト版と同じ書式の入力欄・結果のログ。

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 本番で複製が遅れても失敗しないように、読み込みを待ってから require する（11章 §1）
if not game:IsLoaded() then
	game.Loaded:Wait()
end
ReplicatedStorage:WaitForChild("Core")
ReplicatedStorage:WaitForChild("Data")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local commandRemote = remotes:WaitForChild("Command") :: RemoteFunction
local stateRemote = remotes:WaitForChild("StateChanged") :: RemoteEvent

local CommandText = require("@game/ReplicatedStorage/Core/CommandText")
local Data = require("@game/ReplicatedStorage/Data")
local MasterData = require("@game/ReplicatedStorage/Core/MasterData")
local Protocol = require("@game/ReplicatedStorage/Core/Protocol")
local DebugView = require("./DebugView")

local master = MasterData.load(Data)

-- 画面 ----------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "DebugScreen"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

local function textBox(name: string, parent: Instance, pos: UDim2, size: UDim2): TextLabel
	local frame = Instance.new("ScrollingFrame")
	frame.Name = name
	frame.Position = pos
	frame.Size = size
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.ScrollBarThickness = 8
	frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	frame.CanvasSize = UDim2.new()
	frame.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -12, 0, 0)
	label.Position = UDim2.fromOffset(6, 4)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(230, 230, 230)
	label.Font = Enum.Font.Code
	label.TextSize = 14
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = ""
	label.Parent = frame
	return label
end

local stateLabel = textBox("State", gui, UDim2.fromScale(0, 0), UDim2.new(0.6, 0, 1, -40))
local logLabel = textBox("Log", gui, UDim2.fromScale(0.6, 0), UDim2.new(0.4, 0, 1, -40))

local input = Instance.new("TextBox")
input.Name = "Input"
input.Position = UDim2.new(0, 0, 1, -40)
input.Size = UDim2.new(1, 0, 0, 40)
input.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
input.BorderSizePixel = 0
input.TextColor3 = Color3.fromRGB(255, 255, 255)
input.PlaceholderText = "コマンドを入力して Enter（help で一覧）"
input.Font = Enum.Font.Code
input.TextSize = 16
input.TextXAlignment = Enum.TextXAlignment.Left
input.ClearTextOnFocus = false
input.Text = ""
input.Parent = gui

gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

-- ログ ----------------------------------------------------------------------

local logLines: { string } = {}
local MAX_LOG = 200

local function log(s: string)
	table.insert(logLines, s)
	while #logLines > MAX_LOG do
		table.remove(logLines, 1)
	end
	logLabel.Text = table.concat(logLines, "\n")
	local frame = logLabel.Parent :: ScrollingFrame
	frame.CanvasPosition = Vector2.new(0, math.huge)
end

local function logEvents(events: { any }?)
	for _, e in events or {} do
		local json = HttpService:JSONEncode(e)
		if #json > 240 then
			json = string.sub(json, 1, 240) .. "…"
		end
		log("  · " .. json)
	end
end

-- 状態（D-103：起動時に全体、以後は差分） --------------------------------------

local view: any = nil
local seq = 0
local syncing = false

local function now(): number
	return math.floor(workspace:GetServerTimeNow())
end

local function render()
	if view then
		stateLabel.Text = DebugView.render(view, master, now())
	else
		stateLabel.Text = "読み込み中…"
	end
end

local function resync()
	if syncing then
		return
	end
	syncing = true
	while true do
		local ok, r = pcall(function()
			return commandRemote:InvokeServer({ type = "Sync" })
		end)
		if ok and r and r.ok and r.view then
			view, seq = r.view, r.seq
			break
		end
		task.wait(0.5)
	end
	syncing = false
	render()
end

stateRemote.OnClientEvent:Connect(function(msg: any)
	if #(msg.events or {}) > 0 then
		log(`[{msg.reason}]`)
		logEvents(msg.events)
	end
	if syncing then
		return -- 取り直しの結果に含まれる
	end
	if msg.reason == "load" then
		view, seq = msg.view, msg.seq
	elseif view == nil or msg.seq <= seq then
		return
	elseif msg.baseSeq ~= seq then
		log("（通知の取りこぼし。全体を取り直します）")
		task.spawn(resync)
		return
	else
		Protocol.applyPatch(view, msg.patch)
		seq = msg.seq
	end
	render()
end)

-- 入力 ----------------------------------------------------------------------

local HELP = "使えるコマンド\n  help / sync（全体を取り直す）\n" .. CommandText.HELP

local function submit(line: string)
	line = string.match(line, "^%s*(.-)%s*$") or ""
	if line == "" then
		return
	end
	log("> " .. line)
	if line == "help" then
		log(HELP)
		return
	elseif line == "sync" then
		task.spawn(resync)
		return
	end
	local command = CommandText.parse(line)
	if command == nil then
		log("不明なコマンド（help で一覧）")
		return
	end
	local ok, r = pcall(function()
		return commandRemote:InvokeServer(command)
	end)
	if not ok then
		log("NG 通信エラー: " .. tostring(r))
	elseif r.ok then
		log("OK")
	else
		log(`NG {r.error}{if r.detail then "（" .. r.detail .. "）" else ""}`)
	end
end

input.FocusLost:Connect(function(enterPressed: boolean)
	if enterPressed then
		local line = input.Text
		input.Text = ""
		-- 応答を待つ間も次を打てるよう、先に入力欄へ戻す（コマンドはサーバーが到着順に処理する）
		task.defer(function()
			input:CaptureFocus()
		end)
		task.spawn(submit, line)
	end
end)

render()
task.spawn(resync)

-- 探索の進み具合（残り秒数など）を更新する
task.spawn(function()
	while true do
		task.wait(1)
		render()
	end
end)
