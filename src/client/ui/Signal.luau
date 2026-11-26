--!strict
-- 小さな通知の仕組み（D-227 ①：外部のライブラリは使わない）。純粋で、Lune でも動く。

local Signal = {}
Signal.__index = Signal

export type Connection = { disconnect: () -> () }
export type Signal<T...> = typeof(setmetatable({} :: { handlers: { [number]: (T...) -> () }, nextId: number }, Signal))

function Signal.new<T...>(): Signal<T...>
	return setmetatable({ handlers = {}, nextId = 0 }, Signal) :: any
end

function Signal.connect<T...>(self: Signal<T...>, fn: (T...) -> ()): Connection
	self.nextId += 1
	local id = self.nextId
	self.handlers[id] = fn
	return {
		disconnect = function()
			self.handlers[id] = nil
		end,
	}
end

function Signal.fire<T...>(self: Signal<T...>, ...: T...)
	-- 通知の途中で接続が増減しても安全なように、写してから呼ぶ
	local list = {}
	for id, fn in self.handlers do
		table.insert(list, { id = id, fn = fn })
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	for _, h in list do
		-- 通知の途中で外された接続は呼ばない（閉じた画面の描画を呼ばない）
		if self.handlers[h.id] == h.fn then
			-- 1つの受け手のエラーで、残りの受け手と送り手（コマンドの返事を待つ処理など）を止めない
			local ok, err = pcall(h.fn, ...)
			if not ok then
				print("[Signal] 受け手のエラー: " .. tostring(err))
			end
		end
	end
end

return Signal
