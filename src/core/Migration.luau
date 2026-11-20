--!strict
-- セーブデータの移行（docs/system/03_state_model.md）
-- 形式を変えたら CURRENT を上げ、STEPS[旧版] に旧版→新版の変換を追加する。

local Migration = {}

Migration.CURRENT = 1

local STEPS: { [number]: (any) -> () } = {
	-- [1] = function(state) ... state.version = 2 end,
}

function Migration.migrate(state: any): any
	assert(type(state) == "table" and type(state.version) == "number", "セーブデータに version がない")
	assert(state.version <= Migration.CURRENT, `未来の版のセーブデータ: {state.version}`)
	while state.version < Migration.CURRENT do
		local step = STEPS[state.version]
		assert(step, `移行手順がない: {state.version}`)
		step(state)
	end
	return state
end

return Migration
