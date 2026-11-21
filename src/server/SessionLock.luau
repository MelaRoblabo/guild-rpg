--!strict
-- セッションロックの判定（11章 §3、D-099）
-- Roblox API を使わない純粋な関数。DataStore の UpdateAsync に渡す変換をここで作り、Lune でテストする。
--
-- 記録（DataStore の値）：{ state = PlayerState?, session = { jobId, placeId, at }?, savedAt = number? }

local SessionLock = {}

export type Session = { jobId: string, placeId: number, at: number }
export type Record = { state: any?, session: Session?, savedAt: number? }

-- 読み込み時に、このサーバーがロックを取れるか
--   "take"：記録がない・ロックがない・自分のロック・期限切れ（落ちたサーバー）
--   "wait"：他のサーバーが有効なロックを持っている
function SessionLock.decide(record: Record?, myJobId: string, now: number, timeout: number): "take" | "wait"
	if record == nil or record.session == nil then
		return "take"
	end
	local s = record.session :: Session
	if s.jobId == myJobId then
		return "take"
	end
	if now - s.at >= timeout then
		return "take"
	end
	return "wait"
end

-- 読み込み用の変換。ロックを取れるなら新しい記録（state はそのまま）を返す。取れなければ nil（UpdateAsync を中止）。
function SessionLock.acquire(
	record: Record?,
	myJobId: string,
	placeId: number,
	now: number,
	timeout: number
): (Record?, "take" | "wait")
	local decision = SessionLock.decide(record, myJobId, now, timeout)
	if decision == "wait" then
		return nil, decision
	end
	local r = record or {}
	return {
		state = r.state,
		session = { jobId = myJobId, placeId = placeId, at = now },
		savedAt = r.savedAt,
	},
		decision
end

-- 保存してよいか（記録のロックが自分のものか）
function SessionLock.canSave(record: Record?, myJobId: string): boolean
	return record ~= nil and record.session ~= nil and (record.session :: Session).jobId == myJobId
end

-- 保存用の変換。ロックが自分のものなら新しい記録を返す。release なら解放（session = nil）、そうでなければ at を更新。
-- ロックを失っていたら nil（書かない）と false を返す。
function SessionLock.prepareSave(
	record: Record?,
	myJobId: string,
	placeId: number,
	state: any,
	now: number,
	release: boolean
): (Record?, boolean)
	if not SessionLock.canSave(record, myJobId) then
		return nil, false
	end
	return {
		state = state,
		session = if release then nil else { jobId = myJobId, placeId = placeId, at = now },
		savedAt = now,
	},
		true
end

return SessionLock
