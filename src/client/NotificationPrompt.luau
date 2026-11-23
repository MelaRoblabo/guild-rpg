--!strict
-- 通知の許可を求める画面（D-159・D-181、11章 §8.4）
-- Roblox の許可の画面（ExperienceNotificationService:PromptOptIn）はクライアント専用の API なので、ここから出す。
-- 設定画面（S-61、D-181）と「嬉しい瞬間」（D-159。いつ出すかは未決）の両方から prompt を呼ぶ。M8 の画面はまだないので、
-- 今はデバッグ画面の notify コマンドから呼ぶ。
-- 13歳未満・最近出した（Roblox 側の間隔の制限）などで出せないときは CanPromptOptInAsync が false を返す。
-- API の名前は ExperienceNotificationService の API リファレンスで確認（2026-11）。

local ExperienceNotificationService = game:GetService("ExperienceNotificationService")

local NotificationPrompt = {}

-- 今、許可の画面を出せるか（待ちが入る）
function NotificationPrompt.canPrompt(): boolean
	local ok, result = pcall(function()
		return ExperienceNotificationService:CanPromptOptInAsync()
	end)
	return ok and result == true
end

-- 出せるなら許可の画面を出す。出したら true。閉じたときに onClosed を呼ぶ（任意）
function NotificationPrompt.prompt(onClosed: (() -> ())?): boolean
	if not NotificationPrompt.canPrompt() then
		return false
	end
	if onClosed then
		local conn: RBXScriptConnection
		conn = ExperienceNotificationService.OptInPromptClosed:Connect(function()
			conn:Disconnect()
			onClosed()
		end)
	end
	local ok, err = pcall(function()
		ExperienceNotificationService:PromptOptIn()
	end)
	if not ok then
		warn(`[NotificationPrompt] 許可の画面を出せなかった：{err}`)
		return false
	end
	return true
end

return NotificationPrompt
