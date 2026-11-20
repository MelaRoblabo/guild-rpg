--!strict
-- 最小のテストランナー（docs/system/10_testing.md）
-- 使い方:
--   lune run tools/test                        全テスト
--   lune run tools/test Rng                    ファイル名で絞り込み
--   lune run tools/test --coverage-decisions   テスト名に出てこない決定IDを一覧

local fs = require("@lune/fs")
local process = require("@lune/process")

local Expect = require("./Expect")

local TESTS_DIR = "tests"

type TestCase = { name: string, fn: () -> () }

local args = {}
local coverage = false
for _, a in process.args do
	if a == "--coverage-decisions" then
		coverage = true
	elseif a ~= "--" then
		table.insert(args, a)
	end
end
local filter = args[1]

-- テストを集める
local cases: { TestCase } = {}
local prefixStack: { string } = {}

local function describe(name: string, fn: () -> ())
	table.insert(prefixStack, name)
	fn()
	table.remove(prefixStack)
end

local function it(name: string, fn: () -> ())
	local full = table.concat(prefixStack, " > ")
	full = if full == "" then name else full .. " > " .. name
	table.insert(cases, { name = full, fn = fn })
end

local api = { describe = describe, it = it, expect = Expect.expect }

local files = {}
for _, f in fs.readDir(TESTS_DIR) do
	if string.match(f, "%.spec%.luau$") and (filter == nil or string.find(f, filter, 1, true)) then
		table.insert(files, f)
	end
end
table.sort(files)

for _, f in files do
	local mod = (require :: any)("../../" .. TESTS_DIR .. "/" .. string.gsub(f, "%.luau$", ""))
	if type(mod) ~= "function" then
		error(`{f}: テストファイルは function(t) を返すこと`)
	end
	describe(string.gsub(f, "%.spec%.luau$", ""), function()
		mod(api)
	end)
end

-- 実行
local passed, failed = 0, 0
local failures = {}
for _, case in cases do
	local ok, err = pcall(case.fn)
	if ok then
		passed += 1
	else
		failed += 1
		table.insert(failures, { name = case.name, err = tostring(err) })
	end
end

for _, f in failures do
	print(`✗ {f.name}\n    {f.err}`)
end
print(`\n{passed} passed, {failed} failed ({#files} files)`)

-- 決定IDのカバレッジ
if coverage then
	local index = fs.readFile("docs/decisions/INDEX.md")
	local mentioned: { [string]: boolean } = {}
	for _, case in cases do
		for id in string.gmatch(case.name, "[DQ]%-%d%d%d") do
			mentioned[id] = true
		end
	end
	local missing = {}
	for id in string.gmatch(index, "\n%- ([DQ]%-%d%d%d)") do
		if not mentioned[id] then
			table.insert(missing, id)
		end
	end
	print(`\nテスト名に出てこない決定ID（{#missing}件）: {table.concat(missing, ", ")}`)
end

process.exit(if failed > 0 then 1 else 0)
