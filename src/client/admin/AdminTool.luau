--!strict
-- 管理者モードの道具（D-306）。左上の Roblox のメニューの横に ⚙ のボタンを出し、押すと Admin の面を開く。
--   - ボタンを出すのは、サーバーが管理者と答えたときだけ（Remotes.Admin の hello）。判定はサーバーだけで行い、
--     ここでは何も決めない（ボタンを無理に出しても、サーバーが毎回拒む）。
--   - 面：所持金の編集・マップイベント（レイドボス・レアダンジョン）を出す・自分のデータの初期化（2回押し）。
--   - 開発の道具なので、ゲームの画面（Guild UI）とは別の小さな面にする。語は英語。
--   操作を足すときは、サーバーの Admin の ops と、ここの行を1つずつ足す。

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Create = require("../ui/Create")
local Tokens = require("../ui/Tokens")
local Components = require("../ui/Components")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local AdminTool = {}

local BTN = 44 -- Roblox の上の帯のボタンと同じくらいの大きさ
local PANEL_W = 440
local RESET_CONFIRM_SECONDS = 3

local remote: RemoteFunction? = nil

local function call(req: any): any
	local r = remote
	if r == nil then
		return nil
	end
	local ok, res = pcall(r.InvokeServer, r, req)
	return if ok then res else nil
end

local function label(text: string, size: number, parent: Instance, order: number): TextLabel
	return new("TextLabel", {
		Text = text,
		TextSize = size,
		FontFace = Tokens.font.bodyStrong,
		TextColor3 = C.inkLight,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, size + 8),
		LayoutOrder = order,
		Parent = parent,
	})
end

local function plainButton(text: string, color: Color3, width: number, onClick: () -> ()): TextButton
	local b: TextButton = new("TextButton", {
		Text = text,
		TextSize = 18,
		FontFace = Tokens.font.bodyStrong,
		TextColor3 = C.inkWhite,
		AutoButtonColor = true,
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(width, 40),
		[CHILDREN] = { Components.corner(10) },
	})
	b.Activated:Connect(onClick)
	return b
end

function AdminTool.mount()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remote = remotes:WaitForChild("Admin", 10) :: RemoteFunction?
	local hello = call({ op = "hello" })
	if type(hello) ~= "table" or not hello.ok then
		return -- 管理者でない：何も作らない
	end
	local playerGui = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	local gui: ScreenGui = new("ScreenGui", {
		Name = "AdminTool",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = 200,
		Parent = playerGui,
	})
	-- ⚙ のボタン：Roblox の上の帯の左のボタンのすぐ右（TopbarInset の左端）
	local open: TextButton = new("TextButton", {
		Name = "AdminButton",
		Text = "⚙",
		TextSize = 24,
		FontFace = Tokens.font.number,
		TextColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = true,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.3,
		Size = UDim2.fromOffset(BTN, BTN),
		[CHILDREN] = { Components.corner(BTN / 2) },
		Parent = gui,
	})
	local function place()
		local inset = GuiService.TopbarInset
		local y = math.max(0, (inset.Height - BTN) / 2)
		open.Position = UDim2.fromOffset(inset.Min.X + 6, if inset.Height > 0 then inset.Min.Y + y else 8)
	end
	place()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(place)

	-- Admin の面
	local panel: Frame = new("Frame", {
		Name = "AdminPanel",
		Visible = false,
		BackgroundColor3 = C.ch13,
		Size = UDim2.fromOffset(PANEL_W, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		[CHILDREN] = {
			Components.corner(16),
			Components.stroke(C.warnDark, 3),
			new("UIPadding", {
				PaddingLeft = UDim.new(0, 18),
				PaddingRight = UDim.new(0, 18),
				PaddingTop = UDim.new(0, 14),
				PaddingBottom = UDim.new(0, 14),
			}),
			new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		},
		Parent = gui,
	})
	local function placePanel()
		local p = open.Position
		panel.Position = UDim2.fromOffset(p.X.Offset, p.Y.Offset + BTN + 8)
	end
	placePanel()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(placePanel)

	local title = label("Admin", 24, panel, 1)
	title.FontFace = Tokens.font.display
	local status = label("", 16, panel, 99)
	status.TextColor3 = C.inkMid
	status.TextWrapped = true
	status.Size = UDim2.new(1, 0, 0, 40)
	local function say(text: string, good: boolean?)
		status.Text = text
		status.TextColor3 = if good == false then C.warn elseif good then C.okGreen else C.inkMid
	end
	local function report(r: any, okText: string)
		if type(r) ~= "table" then
			say("No response", false)
		elseif r.ok then
			say(okText, true)
		else
			say("Failed: " .. tostring(r.error), false)
		end
	end

	-- 所持金
	local goldRow: Frame = new("Frame", {
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		[CHILDREN] = {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = panel,
	})
	local goldLabel = label("Gold", 18, goldRow, 1)
	goldLabel.Size = UDim2.fromOffset(60, 40)
	local box: TextBox = new("TextBox", {
		LayoutOrder = 2,
		Text = tostring(hello.result and hello.result.gold or ""),
		PlaceholderText = "0",
		ClearTextOnFocus = false,
		TextSize = 18,
		FontFace = Tokens.font.number,
		TextColor3 = C.inkDark,
		BackgroundColor3 = C.inkLight,
		Size = UDim2.fromOffset(200, 40),
		[CHILDREN] = { Components.corner(8) },
		Parent = goldRow,
	})
	local setGold = plainButton("Set", C.bronze, 110, function()
		local n = tonumber(box.Text)
		if n == nil or n < 0 or n ~= math.floor(n) then
			say("Enter a whole number", false)
			return
		end
		local r = call({ op = "setGold", gold = n })
		report(r, "Gold set to " .. tostring(n))
	end)
	setGold.LayoutOrder = 3
	setGold.Parent = goldRow

	-- マップイベント
	local eventRow: Frame = new("Frame", {
		LayoutOrder = 3,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		[CHILDREN] = {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = panel,
	})
	local raid = plainButton("Force Raid", C.warnDark, 194, function()
		report(call({ op = "forceEvent", kind = "raid" }), "Raid Boss appeared (3:00)")
	end)
	raid.LayoutOrder = 1
	raid.Parent = eventRow
	local rare = plainButton("Force Rare Dungeon", C.specialPurple, 194, function()
		report(call({ op = "forceEvent", kind = "rareDungeon" }), "Rare Dungeon appeared (3:00)")
	end)
	rare.LayoutOrder = 2
	rare.Parent = eventRow

	-- 自分のデータの初期化（2回押す）
	local armedUntil = 0
	local reset: TextButton
	reset = plainButton("Reset My Data", C.warn, PANEL_W - 36, function()
		if os.clock() > armedUntil then
			armedUntil = os.clock() + RESET_CONFIRM_SECONDS
			reset.Text = "Tap again to reset"
			task.delay(RESET_CONFIRM_SECONDS, function()
				if os.clock() >= armedUntil then
					reset.Text = "Reset My Data"
				end
			end)
			return
		end
		armedUntil = 0
		reset.Text = "Reset My Data"
		local r = call({ op = "resetData" })
		report(r, "Data reset")
		if type(r) == "table" and r.ok and r.result then
			box.Text = tostring(r.result.gold)
		end
	end)
	reset.LayoutOrder = 4
	reset.Parent = panel

	open.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			local r = call({ op = "hello" })
			if type(r) == "table" and r.ok and r.result and r.result.gold then
				box.Text = tostring(r.result.gold)
			end
			say("")
		end
	end)
end

return AdminTool
