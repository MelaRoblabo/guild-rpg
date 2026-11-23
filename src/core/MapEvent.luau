--!strict
-- マップイベントの時間帯（D-152, D-179、docs/system/06_formulas.md §12）
--   5分ごとに1つ（レアダンジョン・レイドボス・旅の商人）。1分前に予告し、出発・購入できるのは出てから3分間。
--   種類・場所・時刻は calendarSeed と時間帯の番号から決まり、全員共通（サーバー全体で状態を持たない：08章）。
--   中身（ボスの HP・商人の品）はプレイヤーごとで、Raid・Merchant が state.seed と時間帯の番号から作る。
-- 状態を持たない（関数の集合）。時刻は引数で受け取る（os.time は使わない）。

local Chest = require("./Chest")
local Rng = require("./Rng")

local MapEvent = {}

-- 時間帯の番号（06章 §12）
function MapEvent.slotOf(now: number, K: any): number
	return math.floor(now / K.mapEventIntervalSeconds)
end

function MapEvent.startOf(slot: number, K: any): number
	return slot * K.mapEventIntervalSeconds
end

-- 出発・購入できる最後の時刻（この時刻ちょうどからは締め切り）
function MapEvent.closeOf(slot: number, K: any): number
	return MapEvent.startOf(slot, K) + K.mapEventWindowSeconds
end

local function uniform(_e: any): number
	return 1
end

local function weightOf(e: any): number
	return e.weight
end

-- その時間帯のイベント（全員共通）：{ eventSlot, kindId, kind, placeId, startAt, closeAt }
-- 乱数：Rng.new(Rng.derive(calendarSeed, eventSlot)) で種類 → 場所の順に引く
function MapEvent.eventAt(slot: number, master: any): any
	local K = master.K
	local rng = Rng.new(Rng.derive(K.calendarSeed, slot))
	local kindId = rng:pickWeighted(K.mapEventKindWeights, weightOf).id
	local place = rng:pickWeighted(master.mapEventPlaces, uniform)
	return {
		eventSlot = slot,
		kindId = kindId,
		kind = master.mapEventKinds[kindId].kind,
		placeId = place.id,
		startAt = MapEvent.startOf(slot, K),
		closeAt = MapEvent.closeOf(slot, K),
	}
end

-- 出発・購入してよいか（D-152, D-179）。だめならエラーコード
--   まだ来ていない時間帯・種類が違う → EVENT_NOT_ACTIVE
--   過ぎた時間帯・3分間を過ぎた      → EVENT_WINDOW_CLOSED
function MapEvent.check(slot: any, kind: string, now: number, master: any): string?
	if type(slot) ~= "number" or slot ~= math.floor(slot) then
		return "EVENT_NOT_ACTIVE"
	end
	local current = MapEvent.slotOf(now, master.K)
	if slot > current then
		return "EVENT_NOT_ACTIVE"
	end
	if MapEvent.eventAt(slot, master).kind ~= kind then
		return "EVENT_NOT_ACTIVE"
	end
	if slot < current or now >= MapEvent.closeOf(slot, master.K) then
		return "EVENT_WINDOW_CLOSED"
	end
	return nil
end

-- 今と次のイベント（画面用：05章 §4 mapEvent）
--   current：今の時間帯のイベント。open（出発・購入できる）と closesIn（締め切りまでの秒。締め切り後は 0）
--   next：次の時間帯のイベント。予告の時間（mapEventNoticeSeconds 前）に入るまでは nil（D-152：1分前に予告）
--   nextAt：次の時間帯の始まりの時刻
function MapEvent.status(now: number, master: any): any
	local K = master.K
	local slot = MapEvent.slotOf(now, K)
	local cur = MapEvent.eventAt(slot, master)
	cur.open = now < cur.closeAt
	cur.closesIn = math.max(0, cur.closeAt - now)
	local nextAt = MapEvent.startOf(slot + 1, K)
	local nxt = nil
	if now >= nextAt - K.mapEventNoticeSeconds then
		nxt = MapEvent.eventAt(slot + 1, master)
		nxt.startsIn = nextAt - now
	end
	return { current = cur, next = nxt, nextAt = nextAt }
end

-- レアダンジョン（D-152, D-171, D-185、06章 §12）
--   強さ：踏破済みの一番深いダンジョン（まだどこも踏破していなければダンジョンの並びの先頭。要確認）
--   宝箱の山：special:rare:<1段上のダンジョン>。一番深いダンジョン（天空の玉座）の踏破後はそのダンジョンのまま。
--             まだどこも踏破していなければ並びの先頭（要確認）
--   「1段上」＝ tier が踏破済みの一番深いダンジョンより大きいもののうち、tier が最も小さい（同じ tier は並びの先）
function MapEvent.rareDungeonTarget(state: any, master: any): { dungeonId: string, pileKey: string }
	local deepest = Chest.deepestCleared(state, master)
	local strength = deepest or master.dungeonList[1]
	local above = nil
	if deepest == nil then
		above = master.dungeonList[1]
	else
		for _, d in master.dungeonList do
			if d.tier > deepest.tier and (above == nil or d.tier < above.tier) then
				above = d
			end
		end
		above = above or deepest -- D-185：最深部の踏破後は天空の玉座のまま
	end
	return { dungeonId = strength.id, pileKey = Chest.RARE_PREFIX .. above.id }
end

return MapEvent
