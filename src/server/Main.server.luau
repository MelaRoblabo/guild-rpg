--!strict
-- サーバーの入口（11章 §2・§3）

local Players = game:GetService("Players")

-- 3D マップの画面だけを見るゲームなので、アバターは出さない（D-270。カメラは MapCamera が動かす）
Players.CharacterAutoLoads = false

local Data = require("@game/ReplicatedStorage/Data")
local MasterData = require("@game/ReplicatedStorage/Core/MasterData")
local Config = require("./Config")
local Network = require("./Network")
local Notifications = require("./Notifications")
local PlayerSessions = require("./PlayerSessions")

-- マスターデータは起動時に1回だけ読み込む。検証に失敗したらプレイヤーを受け付けない（11章 §2）
local ok, masterOrErr = pcall(MasterData.load, Data)
if not ok then
	warn(`[Main] マスターデータの検証に失敗：{masterOrErr}`)
	local function reject(player: Player)
		player:Kick(
			"サーバーの準備に失敗しました。しばらくしてから入り直してください。"
		)
	end
	Players.PlayerAdded:Connect(reject)
	for _, p in Players:GetPlayers() do
		reject(p)
	end
	return
end

local sessions = PlayerSessions.new(masterOrErr)
local notifications = Notifications.new(masterOrErr)
-- 通信は参加の受け付けより先に用意する（読み込み完了時に全体を通知するため）
Network.start(sessions)
notifications:start()

local function onPlayerAdded(player: Player)
	sessions.friends:onPlayerAdded(player) -- 友達の数え直し（D-157）
	task.spawn(notifications.cancel, notifications, player.UserId) -- 遊んでいる人には通知を送らない（D-159）
	sessions:onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerRemoving:Connect(function(player)
	sessions.friends:onPlayerRemoving(player) -- 友達の数え直し（D-157）
	-- 退出したセッションから通知を予約する（D-159）。読み込みが終わっていなければ予約しない
	local session = sessions:get(player)
	if session then
		task.spawn(notifications.schedule, notifications, session)
	end
	sessions:onPlayerRemoving(player)
end)
game:BindToClose(function()
	sessions:saveAll()
end)

task.spawn(function()
	while true do
		task.wait(Config.autosaveSeconds)
		sessions:autosave()
	end
end)
