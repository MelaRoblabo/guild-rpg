--!strict
-- S-61 設定（D-117・D-145・D-181・D-231 ⑧・D-237 ②③）。右上の歯車から開く羊皮紙のモーダル（後ろは幕 75%）。
--   - 左の列：Music・Sound の音量（棒を触った位置で 0〜volumeSteps。数字なし）、Chest opening、Less flashing。
--   - 右の列：Return alerts、Cut-ins、Other carts、Notifications。各行のアイコンの右に短い語（D-231 ⑧）。
--   - 押すとすぐ保存（SetSettings。サーバー：D-117）。Done ボタンはない。× は面の右上の角。
--   - 通知：出せるなら茶のボタン（押すと Roblox の許可の画面）、出せないとき（許可済み・30日の待ち・13歳未満）は
--     押せない色（D-237 ②。Roblox から理由は分からないので見分けない）。

local Game = require("@game/ReplicatedStorage/Core/Game")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Nav = require("../../ui/Nav")
local NotificationPrompt = require("../../NotificationPrompt")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local WarehouseCommon = require("../warehouse/WarehouseCommon")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local function build(_params: any?, api: Nav.Api): Nav.Built
	local frame: Frame = new("Frame", {
		Name = "Settings",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	local panel, content = Components.panel({
		size = UDim2.fromOffset(912, 446),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
	})
	panel.Name = "Panel"
	panel.Parent = frame
	local close = Components.closeButton(api.close)
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.ZIndex = 20
	close.Parent = panel
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = content,
	})
	local busy = false
	local canNotify: boolean? = nil
	local render: () -> ()

	local function send(cmd: any)
		busy = true
		Session.sendAndWait(cmd)
		busy = false
		render()
	end

	render = function()
		body:ClearAllChildren()
		local view = Session.view
		if view == nil then
			return
		end
		local p = Game.query.preferences(view, master)
		local steps = master.K.volumeSteps
		local cols: { Frame } = {}
		for i = 1, 2 do
			cols[i] = new("Frame", {
				Name = "Col" .. i,
				Position = UDim2.new((i - 1) * 0.5, if i == 2 then 12 else 0, 0, 0),
				Size = UDim2.new(0.5, -12, 0, 4 * 72 + 3 * 10 + 16),
				BackgroundColor3 = C.ch50,
				[CHILDREN] = {
					Components.corner(10),
					Components.padding(8, 8, 8, 8),
					new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
				},
				Parent = body,
			})
		end
		local function row(col: number, order: number, icon: string, word: string): Frame
			local r: Frame = new("Frame", {
				Name = "Row_" .. word,
				LayoutOrder = order,
				Size = UDim2.new(1, 0, 0, 72),
				BackgroundColor3 = C.ch75,
				[CHILDREN] = { Components.corner(6), Components.padding(0, 6, 0, 14) },
				Parent = cols[col],
			})
			local ic = Components.text({ text = icon, size = 28, color = C.inkDark, font = Tokens.font.number })
			ic.AnchorPoint = Vector2.new(0, 0.5)
			ic.Position = UDim2.fromScale(0, 0.5)
			ic.Parent = r
			local w = Components.text({ text = word, size = 22, color = C.inkDark, font = Tokens.font.bodyStrong })
			w.AnchorPoint = Vector2.new(0, 0.5)
			w.Position = UDim2.new(0, 46, 0.5, 0)
			w.Parent = r
			return r
		end
		local function switch(col: number, order: number, icon: string, word: string, key: string)
			local r = row(col, order, icon, word)
			local sw = WarehouseCommon.switch("Switch_" .. key, p[key], function()
				if not busy then
					send({ type = "SetSettings", [key] = not p[key] })
				end
			end)
			sw.AnchorPoint = Vector2.new(1, 0.5)
			sw.Position = UDim2.fromScale(1, 0.5)
			sw.Parent = r
		end
		local function slider(col: number, order: number, icon: string, word: string, key: string)
			local r = row(col, order, icon, word)
			local bar: TextButton = new("TextButton", {
				Name = "Slider_" .. key,
				Text = "",
				AutoButtonColor = false,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -6, 0.5, 0),
				Size = UDim2.fromOffset(170, 66),
				BackgroundTransparency = 1,
				Parent = r,
			})
			local track: Frame = new("Frame", {
				Name = "Track",
				Position = UDim2.fromOffset(0, 20),
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundColor3 = C.barTrack,
				[CHILDREN] = { Components.corner(8) },
				Parent = bar,
			})
			local ratio = p[key] / math.max(1, steps)
			new("Frame", {
				Name = "Fill",
				Position = UDim2.fromOffset(3, 3),
				Size = UDim2.new(ratio, -6, 1, -6),
				BackgroundColor3 = C.barFill,
				[CHILDREN] = { Components.corner(6) },
				Parent = track,
			})
			new("Frame", {
				Name = "Knob",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(ratio, 0.5),
				Size = UDim2.fromOffset(48, 48),
				BackgroundColor3 = C.ch75,
				ZIndex = 3,
				[CHILDREN] = { Components.corner(24), Components.stroke(C.bronze, 3) },
				Parent = bar,
			})
			-- 触った位置で段を決める
			bar.InputBegan:Connect(function(input)
				local t = input.UserInputType
				if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then
					return
				end
				local x = (input.Position.X - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X)
				local v = math.clamp(math.floor(x * steps + 0.5), 0, steps)
				if v ~= p[key] and not busy then
					send({ type = "SetSettings", [key] = v })
				end
			end)
		end
		slider(1, 1, "♪", "Music", "musicVolume")
		slider(1, 2, "🔊", "Sound", "soundVolume")
		switch(1, 3, "▣", "Chest opening", "chestAnimation")
		switch(1, 4, "⚡", "Less flashing", "lessFlashing")
		switch(2, 1, "💬", "Return alerts", "returnToast")
		switch(2, 2, "★", "Cut-ins", "cutIns")
		switch(2, 3, "▶", "Other carts", "otherCarts")
		local nr = row(2, 4, "🔔", "Notifications")
		local ok = canNotify == true
		local nb = Components.button({
			kind = if ok then "brown" else "disabled",
			width = 110,
			height = 66,
			icon = "🔔",
			name = "Notify",
			onClick = function()
				if ok then
					NotificationPrompt.prompt(function()
						canNotify = nil
						task.spawn(function()
							canNotify = NotificationPrompt.canPrompt()
							if body.Parent then
								render()
							end
						end)
					end)
				end
			end,
		})
		nb.AnchorPoint = Vector2.new(1, 0.5)
		nb.Position = UDim2.new(1, 0, 0.5, -3)
		nb.Parent = nr
	end

	render()
	-- 許可の画面を出せるかは待ちが入るので、あとで確かめて描き直す
	task.spawn(function()
		canNotify = NotificationPrompt.canPrompt()
		if body.Parent then
			render()
		end
	end)
	local conn = Session.changed:connect(function()
		if not busy then
			render()
		end
	end)
	return {
		frame = frame,
		destroy = function()
			conn.disconnect()
		end,
	}
end

Nav.register("Settings", build)

return {}
