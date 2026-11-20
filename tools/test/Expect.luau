--!strict
-- expect(...) の実装

local Expect = {}

local function show(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

function Expect.expect(actual: any)
	local m = {}

	function m.toBe(expected: any)
		if actual ~= expected then
			error(`期待値 {show(expected)} / 実際 {show(actual)}`, 2)
		end
	end

	function m.toEqual(expected: any)
		if not deepEqual(actual, expected) then
			error("深い比較で一致しない", 2)
		end
	end

	function m.toBeCloseTo(expected: number, eps: number?)
		local e = eps or 1e-9
		if type(actual) ~= "number" or math.abs(actual - expected) > e then
			error(`期待値 {expected} ± {e} / 実際 {show(actual)}`, 2)
		end
	end

	function m.toBeTruthy()
		if not actual then
			error(`真の値を期待 / 実際 {show(actual)}`, 2)
		end
	end

	function m.toBeFalsy()
		if actual then
			error(`偽の値を期待 / 実際 {show(actual)}`, 2)
		end
	end

	function m.toBeBetween(min: number, max: number)
		if type(actual) ~= "number" or actual < min or actual > max then
			error(`{min}〜{max} を期待 / 実際 {show(actual)}`, 2)
		end
	end

	-- actual は関数。呼ぶとエラーになり、メッセージに pattern を含むこと
	function m.toThrow(pattern: string?)
		local ok, err = pcall(actual)
		if ok then
			error("エラーを期待したが成功した", 2)
		end
		if pattern and not string.find(tostring(err), pattern, 1, true) then
			error(`エラーメッセージに "{pattern}" を期待 / 実際 {tostring(err)}`, 2)
		end
	end

	return m
end

return Expect
