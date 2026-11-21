--!strict
-- セーブデータの移行（docs/system/03_state_model.md）
-- 形式を変えたら CURRENT を上げ、STEPS[旧版] に旧版→新版の変換を追加する。

local Migration = {}

Migration.CURRENT = 4

local STEPS: { [number]: (any) -> () } = {
	-- [1] = function(state) ... state.version = 2 end,
	-- v1 → v2：トレーニング場（D-077）と解錠技術（D-078）
	[1] = function(state)
		state.expansions.trainingLevel = state.expansions.trainingLevel or 1
		state.expansions.unlockRank = state.expansions.unlockRank or 2
		state.version = 2
	end,
	-- v2 → v3：宝箱を「ダンジョン×ランクの数」で持つ（D-084）
	[2] = function(state)
		local counts = {}
		for _, c in state.chests do
			counts[c.dungeonId] = counts[c.dungeonId] or { 0, 0, 0, 0, 0 }
			counts[c.dungeonId][c.rank] += 1
		end
		state.chests = counts
		state.version = 3
	end,
	-- v3 → v4：解錠技術をダンジョン単位に（D-088）。旧ランクの上限を近い難度に置き換える
	[3] = function(state)
		local ex = state.expansions
		if ex then
			ex.unlockTier = math.max(2, 2 * ((ex.unlockRank or 2) - 1))
			ex.unlockRank = nil
		end
		state.version = 4
	end,
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
