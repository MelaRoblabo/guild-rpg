--!strict
-- 通知の許可を求める画面（D-159・D-181・D-196、11章 §8.4）
-- Roblox の許可の画面（ExperienceNotificationService:PromptOptIn）はクライアント専用の API なので、ここから出す。
-- 出すきっかけ（D-196 ③）：初めての帰還。そこで許可しなかったらログインボーナス2日目にもう一度。
--   いつ出すかはサーバーが状態の要約の notifyPromptDue（"firstReturn" / "loginDay2" / nil。core の Notify.promptDue）で知らせる。
--   出したら（出せなかったときも）MarkNotifyPrompt で記録をサーバーに保存する（設定と一緒：D-117）。
--   2日目に許可済みかは CanPromptOptInAsync で確かめる（許可済み・13歳未満などなら出さずに記録だけ付ける）。
-- 設定画面（S-61、D-181）からも prompt を呼ぶ。M8 の画面はまだないので、今はデバッグ画面の notify コマンドから呼ぶ。
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

-- 処理中の機会（同じ機会で2回出さない。サーバーの記録が要約に届くまで持つ）
local pending: string? = nil

-- 状態の要約が変わるたびに呼ぶ。出す機会なら許可の画面を出し、記録をサーバーへ送る。
-- send はコマンドを送って結果を返す関数（失敗したら nil）、onResult は結果を知らせる（任意。デバッグ画面のログ用）
function NotificationPrompt.onView(view: any, send: (any) -> any?, onResult: ((string, boolean) -> ())?)
	local due = if view then view.notifyPromptDue else nil
	if pending ~= nil then
		if due ~= pending then
			pending = nil -- 記録が届いた（または別の機会になった）
		end
		return
	end
	if type(due) ~= "string" then
		return
	end
	pending = due
	task.spawn(function()
		local shown = NotificationPrompt.prompt()
		local r = send({ type = "MarkNotifyPrompt", stage = due })
		if not (r and r.ok) then
			pending = nil -- 送れなかった：次の要約の変化でもう一度
		end
		if onResult then
			onResult(due, shown)
		end
	end)
end

return NotificationPrompt
