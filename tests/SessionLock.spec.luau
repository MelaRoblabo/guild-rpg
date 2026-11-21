--!strict
local SessionLock = require("../src/server/SessionLock")

local ME = "job-me"
local OTHER = "job-other"
local PLACE = 114621179717387
local TIMEOUT = 600
local NOW = 1_000_000

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("D-099 読み込み時のロック", function()
		it("D-099 記録がなければ取る（新規プレイヤー）", function()
			local r, d = SessionLock.acquire(nil, ME, PLACE, NOW, TIMEOUT)
			expect(d).toBe("take")
			expect(r).toEqual({ state = nil, session = { jobId = ME, placeId = PLACE, at = NOW }, savedAt = nil })
		end)
		it("D-099 ロックがなければ取り、state はそのまま残す", function()
			local rec = { state = { gold = 5 }, savedAt = 10 }
			local r, d = SessionLock.acquire(rec, ME, PLACE, NOW, TIMEOUT)
			expect(d).toBe("take")
			expect((r :: any).state).toEqual({ gold = 5 })
			expect((r :: any).savedAt).toBe(10)
			expect((r :: any).session.jobId).toBe(ME)
		end)
		it("D-099 自分のロックなら取り直す（時刻を更新）", function()
			local rec = { state = {}, session = { jobId = ME, placeId = PLACE, at = NOW - 30 } }
			local r, d = SessionLock.acquire(rec, ME, PLACE, NOW, TIMEOUT)
			expect(d).toBe("take")
			expect((r :: any).session.at).toBe(NOW)
		end)
		it("D-099 他のサーバーの有効なロックなら待つ（書き換えない）", function()
			local rec = { state = {}, session = { jobId = OTHER, placeId = PLACE, at = NOW - (TIMEOUT - 1) } }
			local r, d = SessionLock.acquire(rec, ME, PLACE, NOW, TIMEOUT)
			expect(d).toBe("wait")
			expect(r).toBe(nil)
		end)
		it("D-099 他のサーバーのロックでも期限切れなら取る（落ちたサーバー）", function()
			local rec = { state = { gold = 1 }, session = { jobId = OTHER, placeId = PLACE, at = NOW - TIMEOUT } }
			local r, d = SessionLock.acquire(rec, ME, PLACE, NOW, TIMEOUT)
			expect(d).toBe("take")
			expect((r :: any).session.jobId).toBe(ME)
			expect((r :: any).state).toEqual({ gold = 1 })
		end)
	end)

	describe("D-099 保存時のロック確認", function()
		it("D-099 自分のロックなら保存し、ロックの時刻を更新する", function()
			local rec = { state = { gold = 1 }, session = { jobId = ME, placeId = PLACE, at = NOW - 60 } }
			local r, ok = SessionLock.prepareSave(rec, ME, PLACE, { gold = 2 }, NOW, false)
			expect(ok).toBe(true)
			expect(r).toEqual({
				state = { gold = 2 },
				session = { jobId = ME, placeId = PLACE, at = NOW },
				savedAt = NOW,
			})
		end)
		it("D-099 退出時は保存してロックを解放する", function()
			local rec = { state = {}, session = { jobId = ME, placeId = PLACE, at = NOW - 60 } }
			local r, ok = SessionLock.prepareSave(rec, ME, PLACE, { gold = 3 }, NOW, true)
			expect(ok).toBe(true)
			expect((r :: any).session).toBe(nil)
			expect((r :: any).state).toEqual({ gold = 3 })
		end)
		it("D-099 ロックを失っていたら書かない（二重ログインでの上書き防止）", function()
			local rec = { state = { gold = 9 }, session = { jobId = OTHER, placeId = PLACE, at = NOW } }
			local r, ok = SessionLock.prepareSave(rec, ME, PLACE, { gold = 1 }, NOW, false)
			expect(ok).toBe(false)
			expect(r).toBe(nil)
		end)
		it("D-099 ロックが解放済み・記録がない場合も書かない", function()
			expect(SessionLock.canSave({ state = {} }, ME)).toBe(false)
			expect(SessionLock.canSave(nil, ME)).toBe(false)
		end)
	end)
end
