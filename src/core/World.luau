--!strict
-- 他のプレイヤーに見せる公開情報（D-027・D-108・D-121・D-151、11章（システム）§6）。状態を持たない（関数の集合）。
--   World.publicInfo：馬車の位置を描くための1人分（WorldChanged で送る）。探索中のパーティだけ。
--     { userId, guildLevel, parties = { { index, dungeonId, departAt, travelSeconds, totalSeconds } } }
--     位置はクライアントが出発時刻と時間から求める（D-026）。探索ログ・宝箱・HP などは含めない。
--   World.inspect：馬車を触ったときの詳細（Inspect の返事）。そのパーティのメンバーの name・jobId・level・appearanceId とギルドLv。
--     探索中でなければ nil（NOT_FOUND）。
--   World.same：前に送った公開情報と同じか（変わったときだけ送る）。

local World = {}

export type PublicParty = {
	index: number,
	dungeonId: string,
	departAt: number,
	travelSeconds: number,
	totalSeconds: number,
}

export type PublicInfo = { userId: number, guildLevel: number, parties: { PublicParty } }

local function exploring(state: any, partyIndex: number, now: number): any?
	for _, e in state.expeditions or {} do
		if e.partyIndex == partyIndex and not e.collected and e.log and now < e.departAt + e.log.totalSeconds then
			return e
		end
	end
	return nil
end

function World.publicInfo(state: any, userId: number, now: number): PublicInfo
	local parties: { PublicParty } = {}
	for _, party in state.parties or {} do
		local e = exploring(state, party.index, now)
		if e then
			table.insert(parties, {
				index = party.index,
				dungeonId = e.dungeonId,
				departAt = e.departAt,
				travelSeconds = e.log.travelSeconds,
				totalSeconds = e.log.totalSeconds,
			})
		end
	end
	table.sort(parties, function(a, b)
		return a.index < b.index
	end)
	return { userId = userId, guildLevel = state.guild.level, parties = parties }
end

function World.same(a: PublicInfo?, b: PublicInfo?): boolean
	if a == nil or b == nil then
		return a == b
	end
	if a.guildLevel ~= b.guildLevel or #a.parties ~= #b.parties then
		return false
	end
	for i, p in a.parties do
		local q = b.parties[i]
		if
			p.index ~= q.index
			or p.dungeonId ~= q.dungeonId
			or p.departAt ~= q.departAt
			or p.totalSeconds ~= q.totalSeconds
			or p.travelSeconds ~= q.travelSeconds
		then
			return false
		end
	end
	return true
end

function World.inspect(state: any, partyIndex: number, now: number): any?
	local e = exploring(state, partyIndex, now)
	if e == nil then
		return nil
	end
	-- 出発したときのメンバー（探索中は編成を変えられない：05章 §5）
	local members = {}
	for _, uid in e.memberUids or {} do
		local a = state.adventurers[uid]
		if a then
			table.insert(members, { name = a.name, jobId = a.jobId, level = a.level, appearanceId = a.appearanceId })
		end
	end
	return {
		guildLevel = state.guild.level,
		partyIndex = partyIndex,
		dungeonId = e.dungeonId,
		departAt = e.departAt,
		travelSeconds = e.log.travelSeconds,
		totalSeconds = e.log.totalSeconds,
		members = members,
	}
end

return World
