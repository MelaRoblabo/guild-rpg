--!strict
-- フレンドボタンと紹介（D-157, D-180, D-190, D-192, D-195、docs/system/06_formulas.md §20、05_commands.md ClaimFriendReward・GrantReferral）
--   Friend.claim          フレンドボタン。同じサーバーの友達の数（サーバーが数えて ctx.friendCount で渡す：M7b-5）でゴールドが少し増える。
--                         一定時間ごとに押せる（押さないとたまらない）・1日の上限あり。受け取り箱には入れず、その場で渡す
--   Friend.referralProgressReached  招待された人が紹介の進み具合（referralProgressCondition。転生回数の累計：D-195）に届いたか（D-192）。
--                         サーバーはこれを見て、招待した人へ届け物を書き（markInviterDelivered）、招待された側に GrantReferral（invitee）を実行する
--   Friend.grantReferral  紹介の報酬を受け取り箱へ入れる。招待された側は1回だけで、進み具合に届いてから（D-192）。
--                         招待した側は相手1人ごと・週の上限まで
--                         招待した側の報酬は「届け物」（別の保存場所。サーバーが M7b-5 で持つ）で届き、届け物の id を
--                         記録して二重に受け取らない（サーバーが保存してから届け物を消す間に落ちると、同じ届け物がもう一度来るため）
--   Friend.inviterDelivered / markInviterDelivered  招待された側の「招待した人へ届け物を書いた」印（同じ招待で2回届けない）
-- 日・週の区切りは Calendar（D-168）。状態を持たない（関数の集合）。

local Calendar = require("./Calendar")
local Chest = require("./Chest")
local Formulas = require("./Formulas")
local Inbox = require("./Inbox")
local Rng = require("./Rng")

local Friend = {}

function Friend.newState(): any
	return { nextAt = 0, dayIndex = -1, todayCount = 0 }
end

function Friend.newReferralState(): any
	return {
		inviteeRewardDone = false, -- 招待された側の報酬を渡したか（1回だけ）
		inviterDelivered = false, -- 招待された側：招待した人へ届け物を書いたか（同じ招待で2回届けない）
		rewardedInvitees = {}, -- 招待した側：報酬を渡した相手の UserId（文字列キー）
		claimedDeliveries = {}, -- 招待した側：受け取った届け物の id（二重に受け取らない）
		weekIndex = -1,
		weekCount = 0,
	}
end

-- 報酬のゴールド（06章 §20・§22、D-190）：人数は friendRewardMaxFriends まで。
-- 基準のダンジョン（踏破した一番深いダンジョン、なければ古い墓地：D-187）の rewardGoldBase に係数を掛ける
function Friend.gold(state: any, friendCount: number, master: any): number
	local K = master.K
	local n = math.min(math.floor(friendCount), K.friendRewardMaxFriends)
	if n < 1 then
		return 0
	end
	return Formulas.rewardGold(
		Chest.baseDungeon(state, master),
		K.friendRewardGoldMult * (1 + K.friendRewardBonusPerFriend * (n - 1)),
		K
	)
end

-- 押せるか。押せなければエラーコード
function Friend.blocker(state: any, now: number, friendCount: number, master: any): string?
	local F = state.friend
	if friendCount < 1 then
		return "NO_FRIEND"
	end
	local todayCount = if F.dayIndex == Calendar.dayIndex(now) then F.todayCount else 0
	if todayCount >= master.K.friendRewardDailyCap then
		return "DAILY_LIMIT"
	end
	if now < F.nextAt then
		return "FRIEND_NOT_READY"
	end
	return nil
end

-- フレンドボタンを押す。成功ならイベント、失敗ならエラーコード
function Friend.claim(state: any, now: number, friendCount: number, master: any): (any?, string?)
	local err = Friend.blocker(state, now, friendCount, master)
	if err then
		return nil, err
	end
	local F = state.friend
	local today = Calendar.dayIndex(now)
	if F.dayIndex ~= today then
		F.dayIndex = today
		F.todayCount = 0
	end
	F.todayCount += 1
	F.nextAt = now + master.K.friendRewardIntervalSeconds -- 押さないとたまらない（06章 §20）
	local gold = Friend.gold(state, friendCount, master)
	state.gold += gold
	return {
		type = "FriendReward",
		at = now,
		gold = gold,
		friendCount = math.min(math.floor(friendCount), master.K.friendRewardMaxFriends),
		nextAt = F.nextAt,
		todayCount = F.todayCount,
	},
		nil
end

-- 招待された人（この state の持ち主）が紹介の進み具合に届いたか（D-192, D-195。条件は Constants.referralProgressCondition）
--   kind = "rebirthsTotal"：これまでに転生した回数の累計（stats.rebirths。RebirthChoose で数える）が count 回以上。
--   今いる冒険者の rebirthCount では数えない（解雇で戻らない：D-195）
function Friend.referralProgressReached(state: any, master: any): boolean
	local cond = master.K.referralProgressCondition
	if cond.kind == "rebirthsTotal" then
		local stats = state.stats or {}
		return (stats.rebirths or 0) >= cond.count
	end
	return false -- 知らない条件（MasterData の検証で止めるので起きない）
end

-- 紹介の報酬を受け取り箱へ（source = "referral"）。成功ならイベント、失敗ならエラーコード
--   role = "invitee"：招待された側（1回だけ）。進み具合に届いていなければ PROGRESS_NOT_REACHED（D-192）
--   role = "inviter"：招待した側。userId は招待された人。deliveryId は届け物の id（同じ id は二度受け取らない）
function Friend.grantReferral(
	state: any,
	role: string,
	userId: number,
	deliveryId: string?,
	now: number,
	takeRng: () -> Rng.Rng,
	master: any
): (any?, string?)
	local R = state.referral
	local K = master.K
	if role == "invitee" then
		if R.inviteeRewardDone then
			return nil, "ALREADY_REWARDED"
		end
		if not Friend.referralProgressReached(state, master) then
			return nil, "PROGRESS_NOT_REACHED"
		end
		R.inviteeRewardDone = true
	elseif role == "inviter" then
		if deliveryId and R.claimedDeliveries[deliveryId] then
			return nil, "ALREADY_CLAIMED"
		end
		local key = tostring(userId)
		if R.rewardedInvitees[key] then
			return nil, "ALREADY_REWARDED"
		end
		local week = Calendar.weekIndex(now)
		if R.weekIndex ~= week then
			R.weekIndex = week
			R.weekCount = 0
		end
		if R.weekCount >= K.referralWeeklyCap then
			return nil, "WEEKLY_LIMIT"
		end
		R.weekCount += 1
		R.rewardedInvitees[key] = true
		if deliveryId then
			R.claimedDeliveries[deliveryId] = true
		end
	else
		return nil, "INVALID_ROLE"
	end
	local entry = Inbox.push(state, "referral", now, K.referralRewards[role], takeRng, master)
	return { type = "ReferralGranted", at = now, role = role, userId = userId, inboxUid = entry.uid }, nil
end

-- 招待された側：招待した人へ届け物を書いたか（書くきっかけの判定はサーバー：M7b-5）
function Friend.inviterDelivered(state: any): boolean
	return state.referral.inviterDelivered == true
end

-- 招待された側：招待した人へ届け物を書いた印を付ける。付けたら true（すでに付いていれば false）
function Friend.markInviterDelivered(state: any): boolean
	if state.referral.inviterDelivered then
		return false
	end
	state.referral.inviterDelivered = true
	return true
end

return Friend
