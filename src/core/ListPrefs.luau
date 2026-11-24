--!strict
-- 一覧の並べ方と一括売却の上限（D-117・D-119・D-231 ⑮。05章 SetListPrefs）
--   前回選んだものをサーバーに保存する（設定と一緒に保存：D-117）。保存がなければ StarterSet.listPrefs の初期値。
--   ListPrefs.ADV_SORTS / WH_SORTS  並べ替えの種類（冒険者の一覧 S-40・倉庫 S-50）
--   ListPrefs.get   今の並べ方（保存と初期値を合わせたもの）
--   ListPrefs.set   コマンドの値で書き換える（エラーコードか nil）

local ListPrefs = {}

-- 冒険者の一覧（S-40）：Lv・攻撃力・最大HP・雇用順・転生回数
ListPrefs.ADV_SORTS = { "level", "attack", "maxHp", "hired", "rebirths" }
-- 倉庫（S-50）：レアリティ・性能・売却額・新しい順
ListPrefs.WH_SORTS = { "rarity", "power", "sell", "new" }

local function has(list: { string }, v: any): boolean
	return table.find(list, v) ~= nil
end

function ListPrefs.get(state: any, master: any): any
	local d = master.raw.StarterSet.listPrefs
	local s = (state.settings and state.settings.listPrefs) or {}
	return {
		advSort = if has(ListPrefs.ADV_SORTS, s.advSort) then s.advSort else d.advSort,
		advDesc = if type(s.advDesc) == "boolean" then s.advDesc else d.advDesc,
		whSort = if has(ListPrefs.WH_SORTS, s.whSort) then s.whSort else d.whSort,
		whDesc = if type(s.whDesc) == "boolean" then s.whDesc else d.whDesc,
		bulkSellMaxRarity = if type(s.bulkSellMaxRarity) == "number" then s.bulkSellMaxRarity else d.bulkSellMaxRarity,
	}
end

-- 送られた項目だけを変える（省いた項目は今のまま）
function ListPrefs.set(state: any, cmd: any, master: any): string?
	if cmd.advSort ~= nil and not has(ListPrefs.ADV_SORTS, cmd.advSort) then
		return "INVALID_SORT"
	end
	if cmd.whSort ~= nil and not has(ListPrefs.WH_SORTS, cmd.whSort) then
		return "INVALID_SORT"
	end
	local r = cmd.bulkSellMaxRarity
	if r ~= nil and (type(r) ~= "number" or r ~= math.floor(r) or r < 1 or r > master.rarityCount) then
		return "INVALID_RARITY"
	end
	local cur = ListPrefs.get(state, master)
	for _, key in { "advSort", "advDesc", "whSort", "whDesc", "bulkSellMaxRarity" } do
		if cmd[key] ~= nil then
			cur[key] = cmd[key]
		end
	end
	state.settings = state.settings or {}
	state.settings.listPrefs = cur
	return nil
end

return ListPrefs
