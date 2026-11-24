--!strict
-- 画面の重ね方（D-134・D-222）。純粋な状態だけを持ち、見た目は Nav（Roblox 側）が作る。
--   - メイン画面（T0）の上に、最大3段まで画面を重ねる。
--   - 右上の ×（ゲームパッドの B）で一段閉じる。ホームでメインへ戻る（全部閉じる）。
--   - 4段目を開こうとしたら、一番下の重ねた画面を閉じて入れ替える（段数を超えない）。

local NavStack = {}
NavStack.__index = NavStack

export type Entry = { id: string, params: any? }
export type Stack = typeof(setmetatable({} :: { entries: { Entry }, max: number }, NavStack))

local MAX_LAYERS = 3

function NavStack.new(max: number?): Stack
	return setmetatable({ entries = {}, max = max or MAX_LAYERS }, NavStack)
end

-- 画面を開く。閉じた画面（段数を超えて押し出したもの）を返す
function NavStack.push(self: Stack, id: string, params: any?): Entry?
	table.insert(self.entries, { id = id, params = params })
	if #self.entries > self.max then
		return table.remove(self.entries, 1)
	end
	return nil
end

-- 一段閉じる。閉じた画面を返す（重ねた画面がなければ nil）
function NavStack.pop(self: Stack): Entry?
	return table.remove(self.entries)
end

-- いま一番上の画面（なければメイン画面）
function NavStack.top(self: Stack): Entry?
	return self.entries[#self.entries]
end

-- 今の画面を別の画面に置き換える（雇用の a→b→c のように、流れの中で進むとき）
function NavStack.replace(self: Stack, id: string, params: any?)
	if #self.entries == 0 then
		table.insert(self.entries, { id = id, params = params })
	else
		self.entries[#self.entries] = { id = id, params = params }
	end
end

-- ホーム：全部閉じてメインへ。閉じた画面を上から順に返す
function NavStack.home(self: Stack): { Entry }
	local closed = {}
	while #self.entries > 0 do
		table.insert(closed, table.remove(self.entries) :: Entry)
	end
	return closed
end

function NavStack.depth(self: Stack): number
	return #self.entries
end

return NavStack
