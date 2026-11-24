--!strict
-- 探索ウィンドウ S-11 の再生（D-001・D-026・D-115・D-213 ⑦・D-236）。純粋な関数（Lune でテストする）。
--   探索ログ（core の Expedition.simulate の結果）と今の時刻から、見せる中身を作る。
--   - 戦闘のフロア：1ターン replaySecondsPerTurn 秒。そのターンの行動（与えたダメージ・回復）と被弾を当てた後の HP、
--     モンスターの HP の割合（D-236 ①）。
--   - イベントのフロア：イベントの種類と、フロアの前後の HP の差（罠・泉の増減：D-236 ③）。
--   - 帰り道：残り時間と持ち帰る宝箱の数（D-236 ④）。
--   メンバーは input.members の順（隊列順の詰め）。memberSlots[i] がその人の隊列番号（行動の slot・target と合わせる）。

local Replay = {}

export type State = {
	phase: string, -- outbound / floor / inbound / returned
	floorIndex: number?,
	kind: string?, -- battle / event
	floor: number?, -- フロアの番号
	floors: number, -- 全フロア数（ログに残ったフロアの数ではなくダンジョンの数は呼び出し側）
	monsterId: string?,
	monsterRatio: number?, -- モンスターの HP の割合（0〜1）
	turn: number?, -- 今のターン（1〜）
	actions: { any }, -- 今のターンの行動（kind・slot・amount・crit・target）
	hit: { index: number, amount: number }?, -- 今のターンの被弾
	event: string?, -- イベントの種類
	deltas: { { index: number, amount: number } }, -- イベントの HP の増減
	hp: { number }, -- メンバーの今の HP
	chests: number, -- ここまでに確保した宝箱
	remaining: number, -- 帰還までの秒
}

local function indexOfSlot(memberSlots: { number }, slot: number?): number?
	if slot == nil then
		return nil
	end
	return table.find(memberSlots, slot)
end

-- 確保した宝箱の数（終わったフロアの gained の範囲の合計）
local function chestsBefore(log: any, uptoFloor: number): number
	local n = 0
	for i = 1, uptoFloor do
		local g = log.floors[i] and log.floors[i].gained
		if g and g.chestTo >= g.chestFrom then
			n += g.chestTo - g.chestFrom + 1
		end
	end
	return n
end

function Replay.at(log: any, memberSlots: { number }, maxHp: { number }, now: number, K: any): State
	local t = now - log.departAt
	local s: State = {
		phase = "outbound",
		floors = #log.floors,
		actions = {},
		deltas = {},
		hp = table.clone(maxHp),
		chests = 0,
		remaining = math.max(0, log.departAt + log.totalSeconds - now),
	}
	if t < log.travelSeconds then
		return s
	end
	local replayEnd = log.travelSeconds + log.replaySeconds
	if t >= replayEnd then
		local last = log.floors[#log.floors]
		s.phase = if t >= log.totalSeconds then "returned" else "inbound"
		s.hp = if last then table.clone(last.hpAfter) else s.hp
		s.chests = chestsBefore(log, #log.floors)
		return s
	end
	s.phase = "floor"
	for i, f in log.floors do
		if t < f.startOffset + f.duration then
			local prev = if i > 1 then log.floors[i - 1].hpAfter else maxHp
			s.floorIndex = i
			s.kind = f.kind
			s.floor = f.floor
			s.chests = chestsBefore(log, i - 1)
			local hp = table.clone(prev)
			if f.kind == "battle" and f.turns and #f.turns > 0 then
				local per = K.replaySecondsPerTurn
				local k = math.clamp(math.floor((t - f.startOffset) / per) + 1, 1, #f.turns)
				for j = 1, k do
					local turn = f.turns[j]
					for _, a in turn.actions do
						if a.kind == "heal" then
							local idx = indexOfSlot(memberSlots, a.target)
							if idx then
								hp[idx] = math.min(maxHp[idx] or hp[idx], hp[idx] + a.amount)
							end
						end
					end
					if turn.monster then
						local idx = indexOfSlot(memberSlots, turn.monster.target)
						if idx then
							hp[idx] = math.max(0, hp[idx] - turn.monster.amount)
						end
					end
				end
				local cur = f.turns[k]
				s.turn = k
				s.actions = cur.actions
				if cur.monster then
					local idx = indexOfSlot(memberSlots, cur.monster.target)
					if idx then
						s.hit = { index = idx, amount = cur.monster.amount }
					end
				end
				s.monsterId = f.monsterId
				local top = (f.monsterStats and f.monsterStats.hp) or 1
				s.monsterRatio = math.clamp(cur.monsterHp / math.max(1, top), 0, 1)
				-- 戦闘の終わりは記録どおりの HP にそろえる
				if k == #f.turns then
					hp = table.clone(f.hpAfter)
				end
			else
				s.event = f.event
				hp = table.clone(f.hpAfter)
				for idx, v in f.hpAfter do
					local d = v - (prev[idx] or v)
					if d ~= 0 then
						table.insert(s.deltas, { index = idx, amount = d })
					end
				end
				-- 宝箱は増える瞬間から数える
				local g = f.gained
				if g and g.chestTo >= g.chestFrom then
					s.chests += g.chestTo - g.chestFrom + 1
				end
			end
			s.hp = hp
			return s
		end
	end
	return s
end

return Replay
