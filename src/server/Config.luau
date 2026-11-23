--!strict
-- サーバーの運用の値（11章 §1・§3・§4）。ゲームの数値ではないものだけを置く（ゲームの数値は src/data）。
-- （仮）の値は運用しながら調整する。

return {
	-- 保存（D-099）
	dataStoreName = "PlayerData_v1", -- 仮。形式を根本から変えるときだけ番号を上げる
	keyPrefix = "player_",
	autosaveSeconds = 60, -- 仮
	lockTimeoutSeconds = 600, -- 仮。これより古いロックは落ちたサーバーのものとみなす
	lockRetrySeconds = 5, -- 仮
	lockRetryCount = 6, -- 仮
	saveRetryCount = 3, -- 仮。待ち時間は 1・2・4 秒と倍にする
	saveSizeWarnBytes = 3000000, -- 仮。DataStore の上限は 4MB
	closeWaitSeconds = 25, -- サーバー終了時に保存を待つ上限（Roblox の BindToClose は最大30秒）

	-- 届け物（D-180、11章 §3.6）。プレイヤーのセーブとは別の DataStore に置く
	deliveryStoreName = "Deliveries_v1", -- 仮
	deliveryKeyPrefix = "delivery_",
	deliveryMaxItems = 100, -- 仮。1人の届け物の箱に置ける数の上限（DataStore の大きさの保護）

	-- サーバー権限・通信（M7-3 で使う）
	advanceIntervalSeconds = 1, -- 仮
	commandRateLimit = 10, -- 仮。1人あたり1秒の上限
}
