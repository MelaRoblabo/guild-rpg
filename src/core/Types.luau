--!strict
-- 共通の型（docs/system/03_state_model.md, 04_master_data.md）
-- M0 では基礎的な型のみ。各フェイズで必要な型を追加する。

export type StatKey = "str" | "mag" | "agi" | "dex" | "hp"

export type StatBlock = {
	str: number,
	mag: number,
	agi: number,
	dex: number,
	hp: number,
}

export type Range = { min: number, max: number }

export type WeightedId = { id: string, weight: number }

-- 検証結果（MasterData.validate）
export type ValidationIssue = {
	level: "error" | "warning",
	path: string, -- 例 "Constants.eventWeights"
	message: string,
}

local Types = {}

Types.STAT_KEYS = { "str", "mag", "agi", "dex", "hp" } :: { StatKey }

return Types
