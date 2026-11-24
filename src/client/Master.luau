--!strict
-- マスターデータ（クライアントで1回だけ読み込む）。表示用の計算と再生にだけ使う（11章 §1）

local MasterData = require("@game/ReplicatedStorage/Core/MasterData")
local Data = require("@game/ReplicatedStorage/Data")

return MasterData.load(Data)
