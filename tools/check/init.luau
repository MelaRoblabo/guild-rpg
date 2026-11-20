--!strict
-- まとめて確認する：StyLua（整形チェック）→ selene → マスターデータ検証 → 全テスト
-- 使い方: lune run tools/check

local process = require("@lune/process")

local MasterData = require("../../src/core/MasterData")
local Data = require("../../src/data")

local TARGETS = { "src", "tools", "tests" }

local failed = false

local function step(name: string, cmd: string, args: { string })
	print(`\n== {name} ==`)
	local ok, result = pcall(process.spawn, cmd, args, { stdio = "inherit" })
	if not ok then
		print(`起動できません: {cmd}（rokit install を実行してください）`)
		failed = true
	elseif not result.ok then
		failed = true
	else
		print("OK")
	end
end

step("StyLua", "stylua", { "--check", table.unpack(TARGETS) })
step("selene", "selene", TARGETS)

print("\n== マスターデータ検証 ==")
local issues = MasterData.validate(Data)
if #issues > 0 then
	print(MasterData.formatIssues(issues))
end
local hasError = false
for _, i in issues do
	hasError = hasError or i.level == "error"
end
if hasError then
	failed = true
else
	print("OK")
end

step("テスト", "lune", { "run", "tools/test" })

print(if failed then "\n✗ check 失敗" else "\n✓ check 成功")
process.exit(if failed then 1 else 0)
