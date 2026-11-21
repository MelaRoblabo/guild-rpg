--!strict
-- サーバーの入口（11章 §2・§3）

local Players = game:GetService("Players")

local Data = require("@game/ReplicatedStorage/Data")
local MasterData = require("@game/ReplicatedStorage/Core/MasterData")
local Config = require("./Config")
local Network = require("./Network")
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
-- 通信は参加の受け付けより先に用意する（読み込み完了時に全体を通知するため）
Network.start(sessions)

Players.PlayerAdded:Connect(function(player)
	sessions:onPlayerAdded(player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(sessions.onPlayerAdded, sessions, player)
end
Players.PlayerRemoving:Connect(function(player)
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
