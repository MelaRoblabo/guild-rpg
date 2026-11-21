--!strict
-- DataStore の読み書き（11章 §3、D-099）
-- ロックの判定は SessionLock（純粋な関数）に任せ、ここは DataStore の呼び出し・再試行・大きさの確認だけを行う。

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local Config = require("./Config")
local SessionLock = require("./SessionLock")

local Persistence = {}
Persistence.__index = Persistence

export type LoadStatus = "ok" | "locked" | "error"
export type SaveStatus = "ok" | "lost" | "error"

local function keyOf(userId: number): string
	return Config.keyPrefix .. tostring(userId)
end

local function waitForBudget()
	while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) < 1 do
		task.wait(1)
	end
end

-- UpdateAsync を再試行つきで呼ぶ。transform が nil を返すと書き込まない（Roblox の仕様）。
local function updateWithRetry(store: DataStore, key: string, transform: (any) -> any?): (boolean, string?)
	local waitSeconds = 1
	local lastError: string? = nil
	for attempt = 1, Config.saveRetryCount + 1 do
		waitForBudget()
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old: any)
				return transform(old)
			end)
		end)
		if ok then
			return true, nil
		end
		lastError = tostring(err)
		warn(`[Persistence] UpdateAsync 失敗（{key}、{attempt}回目）：{lastError}`)
		if attempt <= Config.saveRetryCount then
			task.wait(waitSeconds)
			waitSeconds *= 2
		end
	end
	return false, lastError
end

function Persistence.new(jobId: string, placeId: number)
	local self = setmetatable({}, Persistence)
	self.store = DataStoreService:GetDataStore(Config.dataStoreName)
	self.jobId = jobId
	self.placeId = placeId
	return self
end

-- 読み込み：ロックを取り、記録を返す。他のサーバーがロックを持っていれば待って再試行する。
-- 戻り値：("ok", 記録) / ("locked", nil) / ("error", nil, エラー文)
function Persistence.load(self: any, userId: number): (LoadStatus, any?, string?)
	local key = keyOf(userId)
	for _ = 1, Config.lockRetryCount do
		local decision: string? = nil
		local taken: any = nil
		local ok, err = updateWithRetry(self.store, key, function(old)
			local rec, d = SessionLock.acquire(old, self.jobId, self.placeId, os.time(), Config.lockTimeoutSeconds)
			decision = d
			taken = rec
			return rec
		end)
		if not ok then
			return "error", nil, err
		end
		if decision == "take" then
			return "ok", taken, nil
		end
		task.wait(Config.lockRetrySeconds)
	end
	return "locked", nil, nil
end

-- 保存：記録のロックが自分のものなら書く。release なら解放する。
-- 戻り値："ok" / "lost"（ロックを失っていた。書いていない） / "error"
function Persistence.save(self: any, userId: number, state: any, release: boolean): SaveStatus
	local key = keyOf(userId)
	if state ~= nil then
		local okSize, json = pcall(HttpService.JSONEncode, HttpService, state)
		if okSize and #json > Config.saveSizeWarnBytes then
			warn(`[Persistence] セーブデータが大きい（{key}：{#json} バイト）`)
		end
	end
	local lost = false
	local ok = updateWithRetry(self.store, key, function(old)
		local rec, can = SessionLock.prepareSave(old, self.jobId, self.placeId, state, os.time(), release)
		lost = not can
		return rec
	end)
	if not ok then
		return "error"
	end
	return if lost then "lost" else "ok"
end

return Persistence
