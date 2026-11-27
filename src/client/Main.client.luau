--!strict
-- クライアントの入口（11章 §5、D-227）。
--   - M8 の画面：メイン画面（Hub）を土台に置き、ほかの画面は Nav で重ねる。
--   - デバッグ画面（M7）：状態の一覧・テキスト版と同じ書式の入力欄・結果のログ。F1 で表示を切り替える（最初は隠す）。
--   - F2：部品の見本（Gallery）を開く／閉じる。

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- 本番で複製が遅れても失敗しないように、読み込みを待ってから require する（11章 §1）
if not game:IsLoaded() then
	game.Loaded:Wait()
end
ReplicatedStorage:WaitForChild("Core")
ReplicatedStorage:WaitForChild("Data")
ReplicatedStorage:WaitForChild("Remotes")

local CommandText = require("@game/ReplicatedStorage/Core/CommandText")
local Game = require("@game/ReplicatedStorage/Core/Game")
local DebugView = require("./DebugView")
local master = require("./Master")
local NotificationPrompt = require("./NotificationPrompt")
local Session = require("./Session")

-- デバッグ画面 ----------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "DebugScreen"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Enabled = false

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

local function onPromptResult(stage: string, shown: boolean)
	log(
		`通知の許可の画面（{stage}）：{if shown
			then "出した"
			else "出せない（許可済み・13歳未満・出したばかりなど）"}`
	)
end

local function renderDebug()
	local view = Session.view
	if view then
		stateLabel.Text = DebugView.render(view, master, Session.now())
		-- 初めての帰還・ログインボーナス2日目に通知の許可の画面を出す（D-196 ③）
		NotificationPrompt.onView(view, Session.send, onPromptResult)
	else
		stateLabel.Text = "読み込み中…"
	end
end

Session.changed:connect(renderDebug)
Session.events:connect(function(reason, events)
	log(`[{reason}]`)
	logEvents(events)
end)
Session.notice:connect(log)

local HELP = "使えるコマンド\n  help / sync（全体を取り直す）\n"
	.. "  notify                     通知の許可の画面を出す（D-181。設定画面に置くものの仮）\n"
	.. CommandText.HELP

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
		task.spawn(Session.resync)
		return
	elseif line == "notify" then
		local shown = NotificationPrompt.prompt(function()
			log("通知の許可の画面を閉じた")
		end)
		log(
			if shown
				then "通知の許可の画面を出した"
				else "通知の許可の画面を出せない（13歳未満・出したばかりなど）"
		)
		return
	end
	local command = CommandText.parse(line)
	if command == nil then
		log("不明なコマンド（help で一覧）")
		return
	end
	-- eventgo・buy で時間帯を省いたら、今の時間帯で埋める（テキスト版と同じ：D-152）
	if (command.type == "DispatchEvent" or command.type == "BuyFromMerchant") and command.eventSlot == nil then
		command.eventSlot = Game.query.mapEvent(Session.now(), master, Session.view).current.eventSlot
	end
	local r = Session.send(command)
	if r == nil then
		log("NG 通信エラー")
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

-- M8 の画面 --------------------------------------------------------------------

local Nav = require("./ui/Nav")
local Root = require("./ui/Root")
require("./screens/Gallery")
local Hub = require("./screens/Hub")

Root.mount()
Hub.mount()
-- 管理者モード（D-306）：サーバーが管理者と答えたときだけ、左上に ⚙ のボタンを出す
task.spawn(require("./admin/AdminTool").mount)

UserInputService.InputBegan:Connect(function(io: InputObject, processed: boolean)
	if processed then
		return
	end
	if io.KeyCode == Enum.KeyCode.F1 then
		gui.Enabled = not gui.Enabled
	elseif io.KeyCode == Enum.KeyCode.F2 then
		if Nav.depth() == 0 then
			Nav.open("Gallery")
		else
			Nav.home()
		end
	end
end)

renderDebug()
task.spawn(Session.resync)

-- 探索の進み具合（残り秒数など）を更新する
task.spawn(function()
	while true do
		task.wait(1)
		if gui.Enabled then
			renderDebug()
		end
	end
end)
