--!strict
-- 最後に使った入力（D-139・D-218 ①）。ゲームパッドのときだけ、ボタンの角に A/B/X/Y の印を出す。

local UserInputService = game:GetService("UserInputService")

local Signal = require("./Signal")

local Input = {}

Input.changed = Signal.new() :: Signal.Signal<boolean>
Input.gamepad = false

local function isGamepad(t: Enum.UserInputType): boolean
	return t.Name:sub(1, 7) == "Gamepad"
end

local function set(gamepad: boolean)
	if Input.gamepad ~= gamepad then
		Input.gamepad = gamepad
		Input.changed:fire(gamepad)
	end
end

UserInputService.LastInputTypeChanged:Connect(function(t: Enum.UserInputType)
	if isGamepad(t) then
		set(true)
	elseif
		t == Enum.UserInputType.Touch
		or t == Enum.UserInputType.MouseButton1
		or t == Enum.UserInputType.MouseMovement
		or t == Enum.UserInputType.Keyboard
	then
		set(false)
	end
end)
set(isGamepad(UserInputService:GetLastInputType()))

return Input
