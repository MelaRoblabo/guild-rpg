--!strict
-- レイドボス（まず自分専用。D-152, D-164, D-179、docs/system/06_formulas.md §12、07章 §4b）
--   その時間帯の3分間に出発したパーティのダメージ（出発時に計算）を、到着時刻（出発 + raidTravelSeconds）にボスへ入れる。
--   合計が HP を超えたら討伐。参加したパーティごとにレアな宝箱（special:raid）を1つ受け取り箱へ入れる
--   （討伐の時点で到着しているパーティの分はそのとき、後から到着したパーティの分は到着のとき）。報酬の段階・弱点はない。
--   HP とダメージの式は仮（M7b-6）：Constants の raidHpMult・raidHpSpread・raidDamagePerAtk
-- 状態を持たない（関数の集合）。

local Chest = require("./Chest")
local Inbox = require("./Inbox")
local MapEvent = require("./MapEvent")
local Rng = require("./Rng")

local Raid = {}

-- その時間帯のボスの HP（プレイヤーごと。Rng.derive(state.seed, eventSlot)。rngCounter は進めない）
--   floor(基準のダンジョンの base.hp × raidHpMult × 一様乱数[min, max))。
--   基準のダンジョンは踏破済みの一番深いダンジョン（まだどこも踏破していなければ古い墓地：D-187）
function Raid.hp(state: any, slot: number, master: any): number
	local K = master.K
	local d = Chest.baseDungeon(state, master)
	local rng = Rng.new(Rng.derive(state.seed, slot))
	local spread = K.raidHpSpread.min + rng:float() * (K.raidHpSpread.max - K.raidHpSpread.min)
	return math.max(1, math.floor(d.base.hp * K.raidHpMult * spread))
end

-- パーティのダメージ（出発時に計算する）：floor(全員の攻撃力の合計 × raidDamagePerAtk)
function Raid.damage(snaps: { any }, K: any): number
	local total = 0
	for _, s in snaps do
		total += s.atk
	end
	return math.floor(total * K.raidDamagePerAtk)
end

-- 今の時間帯のレイドの状態（なければ nil。古い時間帯の分は使わない：03章）
function Raid.stateFor(state: any, slot: number): any?
	local r = state.raid
	if r and r.eventSlot == slot then
		return r
	end
	return nil
end

-- そのパーティはこの時間帯のレイドに出発済みか（1パーティ1回まで：D-187）
function Raid.joined(state: any, slot: number, partyIndex: number): boolean
	local r = Raid.stateFor(state, slot)
	return r ~= nil and table.find(r.parties, partyIndex) ~= nil
end

-- 出発を記録する。HP は最初の出発のときに決めて保存する（3分間のうちに踏破が進んでも変えない）
function Raid.join(state: any, slot: number, partyIndex: number, master: any)
	if Raid.stateFor(state, slot) == nil then
		state.raid = {
			eventSlot = slot,
			hp = Raid.hp(state, slot, master),
			damage = 0,
			defeated = false,
			parties = {},
			arrived = 0,
		}
	end
	table.insert(state.raid.parties, partyIndex)
end

-- 到着：ダメージを入れ、討伐の判定をする。宝箱は受け取り箱へ（D-164, D-179）
function Raid.arrive(state: any, e: any, takeRng: () -> Rng.Rng, master: any, events: { any })
	local r = Raid.stateFor(state, e.eventSlot)
	if r == nil then
		return -- 起きない（到着は次の時間帯より前：MasterData の検証）
	end
	r.damage += e.raidDamage
	r.arrived += 1
	local at = e.arriveAt
	local chests = 0
	local justDefeated = false
	if r.defeated then
		chests = 1 -- 討伐の後に到着したパーティの分
	elseif r.damage > r.hp then
		r.defeated = true
		justDefeated = true
		chests = r.arrived -- 討伐の時点で到着しているパーティの分
	end
	table.insert(events, {
		type = "RaidHit",
		at = at,
		partyIndex = e.partyIndex,
		eventSlot = e.eventSlot,
		damage = e.raidDamage,
		total = r.damage,
		hp = r.hp,
		defeated = r.defeated,
	})
	if justDefeated then
		table.insert(events, { type = "RaidDefeated", at = at, eventSlot = e.eventSlot })
	end
	for _ = 1, chests do
		local entry =
			Inbox.push(state, "raid", at, { chests = { { pileKey = "special:raid", count = 1 } } }, takeRng, master)
		table.insert(events, { type = "RaidReward", at = at, eventSlot = e.eventSlot, inboxUid = entry.uid })
	end
end

-- マップに出ているレイドボス（画面用：D-275）。{ { eventSlot, placeId, phase, closesIn?, coming, arriveIn? } }
--   phase："open"（出発できる3分間）・"closed"（3分間は過ぎたが、向かっているパーティがまだ着いていない）
--   coming：向かっている（まだ着いていない）パーティの番号。討伐したら出さない
function Raid.presence(state: any, now: number, master: any): { any }
	local bySlot: { [number]: any } = {}
	local function entry(slot: number): any
		local r = Raid.stateFor(state, slot)
		if r and r.defeated then
			return nil
		end
		local e = bySlot[slot]
		if e == nil then
			local ev = MapEvent.eventAt(slot, master, state)
			e = { eventSlot = slot, placeId = ev.placeId, phase = "closed", coming = {} }
			bySlot[slot] = e
		end
		return e
	end
	local slot = MapEvent.currentSlot(now, master, state) -- 管理者が出したレイドも（D-306）
	local cur = MapEvent.eventAt(slot, master, state)
	if cur.kind == "raid" and now < cur.closeAt then
		local e = entry(slot)
		if e then
			e.phase = "open"
			e.closesIn = cur.closeAt - now
		end
	end
	for _, x in state.expeditions do
		if x.raidDamage and not x.raidArrived and now < x.arriveAt then
			local e = entry(x.eventSlot)
			if e then
				table.insert(e.coming, x.partyIndex)
				e.arriveIn = math.min(e.arriveIn or math.huge, x.arriveAt - now) -- 最初に着くパーティまで
			end
		end
	end
	local out = {}
	for _, e in bySlot do
		if e.phase == "open" or #e.coming > 0 then
			table.sort(e.coming)
			table.insert(out, e)
		end
	end
	table.sort(out, function(a, b)
		return a.eventSlot < b.eventSlot
	end)
	return out
end

return Raid
