--!strict
-- 同じサーバーにいる友達の数（D-157、11章 §2.1）
-- core の ClaimFriendReward は ctx.friendCount を読む。その数をサーバーで数える。
--
-- - 2人の組ごとに、友達かどうかを1回だけ Roblox に問い合わせて覚える（Player:IsFriendsWithAsync）。
--   友達の関係は対称なので、組の鍵は小さい UserId と大きい UserId をつないだもの。
-- - 人の出入りで数え直す：入ったら、その人と今いる全員の組を問い合わせる。出たら、その人の組を忘れる。
-- - 問い合わせに失敗した組は覚えず、次の出入りのときにもう一度問い合わせる（それまでは友達でないとして数える）。
-- - count は覚えた結果を数えるだけで、待ちを入れない（コマンドの処理中に呼ぶため）。

local Players = game:GetService("Players")

local FriendCounter = {}
FriendCounter.__index = FriendCounter

local function pairKey(a: number, b: number): string
	if a < b then
		return `{a}:{b}`
	end
	return `{b}:{a}`
end

function FriendCounter.new()
	local self = setmetatable({}, FriendCounter)
	self.known = {} :: { [string]: boolean } -- 組の鍵 → 友達か
	self.asking = {} :: { [string]: boolean } -- 問い合わせ中の組（同じ組を重ねて問い合わせない）
	return self
end

-- 友達かを問い合わせる。Roblox API の呼び出しはここだけ。
-- Player:IsFriendsWith は非推奨になり IsFriendsWithAsync に置き換わった（Player の API リファレンスで確認、2026-11）。
-- 結果は Roblox 側でもキャッシュされる。
local function askFriends(player: Player, otherUserId: number): (boolean, boolean)
	local ok, result = pcall(function()
		return (player :: any):IsFriendsWithAsync(otherUserId)
	end)
	if not ok then
		warn(`[FriendCounter] 友達の問い合わせに失敗（{player.UserId}・{otherUserId}）：{result}`)
		return false, false
	end
	return true, result == true
end

-- まだ覚えていない組を問い合わせる（問い合わせは別の処理で行うので、呼んだ側は待たない）。
-- leavingUserId：出ていく途中の人（PlayerRemoving の間はまだ一覧に残るので除く）
function FriendCounter.refresh(self: any, leavingUserId: number?)
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.UserId ~= leavingUserId then
			table.insert(list, p)
		end
	end
	for i = 1, #list do
		for j = i + 1, #list do
			local a, b = list[i], list[j]
			local key = pairKey(a.UserId, b.UserId)
			if self.known[key] == nil and not self.asking[key] then
				self.asking[key] = true
				task.spawn(function()
					local ok, isFriend = askFriends(a, b.UserId)
					self.asking[key] = nil
					-- 問い合わせの間にどちらかが出ていたら覚えない（出たときに忘れた組を戻さない）
					if ok and a.Parent == Players and b.Parent == Players then
						self.known[key] = isFriend
					end
				end)
			end
		end
	end
end

function FriendCounter.onPlayerAdded(self: any, _player: Player)
	self:refresh()
end

-- 出た人の組を忘れる。失敗していた組は、残った人どうしでもう一度問い合わせる
function FriendCounter.onPlayerRemoving(self: any, player: Player)
	local prefix = `{player.UserId}:`
	local suffix = `:{player.UserId}`
	for key in self.known do
		if string.sub(key, 1, #prefix) == prefix or string.sub(key, -#suffix) == suffix then
			self.known[key] = nil
		end
	end
	self:refresh(player.UserId)
end

-- userId の人と同じサーバーにいる友達の数（覚えた結果だけを数える。待ちを入れない）
function FriendCounter.count(self: any, userId: number): number
	local n = 0
	for _, other in Players:GetPlayers() do
		if other.UserId ~= userId and self.known[pairKey(userId, other.UserId)] == true then
			n += 1
		end
	end
	return n
end

return FriendCounter
