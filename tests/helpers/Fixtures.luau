--!strict
-- テスト用の部品

local Data = require("../../src/data")
local MasterData = require("../../src/core/MasterData")

local Fixtures = {}

local function clone(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = clone(x)
	end
	return out
end
Fixtures.clone = clone

-- 本番データ（必要なら mutate で上書き）
function Fixtures.master(mutate: ((any) -> ())?): any
	local d = clone(Data)
	if mutate then
		mutate(d)
	end
	return MasterData.load(d)
end

-- 戦闘テスト用のメンバー状態を直接作る
function Fixtures.snap(overrides: any): any
	local s = {
		uid = "u" .. tostring(overrides.slot or 1),
		slot = 1,
		jobId = "job_warrior",
		attackType = "physical",
		heals = false,
		maxHp = 100,
		atk = 10,
		pdef = 0,
		mdef = 0,
		agi = 10,
		dex = 0,
		mag = 0,
		tagAtkRates = {},
		tagGiftIds = {},
		healRate = 0,
		lucky = false,
		trapDexMult = 1,
		travel = {},
		expRate = 0,
		giftIds = {},
	}
	for k, v in overrides do
		s[k] = v
	end
	return s
end

function Fixtures.memberState(overrides: any, hp: number?): any
	local s = Fixtures.snap(overrides)
	return { slot = s.slot, snap = s, hp = hp or s.maxHp }
end

function Fixtures.monster(overrides: any?): any
	local m = { id = "mon_test", raceTag = "beast", attackType = "physical", hp = 100, atk = 10, pdef = 0, mdef = 0 }
	for k, v in overrides or {} do
		m[k] = v
	end
	return m
end

return Fixtures
