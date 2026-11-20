--!strict
-- 決定的な乱数（docs/system/08_rng_time.md）
-- xoshiro128** を bit32 のみで実装する。Roblox の Random / math.random は使わない。
-- 32bit 同士の乗算は 16bit に分割して行い、倍精度の丸めによるずれを防ぐ。

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable(
	{} :: {
		s0: number,
		s1: number,
		s2: number,
		s3: number,
	},
	Rng
))

export type WeightedEntry = { id: string, weight: number }

local TWO_32 = 4294967296

local band = bit32.band
local bxor = bit32.bxor
local lshift = bit32.lshift
local rshift = bit32.rshift
local lrotate = bit32.lrotate

-- (a * b) mod 2^32 を正確に計算する
local function mul32(a: number, b: number): number
	local aHi, aLo = rshift(a, 16), band(a, 0xFFFF)
	local bHi, bLo = rshift(b, 16), band(b, 0xFFFF)
	local lo = aLo * bLo -- < 2^32
	local mid = (aHi * bLo + aLo * bHi) % 65536 -- 和は < 2^33 で倍精度で正確
	return (lo + mid * 65536) % TWO_32
end

local function add32(a: number, b: number): number
	return (a + b) % TWO_32
end

-- 32bit の値を攪拌する（murmur3 の fmix32）
local function fmix32(x: number): number
	x = bxor(x, rshift(x, 16))
	x = mul32(x, 0x85EBCA6B)
	x = bxor(x, rshift(x, 13))
	x = mul32(x, 0xC2B2AE35)
	x = bxor(x, rshift(x, 16))
	return x
end

local GOLDEN = 0x9E3779B9

-- splitmix32：状態を進めて出力を返す
local function splitmix32(state: number): (number, number)
	local nextState = add32(state, GOLDEN)
	return nextState, fmix32(nextState)
end

local function toU32(n: number): number
	-- 負数・小数・2^32 以上を 0..2^32-1 に正規化する
	n = math.floor(n)
	return n % TWO_32
end

function Rng.new(seed: number): Rng
	local state = toU32(seed)
	local s0, s1, s2, s3
	state, s0 = splitmix32(state)
	state, s1 = splitmix32(state)
	state, s2 = splitmix32(state)
	state, s3 = splitmix32(state)
	-- xoshiro は状態がすべて 0 だと動かない
	if s0 == 0 and s1 == 0 and s2 == 0 and s3 == 0 then
		s0 = 1
	end
	return setmetatable({ s0 = s0, s1 = s1, s2 = s2, s3 = s3 }, Rng)
end

-- 状態シードと回数から新しいシードを作る（08章 §2）
function Rng.derive(baseSeed: number, counter: number): number
	local a = fmix32(add32(toU32(baseSeed), GOLDEN))
	local b = fmix32(add32(toU32(counter), mul32(GOLDEN, 3)))
	return fmix32(bxor(a, b))
end

function Rng.nextU32(self: Rng): number
	local s0, s1, s2, s3 = self.s0, self.s1, self.s2, self.s3
	local result = mul32(lrotate(mul32(s1, 5), 7), 9)
	local t = lshift(s1, 9)
	s2 = bxor(s2, s0)
	s3 = bxor(s3, s1)
	s1 = bxor(s1, s2)
	s0 = bxor(s0, s3)
	s2 = bxor(s2, t)
	s3 = lrotate(s3, 11)
	self.s0, self.s1, self.s2, self.s3 = s0, s1, s2, s3
	return result
end

-- [0, 1)
function Rng.float(self: Rng): number
	return self:nextU32() / TWO_32
end

-- min 以上 max 以下の整数
function Rng.int(self: Rng, min: number, max: number): number
	assert(max >= min, "Rng.int: max < min")
	local span = max - min + 1
	return min + math.floor(self:float() * span)
end

function Rng.chance(self: Rng, p: number): boolean
	if p <= 0 then
		return false
	end
	if p >= 1 then
		-- 消費数を揃えるため、確定でも1回引く
		self:nextU32()
		return true
	end
	return self:float() < p
end

-- entries は配列（順序が結果に影響するため、辞書は使わない：04章）
function Rng.pickWeighted<T>(self: Rng, entries: { T }, weightOf: (T) -> number): T
	local total = 0
	for _, e in entries do
		total += weightOf(e)
	end
	assert(total > 0, "Rng.pickWeighted: total weight must be > 0")
	local r = self:float() * total
	local acc = 0
	for _, e in entries do
		acc += weightOf(e)
		if r < acc then
			return e
		end
	end
	return entries[#entries]
end

-- テスト用に内部関数を公開する
Rng._mul32 = mul32
Rng._fmix32 = fmix32

return Rng
