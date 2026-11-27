--!strict
-- 値の上書き（MB）：src/data を書き換えずに、読み込んだデータの値だけを変えて試す
--   --set Constants.expCycleMult=1.2
--   --set Dungeons.dng_ruins.unlockGold=500        配列の中は id で探す
--   --set Quests.qst_daily_clear.rewards.goldMult=2
-- 値は数・true／false・それ以外は文字。上書きは MasterData の検証を通ってから使う（壊れた値はそこで止まる）

local Overrides = {}

export type Override = { path: string, value: any }

function Overrides.parse(text: string): Override
	local path, raw = string.match(text, "^([^=]+)=(.*)$")
	assert(path and raw, `--set は「パス=値」: {text}`)
	local value: any = raw
	if tonumber(raw) ~= nil then
		value = tonumber(raw)
	elseif raw == "true" then
		value = true
	elseif raw == "false" then
		value = false
	end
	return { path = path, value = value }
end

local function child(node: any, key: string, path: string): any
	assert(type(node) == "table", `上書きのパスが表を指していない: {path}`)
	local n = tonumber(key)
	if n ~= nil and node[n] ~= nil then
		return n
	end
	if node[key] ~= nil then
		return key
	end
	-- 配列の中を id で探す
	for i, row in node do
		if type(row) == "table" and row.id == key then
			return i
		end
	end
	error(`上書きのパスが見つからない: {path}（{key}）`)
end

-- data（src/data の束）に上書きを当てる。元の値を返す（成績表に書くため）
function Overrides.apply(data: any, list: { Override }): { any }
	local before = {}
	for _, o in list do
		local keys = string.split(o.path, ".")
		local node = data
		for i = 1, #keys - 1 do
			node = node[child(node, keys[i], o.path)]
		end
		local last = keys[#keys]
		assert(type(node) == "table", `上書きのパスが表を指していない: {o.path}`)
		local k: any = tonumber(last) or last
		if node[k] == nil then
			-- 新しいキーは作らない（綴りの間違いで静かに効かないのを防ぐ）
			error(`上書きのパスが見つからない: {o.path}`)
		end
		table.insert(before, node[k])
		node[k] = o.value
	end
	return before
end

return Overrides
