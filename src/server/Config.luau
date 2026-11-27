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

	-- 管理者モード（D-306、src/server/Admin）。Studio のテストプレイのほか、ここに登録した UserId だけが使える。
	-- ServerScriptService にあるので端末からは見えない
	adminUserIds = {
		[3407099658] = true,
	} :: { [number]: boolean },

	-- サーバー権限・通信（M7-3 で使う）
	advanceIntervalSeconds = 1, -- 仮
	commandRateLimit = 10, -- 仮。1人あたり1秒の上限

	-- 紹介の届け物を書くきっかけ（D-157・D-180・D-192、11章 §3.7）
	referralRetrySeconds = 60, -- 仮。届け物を書けなかった（DataStore のエラー・箱がいっぱい）ときに次に試すまでの秒

	-- ゲーム外の通知（D-159・D-181、11章 §8）。Open Cloud の CreateUserNotification を HttpService で呼ぶ
	notifyEnabled = true, -- 仮。false なら予約も送信もしない
	notifySecretName = "OpenCloudApiKey", -- 仮。Creator Hub の Secrets に登録する API キーの名前（apis.roblox.com に結び付ける）
	notifyQueueName = "NotifyQueue_v1", -- 仮。送る予約（MemoryStore の SortedMap。鍵 = UserId、並びの鍵 = 送る時刻）
	notifySentMapName = "NotifySent_v1", -- 仮。最後に送った日（MemoryStore の HashMap。1人1日1通の判定）
	notifyPollSeconds = 30, -- 仮。送る時刻が来た予約を探す間隔
	notifyBatch = 20, -- 仮。1回に取り出す予約の数（GetRangeAsync の上限は 200）
	notifyMinAwaySeconds = 6 * 3600, -- 仮。退出からこれだけ空けた最初の「いつも遊ぶ時刻」に送る
	notifyQueueExpirationSeconds = 3 * 24 * 3600, -- 仮。予約の寿命（送られなかった予約は消える。上限 45 日）
	-- 登録した通知の文面の id（Creator Dashboard の Notification strings の asset id）。空なら、その種類は送らない（仮。公開前に登録する）
	-- 文面の差し込み名は count（宝箱の数・冒険者の数）だけ。launchData は "notify:<種類>"（M8 で画面へつなぐ）
	notifyMessageIds = {
		loginUnique = "", -- ① あと1日でログインボーナスのユニーク
		offlineDone = "", -- ② 全パーティ帰還・宝箱 {count} 個（留守番の終わり）
		dailyTrait = "", -- ③ 今日の日替わりが得意なダンジョン
		rebirthReady = "", -- ④ 転生できる冒険者 {count} 人
		dailyReset = "", -- ⑤ デイリー更新
	},
}
