--!strict
-- 拡張（S-22、D-071・D-209・D-231 ①⑤・D-237 ①）の見せ方。純粋な関数（Lune でテストする）。
--   行ごとに、買った段／全段、次の段、解放の条件（ギルドLv・踏破）とお金が足りるか。
--   条件もお金も足りないときは両方を返す（D-237 ①）。買えるものが1つでもあれば広間の入口に NEW（§5.1）。
--   押せないときの理由の1行（blockReason：D-264 ②）。

local Words = require("../ui/Words")

export type Row = {
	id: string,
	kind: string,
	bought: number, -- 買った段の数
	total: number, -- 全段の数
	current: number, -- 今の値
	step: any?, -- 次の段（nil＝全部買った）
	needLevel: number?, -- 足りないギルドLv
	needClear: string?, -- 踏破が要るダンジョン
	shortGold: boolean, -- お金が足りない
	canBuy: boolean,
}

local ExpandInfo = {}

-- 行の短い語（D-231 ⑤：アイコンだけでは見分けにくいので語を添える）
ExpandInfo.WORD = {
	partySlots = "Party slots",
	candidateSlots = "Candidates",
	rosterSize = "Roster",
	warehouseSize = "Storage",
	trainingLevel = "Training",
}

function ExpandInfo.rows(state: any, master: any): { Row }
	local out: { Row } = {}
	for _, e in master.raw.Expansions do
		local current = state.expansions[e.kind]
		local bought = 0
		for _, s in e.steps do
			if s.value <= current then
				bought += 1
			end
		end
		local step = e.steps[bought + 1]
		local needLevel = if step and state.guild.level < step.guildLevel then step.guildLevel else nil
		local needClear = if step
				and step.requiresClear
				and not state.clearedDungeons[step.requiresClear]
			then step.requiresClear
			else nil
		local shortGold = step ~= nil and state.gold < step.gold
		table.insert(out, {
			id = e.id,
			kind = e.kind,
			bought = bought,
			total = #e.steps,
			current = current,
			step = step,
			needLevel = needLevel,
			needClear = needClear,
			shortGold = shortGold,
			canBuy = step ~= nil and needLevel == nil and needClear == nil and not shortGold,
		})
	end
	return out
end

-- 押せない理由（1行・12語まで：D-264 ②）。何をすれば押せるかを言う。
--   条件（ギルドLv・踏破）を先に、両方足りなければ両方。条件を満たしてお金だけ足りなければ Not enough gold。
--   全部買ったら Fully expanded。買えるなら nil
function ExpandInfo.blockReason(row: Row, master: any): string?
	if row.step == nil then
		return Words.reason.fullyExpanded
	end
	local d = if row.needClear then master.dungeons[row.needClear] else nil
	local dungeonName = if d then d.nameEn else row.needClear
	if row.needLevel and dungeonName then
		return string.format(Words.reason.expandNeedBoth, row.needLevel, dungeonName)
	elseif row.needLevel then
		return string.format(Words.reason.expandNeedLevel, row.needLevel)
	elseif dungeonName then
		return string.format(Words.reason.expandNeedClear, dungeonName)
	elseif row.shortGold then
		return Words.reason.notEnoughGold
	end
	return nil
end

function ExpandInfo.anyBuyable(state: any, master: any): boolean
	for _, r in ExpandInfo.rows(state, master) do
		if r.canBuy then
			return true
		end
	end
	return false
end

return ExpandInfo
