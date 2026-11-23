--!strict
-- 時間の進み方：日替わりの特性（D-156, D-173）、留守番（D-161, D-172）、休息ボーナス（D-161, D-173）
local Calendar = require("../src/core/Calendar")
local DailyTrait = require("../src/core/DailyTrait")
local Expedition = require("../src/core/Expedition")
local Formulas = require("../src/core/Formulas")
local Game = require("../src/core/Game")
local Growth = require("../src/core/Growth")
local Inventory = require("../src/core/Inventory")
local Migration = require("../src/core/Migration")
local Party = require("../src/core/Party")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1767225600 -- 2026-01-01 00:00 UTC
local DAY = 86400

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()
	local K = master.K

	local function ctx(now: number, online: boolean?)
		return { now = now, master = master, online = if online == nil then true else online }
	end
	local function exec(s: any, cmd: any, now: number?): any
		return Game.execute(s, cmd, ctx(now or T0))
	end
	local function newState(seed: number?, now: number?)
		return Game.newState(master, seed or 1, now or T0)
	end
	local function onlyExpedition(s: any): any?
		for _, e in s.expeditions do
			return e
		end
		return nil
	end
	-- 古い墓地に特性が当たる最初の日（T0 の日から探す）
	local function dayWithGraveyardTrait(traitId: string?): (number, string)
		local start = Calendar.dayIndex(T0)
		for d = start, start + 2000 do
			for _, p in DailyTrait.forDay(d, master) do
				if p.dungeonId == "dng_graveyard" and (traitId == nil or p.traitId == traitId) then
					return d, p.traitId
				end
			end
		end
		error("見つからない")
	end
	local function snapsOf(s: any): { any }
		return Party.snapshots(s, 1, master)
	end

	describe("日替わりの特性（D-156, D-173、06章 §16）", function()
		it("D-156 帯ごとに1つ、帯の難度のダンジョンと特性が決まる（全員共通）", function()
			local day = Calendar.dayIndex(T0)
			local picks = DailyTrait.forDay(day, master)
			expect(#picks).toBe(#K.dailyTraitBands)
			for i, p in picks do
				local band = K.dailyTraitBands[i]
				local d = master.dungeons[p.dungeonId]
				expect(p.band).toBe(i)
				expect(d.tier >= band.min and d.tier <= band.max).toBeTruthy()
				expect(master.dailyTraits[p.traitId] ~= nil).toBeTruthy()
			end
			-- 状態に依存しない（日の番号と calendarSeed だけ）
			expect(DailyTrait.forDay(day, Fixtures.master())).toEqual(picks)
			-- 日が変われば変わりうる
			local distinct = {}
			local n = 0
			for d = day, day + 30 do
				local key = DailyTrait.forDay(d, master)[1].dungeonId .. DailyTrait.forDay(d, master)[1].traitId
				if not distinct[key] then
					distinct[key] = true
					n += 1
				end
			end
			expect(n >= 3).toBeTruthy()
		end)
		it("D-156 calendarSeed が違えば別の結果になる", function()
			local m2 = Fixtures.master(function(d)
				d.Constants.calendarSeed += 1
			end)
			local diff = 0
			for d = 0, 20 do
				local a, b = DailyTrait.forDay(20000 + d, master), DailyTrait.forDay(20000 + d, m2)
				for i = 1, #a do
					if a[i].dungeonId ~= b[i].dungeonId or a[i].traitId ~= b[i].traitId then
						diff += 1
					end
				end
			end
			expect(diff > 0).toBeTruthy()
		end)
		it("D-156 query で今日と明日の分を出す", function()
			local now = T0 + 5 * DAY + 123
			local q = Game.query.dailyTraits(now, master)
			expect(q.today).toEqual(DailyTrait.forDay(Calendar.dayIndex(now), master))
			expect(q.tomorrow).toEqual(DailyTrait.forDay(Calendar.dayIndex(now) + 1, master))
			expect(q.nextDayAt).toBe(T0 + 6 * DAY)
		end)
		it(
			"D-156 出発時刻の日の特性を探索に固定する（帰還が翌日でも変えない）",
			function()
				local day, traitId = dayWithGraveyardTrait()
				local departAt = (day + 1) * DAY - 5 -- その日の終わりの5秒前
				local s = newState(1, departAt)
				expect(exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, departAt).ok).toBeTruthy()
				local e = onlyExpedition(s)
				expect(e.dailyTraitId).toBe(traitId)
				expect(e.log.dailyTraitId).toBe(traitId)
				expect(Calendar.dayIndex(e.returnAt)).toBe(day + 1)
			end
		)
		it("D-156 特性が当たっていないダンジョン・日は特性なし", function()
			local day = Calendar.dayIndex(T0)
			local hit = {}
			for _, p in DailyTrait.forDay(day, master) do
				hit[p.dungeonId] = true
			end
			for _, d in master.dungeonList do
				if not hit[d.id] then
					expect(DailyTrait.traitIdFor(d.id, T0, master)).toBe(nil)
				end
			end
		end)
		it("D-156 自動再派遣は次の出発時刻（＝帰還時刻）の日の特性を当てる", function()
			local day = dayWithGraveyardTrait()
			local departAt = day * DAY - 10 -- 前の日の終わり
			local s = newState(1, departAt)
			exec(s, { type = "SetAutoRepeat", partyIndex = 1, dungeonId = "dng_graveyard" }, departAt)
			exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, departAt)
			local first = onlyExpedition(s)
			expect(first.dailyTraitId).toBe(DailyTrait.traitIdFor("dng_graveyard", departAt, master))
			Game.advance(s, ctx(first.returnAt))
			local second = onlyExpedition(s)
			expect(second.departAt).toBe(first.returnAt)
			expect(second.dailyTraitId).toBe(DailyTrait.traitIdFor("dng_graveyard", first.returnAt, master))
			expect(second.dailyTraitId ~= nil).toBeTruthy()
		end)
		it("D-173 攻撃力は攻撃区分が合う者だけ × (1 + value)。個体補正の上限の外", function()
			local phys = master.dailyTraits.dt_atk_physical
			local mag = master.dailyTraits.dt_atk_magic
			local warrior = Fixtures.snap({ atk = 100, attackType = "physical" })
			local mage = Fixtures.snap({ atk = 100, attackType = "magic" })
			expect(Formulas.traitAttack(warrior, phys)).toBe(math.floor(100 * (1 + phys.value)))
			expect(Formulas.traitAttack(mage, phys)).toBe(100)
			expect(Formulas.traitAttack(mage, mag)).toBe(math.floor(100 * (1 + mag.value)))
			expect(Formulas.traitAttack(warrior, nil)).toBe(100)
			-- 個体補正が上限まで掛かっている者にも、さらに掛かる
			local def = {
				uid = "a",
				slot = 1,
				jobId = "job_warrior",
				baseStats = { str = 100, mag = 0, agi = 10, dex = 10, hp = 100 },
				giftIds = { "gift_sturdy", "gift_sturdy", "gift_sturdy", "gift_sturdy" },
				equipment = {},
			}
			local snap = Formulas.memberSnapshot(def, master)
			expect(Formulas.traitAttack(snap, phys)).toBe(math.floor(snap.atk * (1 + phys.value)))
		end)
		it(
			"D-156 攻撃力の特性は戦闘に入る（同じシードで物理職の与ダメージが増える）",
			function()
				local s = newState()
				local snaps = snapsOf(s)
				local base = { seed = 7, departAt = T0, dungeonId = "dng_graveyard", members = snaps }
				local a = Expedition.simulate(base, master)
				local withTrait = table.clone(base)
				withTrait.dailyTraitId = "dt_atk_physical"
				local b = Expedition.simulate(withTrait, master)
				-- 最初の戦闘の1ターン目、物理職（隊列1の戦士）の与ダメージ
				local function firstAttack(log: any, slot: number): number
					for _, act in log.floors[1].turns[1].actions do
						if act.kind == "attack" and act.slot == slot then
							return act.amount
						end
					end
					error("攻撃がない")
				end
				expect(firstAttack(b, 1) > firstAttack(a, 1)).toBeTruthy()
				expect(b.travelSeconds).toBe(a.travelSeconds) -- 攻撃力の特性は移動に効かない
				expect(b.dailyTraitId).toBe("dt_atk_physical")
			end
		)
		it("D-156 移動時間の特性は片道秒に掛かる", function()
			local s = newState()
			local snaps = snapsOf(s)
			local d = master.dungeons.dng_graveyard
			local tr = master.dailyTraits.dt_travel
			local a = Expedition.simulate({ seed = 3, departAt = T0, dungeonId = d.id, members = snaps }, master)
			local b = Expedition.simulate(
				{ seed = 3, departAt = T0, dungeonId = d.id, members = snaps, dailyTraitId = tr.id },
				master
			)
			expect(b.travelSeconds).toBe(Formulas.travelSeconds(snaps, d, K, tr.value))
			expect(b.travelSeconds < a.travelSeconds).toBeTruthy()
			expect(b.totalSeconds).toBe(b.travelSeconds * 2 + b.replaySeconds)
		end)
		it(
			"D-173 宝箱の特性：1個ごとに (倍率 − 1) の確率で +1（端数の確率の切り上げ）",
			function()
				local s = newState()
				local snaps = snapsOf(s)
				local tr = master.dailyTraits.dt_chest
				local base, extra = 0, 0
				for seed = 1, 600 do
					local log = Expedition.simulate({
						seed = seed,
						departAt = T0,
						dungeonId = "dng_graveyard",
						members = snaps,
						dailyTraitId = tr.id,
					}, master)
					base += #log.rewards.chests - log.traitChests
					extra += log.traitChests
				end
				expect(extra / base).toBeCloseTo(tr.value - 1, 0.05)
			end
		)
		it(
			"D-173 宝箱の特性の整数部はそのまま増え、乱数を使わない部分は特性なしと同じ",
			function()
				local m2 = Fixtures.master(function(d)
					for _, r in d.DailyTraits do
						if r.id == "dt_chest" then
							r.value = 2
						end
					end
				end)
				local s = Game.newState(m2, 1, T0)
				local snaps = Party.snapshots(s, 1, m2)
				for seed = 1, 50 do
					local a = Expedition.simulate(
						{ seed = seed, departAt = T0, dungeonId = "dng_graveyard", members = snaps },
						m2
					)
					local b = Expedition.simulate({
						seed = seed,
						departAt = T0,
						dungeonId = "dng_graveyard",
						members = snaps,
						dailyTraitId = "dt_chest",
					}, m2)
					expect(#b.rewards.chests).toBe(2 * #a.rewards.chests)
					expect(b.result).toBe(a.result)
					expect(b.rewards.exp).toEqual(a.rewards.exp)
				end
			end
		)
		it("D-173 経験値の特性は帰還時に掛ける（経験値補正の上限の外）", function()
			local function play(traitId: string?): number
				local s = newState(5)
				local adv = s.adventurers[s.parties[1].slots[1]]
				adv.level, adv.levelCap, adv.exp = 19, 20, 0
				adv.giftIds = { "gift_glutton" }
				exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" })
				local e = onlyExpedition(s)
				e.dailyTraitId = traitId
				local raw = e.log.rewards.exp[adv.uid]
				Game.advance(s, ctx(e.returnAt))
				local mult = Growth.expMultiplier(s.adventurers[adv.uid], master, s.equipment)
				expect(s.adventurers[adv.uid].exp).toBe(
					math.floor(raw * mult * (if traitId then master.dailyTraits[traitId].value else 1))
				)
				return s.adventurers[adv.uid].exp
			end
			expect(play("dt_exp") > play(nil)).toBeTruthy()
		end)
		it("D-173 乱数の消費順を変えたので engineVersion は 2", function()
			expect(Expedition.ENGINE_VERSION).toBe(2)
			local s = newState()
			local log = Expedition.simulate(
				{ seed = 1, departAt = T0, dungeonId = "dng_graveyard", members = snapsOf(s) },
				master
			)
			expect(log.engineVersion).toBe(2)
		end)
	end)

	describe("留守番（D-161, D-172、06章 §13）", function()
		local function loggedOutWithRepeat(dungeonId: string?)
			local s = newState()
			local dng = dungeonId or "dng_graveyard"
			exec(s, { type = "SetAutoRepeat", partyIndex = 1, dungeonId = dng })
			exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = dng })
			s.lastSavedAt = T0 -- ログアウト（サーバーが保存のときに書く）
			return s
		end
		it(
			"D-161 自動再派遣のパーティは探索時間10倍で続き、6時間までに全員帰還して終わる",
			function()
				local s = loggedOutWithRepeat()
				local events = Game.advance(s, ctx(T0 + 10 * 3600, false))
				local dispatched, lastReturn = 0, 0
				for _, e in events do
					if e.type == "AutoDispatched" then
						dispatched += 1
						expect(e.offline).toBe(true)
						expect(e.returnAt <= T0 + K.offlineMaxSeconds).toBeTruthy()
					elseif e.type == "ExpeditionReturned" then
						lastReturn = math.max(lastReturn, e.at)
					end
				end
				expect(dispatched >= 1).toBeTruthy()
				expect(lastReturn <= T0 + K.offlineMaxSeconds).toBeTruthy()
				expect(onlyExpedition(s)).toBe(nil) -- 全員ギルドで待機
				expect(s.parties[1].autoRepeat ~= nil).toBeTruthy() -- 設定は残す
				expect(s.stats.offlineExpeditions).toBe(dispatched)
			end
		)
		it("D-161 留守番の探索は所要秒だけが offlineTimeMult 倍（報酬は同じ）", function()
			local s = loggedOutWithRepeat()
			local snaps = snapsOf(s)
			local a =
				Expedition.simulate({ seed = 9, departAt = T0, dungeonId = "dng_graveyard", members = snaps }, master)
			local b = Expedition.simulate(
				{ seed = 9, departAt = T0, dungeonId = "dng_graveyard", members = snaps, timeMult = K.offlineTimeMult },
				master
			)
			expect(b.totalSeconds).toBe(a.totalSeconds * K.offlineTimeMult)
			expect(b.travelSeconds).toBe(a.travelSeconds * K.offlineTimeMult)
			expect(b.rewards).toEqual(a.rewards)
			expect(b.floors[#b.floors].startOffset).toBe(a.floors[#a.floors].startOffset * K.offlineTimeMult)
		end)
		it("D-161 留守番の探索には offline の印を付ける", function()
			local s = loggedOutWithRepeat()
			local first = onlyExpedition(s)
			Game.advance(s, ctx(first.returnAt, false)) -- 最初の帰還の瞬間にログイン
			local offlineSeen = false
			for _, e in s.expeditions do
				offlineSeen = offlineSeen or e.offline == true
			end
			-- ログインの時点で帰っていない留守番は帰還済み（D-172）なので残らない
			expect(offlineSeen).toBe(false)
			-- 印は帰還イベントにも残る
			local s2 = loggedOutWithRepeat()
			local events = Game.advance(s2, ctx(T0 + 3 * 3600, false))
			local offlineReturns = 0
			for _, e in events do
				if e.type == "ExpeditionReturned" and e.offline then
					offlineReturns += 1
				end
			end
			expect(offlineReturns >= 1).toBeTruthy()
		end)
		it(
			"D-172 6時間より前にログインしたら、帰っていない留守番の探索はその時点で帰還させる",
			function()
				local s = loggedOutWithRepeat()
				local now = T0 + 1800
				local events = Game.advance(s, ctx(now, false))
				local atNow = 0
				for _, e in events do
					if e.type == "ExpeditionReturned" and e.at == now then
						atNow += 1
						expect(e.offline).toBe(true)
					end
				end
				expect(atNow).toBe(1)
				expect(onlyExpedition(s)).toBe(nil)
			end
		)
		it("D-172 留守中は倉庫がいっぱいでも止めない", function()
			local s = loggedOutWithRepeat()
			s.expansions.warehouseSize = 0
			local events = Game.advance(s, ctx(T0 + 3600, false))
			local dispatched, stopped = 0, false
			for _, e in events do
				dispatched += if e.type == "AutoDispatched" then 1 else 0
				stopped = stopped or e.type == "AutoRepeatStopped"
			end
			expect(dispatched >= 1).toBeTruthy()
			expect(stopped).toBe(false)
			expect(s.parties[1].autoRepeat ~= nil).toBeTruthy()
		end)
		it("D-161 自動再派遣でないパーティは、出ていた探索が帰るだけ", function()
			local s = newState()
			exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" })
			s.lastSavedAt = T0
			local events = Game.advance(s, ctx(T0 + 3600, false))
			local returns, dispatched = 0, 0
			for _, e in events do
				returns += if e.type == "ExpeditionReturned" then 1 else 0
				dispatched += if e.type == "AutoDispatched" then 1 else 0
			end
			expect(returns).toBe(1)
			expect(dispatched).toBe(0)
		end)
		it("D-161 留守の始まりは lastSavedAt（6時間の枠もそこから数える）", function()
			local s = loggedOutWithRepeat()
			local first = onlyExpedition(s)
			Game.advance(s, ctx(first.returnAt)) -- オンラインで1回帰って自動再派遣
			local savedAt = first.returnAt + 5
			s.lastSavedAt = savedAt
			expect(Game.offlineStart(s)).toBe(savedAt)
			local events = Game.advance(s, ctx(savedAt + 10 * 3600, false))
			for _, e in events do
				if e.type == "AutoDispatched" then
					expect(e.returnAt <= savedAt + K.offlineMaxSeconds).toBeTruthy()
				end
			end
		end)
		it(
			"D-161 留守中は雇用・転生・トレーニングをしない（状態が変わらない）",
			function()
				local s = loggedOutWithRepeat()
				exec(s, { type = "HireStart" })
				local hire = Fixtures.clone(s.hireSession)
				Game.advance(s, ctx(T0 + 3600, false))
				expect(s.hireSession).toEqual(hire)
				expect(s.rebirthSession).toBe(nil)
			end
		)
	end)

	describe("途中ログインの持ち帰り（D-186）", function()
		-- ログアウト中に出ている留守番の探索（古い墓地）を1つ作る
		local function withOfflineExpedition()
			local s = newState()
			exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" })
			local e = onlyExpedition(s)
			e.offline = true
			s.lastSavedAt = T0
			return s, e
		end
		local function returned(events: { any }): any
			for _, ev in events do
				if ev.type == "ExpeditionReturned" then
					return ev
				end
			end
			error("帰還がない")
		end
		local function materialGold(items: { [string]: number }): number
			local g = 0
			for id, n in items do
				if master.items[id].kind == "sellable" then
					g += master.items[id].sellPrice * n
				end
			end
			return g
		end

		it("D-186 ログアウト直後にログインすると、ほとんど何も持ち帰らない", function()
			local s, e = withOfflineExpedition()
			local adv = s.adventurers[e.memberUids[1]]
			local exp0, level0, gold0 = adv.exp, adv.level, s.gold
			local ev = returned(Game.advance(s, ctx(T0 + 1, false)))
			expect(ev.interrupted).toBe(true)
			expect(ev.result).toBe("retreat")
			expect(ev.chests).toBe(0)
			expect(ev.gold).toBe(0)
			expect(ev.guildExp).toBe(0)
			expect(s.gold).toBe(gold0)
			expect(s.adventurers[adv.uid].exp).toBe(exp0)
			expect(s.adventurers[adv.uid].level).toBe(level0)
			expect(s.clearedDungeons.dng_graveyard).toBe(nil) -- 踏破の扱いにしない
			expect(onlyExpedition(s)).toBe(nil) -- ギルドで待機
		end)
		it(
			"D-186 半分ほど進んだところでログインすると、そこまでのフロアの分だけ持ち帰る",
			function()
				local s, e = withOfflineExpedition()
				local log = e.log
				local k = #log.floors // 2
				local f = log.floors[k]
				local now = e.departAt + f.startOffset + f.duration
				expect(now < e.returnAt).toBeTruthy()
				local gold, chests, items = 0, 0, {}
				for i = 1, k do
					local g = log.floors[i].gained
					gold += g.gold
					chests += g.chestTo - g.chestFrom + 1
					for id, n in g.items do
						items[id] = (items[id] or 0) + n
					end
				end
				expect(chests < #log.rewards.chests).toBeTruthy() -- 確定宝箱などは入らない
				local gold0 = s.gold
				local events = Game.advance(s, ctx(now, false))
				local ev = returned(events)
				expect(ev.interrupted).toBe(true)
				expect(ev.result).toBe("retreat")
				expect(ev.reachedFloor).toBe(k)
				expect(ev.gold).toBe(gold)
				expect(ev.chests).toBe(chests)
				expect(ev.guildExp).toBe(k * K.guildExpPerFloor)
				expect(s.chests.dng_graveyard ~= nil or chests == 0).toBeTruthy()
				local total = 0
				for _, n in s.chests.dng_graveyard or {} do
					total += n
				end
				expect(total).toBe(chests)
				expect(s.gold).toBe(gold0 + gold + materialGold(items))
				for _, x in events do
					expect(x.type ~= "FirstClear").toBeTruthy()
				end
			end
		)
		it("D-186 帰還の時刻を過ぎていれば、全部持ち帰る（踏破の報酬も）", function()
			local s, e = withOfflineExpedition()
			local log = e.log
			expect(log.result).toBe("clear")
			local events = Game.advance(s, ctx(e.returnAt + 10, false))
			local ev = returned(events)
			expect(ev.interrupted).toBe(nil)
			expect(ev.result).toBe("clear")
			expect(ev.chests).toBe(#log.rewards.chests)
			expect(ev.gold).toBe(log.rewards.gold)
			expect(s.clearedDungeons.dng_graveyard).toBe(true)
		end)
		it("D-186 全フロアを終えて帰りの移動中なら、ログのとおり全部", function()
			local s, e = withOfflineExpedition()
			local log = e.log
			local part = Expedition.rewardsAt(log, log.travelSeconds + log.replaySeconds, K)
			expect(part.interrupted).toBe(false)
			expect(part.result).toBe(log.result)
			expect(part.rewards).toEqual(log.rewards)
			local _ = s
		end)
		it("D-186 日替わりで増えた宝箱は、元の宝箱を持ち帰るときだけ", function()
			local s = newState()
			local snaps = snapsOf(s)
			for seed = 1, 40 do
				local log = Expedition.simulate({
					seed = seed,
					departAt = T0,
					dungeonId = "dng_graveyard",
					members = snaps,
					dailyTraitId = "dt_chest",
				}, master)
				local k = #log.floors // 2
				local f = log.floors[k]
				local part = Expedition.rewardsAt(log, f.startOffset + f.duration, K)
				local base = 0
				for i = 1, k do
					base += log.floors[i].gained.chestTo - log.floors[i].gained.chestFrom + 1
				end
				local extra = 0
				for _, src in log.traitChestSources do
					if src <= base then
						extra += 1
					end
				end
				expect(#part.rewards.chests).toBe(base + extra)
			end
		end)
	end)

	describe("休息ボーナス（D-161, D-173、06章 §14）", function()
		it("D-161 留守にした時間の半分を貯める（上限4時間）", function()
			local s = newState()
			s.lastSavedAt = T0
			Game.advance(s, ctx(T0 + 2 * 3600, false))
			expect(Game.query.restBonus(s)).toBe(math.floor(2 * 3600 * K.restBonusRate))
			local s2 = newState()
			s2.lastSavedAt = T0
			Game.advance(s2, ctx(T0 + 20 * 3600, false))
			expect(s2.restBonusSeconds).toBe(K.restBonusMaxSeconds)
		end)
		it(
			"D-173 オンラインの時間だけ減る（探索していなくても減る、0 未満にしない）",
			function()
				local s = newState()
				s.restBonusSeconds = 1000
				Game.advance(s, ctx(T0 + 600))
				expect(s.restBonusSeconds).toBe(400)
				Game.advance(s, ctx(T0 + 5000))
				expect(s.restBonusSeconds).toBe(0)
			end
		)
		local function playReturn(rest: number, traitId: string?, glutton: boolean?): (any, any, number)
			local s = newState(5)
			local adv = s.adventurers[s.parties[1].slots[1]]
			adv.level, adv.levelCap, adv.exp = 19, 20, 0
			if glutton then
				adv.giftIds = { "gift_glutton" }
				local amulet = Inventory.newEquipment(
					s,
					{ baseId = "eq_sub_amulet_learning", rarity = 6, grade = 3, itemLevel = 1 }
				)
				exec(s, { type = "Unequip", adventurerUid = adv.uid, slot = "sub" })
				exec(s, { type = "Equip", adventurerUid = adv.uid, equipmentUid = amulet.uid })
			end
			s.restBonusSeconds = rest
			exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" })
			local e = onlyExpedition(s)
			e.dailyTraitId = traitId
			local raw = e.log.rewards.exp[adv.uid]
			local events = Game.advance(s, ctx(e.returnAt))
			return s, events, raw
		end
		it("D-161 オンライン中の帰還で残りがあれば経験値 × restBonusExpMult", function()
			local s, events, raw = playReturn(1000)
			local adv = s.adventurers[s.parties[1].slots[1]]
			local mult = Growth.expMultiplier(adv, master, s.equipment)
			expect(adv.exp).toBe(math.floor(raw * mult * K.restBonusExpMult))
			expect(events[1].restBonus).toBe(true)
			local s0, events0, raw0 = playReturn(0)
			local adv0 = s0.adventurers[s0.parties[1].slots[1]]
			expect(adv0.exp).toBe(math.floor(raw0 * Growth.expMultiplier(adv0, master, s0.equipment)))
			expect(events0[1].restBonus).toBe(nil)
		end)
		it(
			"D-173 帰還時に残りが尽きていれば掛けない（オンラインの経過で減った分を見る）",
			function()
				local _, events = playReturn(1) -- 出発から帰還までに尽きる
				expect(events[1].restBonus).toBe(nil)
			end
		)
		it("D-173 修練の護符・日替わりと重ねて、経験値補正の上限の外で掛ける", function()
			local s, _, raw = playReturn(1000, "dt_exp", true)
			local adv = s.adventurers[s.parties[1].slots[1]]
			local mult = Growth.expMultiplier(adv, master, s.equipment)
			-- 補正（大食らい＋護符）は上限まで
			expect(mult).toBeCloseTo(1 + K.expBonusCap)
			expect(adv.exp).toBe(math.floor(raw * mult * K.restBonusExpMult * master.dailyTraits.dt_exp.value))
		end)
		it("D-161 留守番の探索には休息ボーナスを使わない", function()
			local s = newState(5)
			exec(s, { type = "SetAutoRepeat", partyIndex = 1, dungeonId = "dng_graveyard" })
			exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" })
			s.lastSavedAt = T0
			s.restBonusSeconds = K.restBonusMaxSeconds
			local events = Game.advance(s, ctx(T0 + 3600, false))
			for _, e in events do
				if e.type == "ExpeditionReturned" then
					expect(e.restBonus).toBe(nil)
				end
			end
		end)
		it("D-173 トレーニングには掛けない", function()
			local function train(rest: number): number
				local s = newState()
				local uid = s.parties[1].slots[1]
				s.gold = 10 ^ 9
				s.restBonusSeconds = rest
				exec(s, { type = "Train", adventurerUid = uid, sessions = 1 })
				local adv = s.adventurers[uid]
				return adv.level * 1000000 + adv.exp
			end
			expect(train(K.restBonusMaxSeconds)).toBe(train(0))
		end)
	end)

	describe("セーブの移行 version 6 → 7（M7b-3）", function()
		it(
			"D-161 lastSavedAt に lastAdvancedAt を入れ、休息ボーナスは 0。探索はそのまま",
			function()
				local s = newState()
				exec(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" })
				s.version = 6
				s.lastSavedAt = nil
				s.restBonusSeconds = nil
				s.lastAdvancedAt = T0 + 77
				local before = Fixtures.clone(s.expeditions)
				Migration.migrate(s, master)
				expect(s.version).toBe(Migration.CURRENT) -- 6 → 7 → 8（v7 → 8 は Rewards.spec）
				expect(s.lastSavedAt).toBe(T0 + 77)
				expect(s.restBonusSeconds).toBe(0)
				expect(s.expeditions).toEqual(before)
				local e = onlyExpedition(s)
				expect(e.offline).toBe(nil)
				expect(e.dailyTraitId).toBe(nil)
			end
		)
		it("D-161 新しいセーブは lastSavedAt と休息ボーナス 0 を持つ", function()
			local s = newState()
			expect(s.lastSavedAt).toBe(T0)
			expect(s.restBonusSeconds).toBe(0)
		end)
	end)
end
