--!strict
-- 紹介の届け物を書くきっかけ（D-157・D-180・D-192・D-195・D-197、11章 §3.7）
--
-- 1. 招待した人：参加したときの Player:GetJoinData().ReferredByPlayerId。新規のプレイヤー（初めての参加）のときだけ
--    state.referral.referredBy に入れる（03章。サーバーが入れる：D-195）。既存のプレイヤーが招待のリンクから入っても記録しない。
-- 2. 招待された人が一定の進み具合（転生回数の累計：D-195）に届いたら（Friend.referralProgressReached。core が判定する）、
--    a. 招待した人の届け物の箱に書く（Deliveries.push。id = "referral:<招待された人の UserId>"）。
--    b. 書けたら（"ok"・"duplicate"）、招待された人のセーブに「届けた」印（Friend.markInviterDelivered）を付け、
--       招待された人の報酬 GrantReferral（role = "invitee"）を実行する。
--    書けなかったら印を付けない。"error" なら Config.referralRetrySeconds 後にもう一度試す。
--    "full"（招待した人の箱がいっぱい）なら、そのセッションでは試し直さず、招待された人の次のログインで試す（D-197）。
-- 3. 印は次の保存で書かれる。書く前に落ちたら、次のログインでもう一度届け物を書く。同じ id なので、
--    招待した人がまだ受け取っていなければ "duplicate"、受け取り済みなら core の claimedDeliveries が二重の受け取りを防ぐ。
--    招待された人の報酬は inviteeRewardDone で1回だけ。
-- 招待した人の週の上限（referralWeeklyCap）を超えた届け物は、受け取る側で受け取れずに箱に残り、翌週に受け取る（D-192）。

local Friend = require("@game/ReplicatedStorage/Core/Friend")
local Game = require("@game/ReplicatedStorage/Core/Game")
local Config = require("./Config")

local Referral = {}

export type Hooks = {
	deliveries: any, -- Deliveries
	ctxFor: (session: any) -> any,
	-- 状態を変えたあと、クライアントに知らせる（Network の push）
	onChanged: (session: any, events: { any }) -> (),
	-- そのセッションがまだ有効か（退出・入れ替わりの確認）
	isCurrent: (session: any) -> boolean,
}

-- 招待された人が、招待した側へ届ける進み具合に届いたか（D-157・D-192。条件はマスターデータの referralProgressCondition）
local function progressReached(state: any, master: any): boolean
	return Friend.referralProgressReached(state, master)
end

-- 参加したときの招待した人（ReferredByPlayerId）。なければ nil。Roblox API の呼び出しはここだけ。
-- 名前は Player の API リファレンスで確認（GetJoinData の ReferredByPlayerId：「招待した人の UserId」）。
-- 招待がないときの値は書かれていない（要確認：nil か 0 か）。どちらでも、正の整数でなければ nil にする。
local function referredByOf(player: Player): number?
	local ok, data = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or type(data) ~= "table" then
		return nil
	end
	local id = (data :: any).ReferredByPlayerId
	if type(id) ~= "number" or id <= 0 or id ~= math.floor(id) or id == player.UserId then
		return nil
	end
	return id
end

-- 読み込み時（PlayerSessions.loadPlayer）：新規のプレイヤーなら招待した人を記録する。待ちを入れない
function Referral.recordOnLoad(player: Player, state: any, isNew: boolean)
	if not isNew or state.referral == nil or state.referral.referredBy ~= nil then
		return
	end
	local inviter = referredByOf(player)
	if inviter then
		state.referral.referredBy = inviter
	end
end

-- 届け物を書く必要があるか（待ちを入れない。コマンド・時間経過のたびに呼んでよい）
function Referral.needsDelivery(session: any, master: any, now: number): boolean
	local state = session.state
	local R = state.referral
	if R == nil or R.referredBy == nil or Friend.inviterDelivered(state) then
		return false
	end
	if session.referralBusy or now < (session.referralRetryAt or 0) then
		return false
	end
	return progressReached(state, master)
end

-- 届け物を書き、招待された人の報酬を渡す。別の処理（task.spawn）から呼ぶ（DataStore の待ちが入る）。
-- 状態を変える部分は、session.busy（コマンド・時間経過の順番）を取ってから行う。
function Referral.deliver(session: any, hooks: Hooks)
	if session.referralBusy then
		return
	end
	session.referralBusy = true
	local inviter = session.state.referral.referredBy
	local id = `referral:{session.userId}`
	local status = hooks.deliveries:push(inviter, id, "referral", session.userId)
	if status ~= "ok" and status ~= "duplicate" then
		warn(`[Referral] 届け物を書けなかった（{session.userId} → {inviter}、{status}）`)
		if status == "full" then
			-- 招待した人の箱がいっぱい：このセッションでは試し直さず、次のログインでもう一度試す（D-197）
			session.referralRetryAt = math.huge
		else
			-- 書き込みの失敗（error）：少し待って試し直す
			session.referralRetryAt = os.time() + Config.referralRetrySeconds
		end
		session.referralBusy = false
		return
	end

	while session.busy do
		task.wait()
	end
	if not hooks.isCurrent(session) then
		-- 退出した：印は付けない。次のログインでもう一度書く（同じ id なので二重にならない）
		session.referralBusy = false
		return
	end
	session.busy = true
	local ok, eventsOrErr = pcall(function()
		local state = session.state
		local events = {}
		if Friend.markInviterDelivered(state) then
			local r = Game.execute(
				state,
				{ type = "GrantReferral", role = "invitee", userId = inviter },
				hooks.ctxFor(session)
			)
			if r.ok then
				events = r.events or {}
			elseif r.error ~= "ALREADY_REWARDED" then
				warn(`[Referral] 招待された人の報酬を渡せなかった（{session.userId}、{r.error}）`)
			end
		end
		return events
	end)
	session.busy = false
	session.referralBusy = false
	if not ok then
		warn(`[Referral] 紹介の処理でエラー（{session.userId}）：{eventsOrErr}`)
		return
	end
	hooks.onChanged(session, eventsOrErr)
end

return Referral
