--!strict
-- メイン画面の純粋なモジュール（M8-2）：パーティの状態・ピンチ・マップの配置
local Expedition = require("../src/core/Expedition")
local MapLayout = require("../src/client/hub/MapLayout")
local PartyStatus = require("../src/client/hub/PartyStatus")

-- 出発 1000、行き 100 秒、フロア3つ（各 20 秒）、帰り 100 秒
local function makeExpedition(hpAfter: { { number } }): any
	local floors = {}
	for i, hp in hpAfter do
		table.insert(floors, { floor = i, startOffset = 100 + (i - 1) * 20, duration = 20, hpAfter = hp })
	end
	return {
		dungeonId = "dng_graveyard",
		returnAt = 1000 + 260,
		collected = false,
		log = { departAt = 1000, travelSeconds = 100, replaySeconds = 60, totalSeconds = 260, floors = floors },
	}
end

local MAX = { 100, 100, 100, 100 }

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("D-249 帰るまでの残り・ダンジョンの中の進み・戦闘中", function()
		it(
			"行き・探索・帰りを通して、帰るまでの残り秒を出す。待機は出さない",
			function()
				local e = makeExpedition({ { 100 }, { 100 }, { 100 } })
				expect(PartyStatus.compute(e, 1050, Expedition.progressAt, MAX, 0.3).remaining).toBe(210)
				expect(PartyStatus.compute(e, 1130, Expedition.progressAt, MAX, 0.3).remaining).toBe(130)
				expect(PartyStatus.compute(e, 1200, Expedition.progressAt, MAX, 0.3).remaining).toBe(60)
				expect(PartyStatus.compute(nil, 1200, Expedition.progressAt, MAX, 0.3).remaining).toBe(nil)
			end
		)
		it("ダンジョンの中だけ進み（0〜1）を出す", function()
			local e = makeExpedition({ { 100 }, { 100 }, { 100 } })
			expect(PartyStatus.compute(e, 1050, Expedition.progressAt, MAX, 0.3).exploreRatio).toBe(nil)
			expect(PartyStatus.compute(e, 1130, Expedition.progressAt, MAX, 0.3).exploreRatio).toBe(0.5)
			expect(PartyStatus.compute(e, 1200, Expedition.progressAt, MAX, 0.3).exploreRatio).toBe(nil)
		end)
		it("今のフロアが戦闘のときだけ戦闘中", function()
			local e = makeExpedition({ { 100 }, { 100 }, { 100 } })
			e.log.floors[1].kind = "battle"
			e.log.floors[2].kind = "event"
			expect(PartyStatus.compute(e, 1110, Expedition.progressAt, MAX, 0.3).inBattle).toBe(true)
			expect(PartyStatus.compute(e, 1130, Expedition.progressAt, MAX, 0.3).inBattle).toBe(false)
			expect(PartyStatus.compute(e, 1050, Expedition.progressAt, MAX, 0.3).inBattle).toBe(false)
		end)
	end)

	describe("D-212 パーティの状態（PartyStatus.compute）", function()
		it("D-212 探索がなければ待機", function()
			local s = PartyStatus.compute(nil, 1000, Expedition.progressAt, MAX, 0.3)
			expect(s.state).toBe("waiting")
			expect(s.pinch).toBe(false)
		end)
		it("D-212 行きは移動中、道のりの位置が進む", function()
			local s = PartyStatus.compute(makeExpedition({}), 1050, Expedition.progressAt, MAX, 0.3)
			expect(s.state).toBe("moving")
			expect(s.along).toBe(0.5)
		end)
		it("D-212 フロアの再生中は探索中（ダンジョンの位置）", function()
			local e = makeExpedition({ { 100, 100, 100, 100 }, { 90, 90, 90, 90 }, { 80, 80, 80, 80 } })
			local s = PartyStatus.compute(e, 1125, Expedition.progressAt, MAX, 0.3)
			expect(s.state).toBe("exploring")
			expect(s.along).toBe(1)
			expect(s.floorIndex).toBe(2)
		end)
		it("D-212 帰りは帰還中、位置はダンジョンからギルドへ戻る", function()
			local e = makeExpedition({ { 100, 100, 100, 100 } })
			local s = PartyStatus.compute(e, 1000 + 160 + 25, Expedition.progressAt, MAX, 0.3)
			expect(s.state).toBe("returning")
			expect(s.along).toBe(0.75)
		end)
		it("D-212 帰ってきたら待機", function()
			local s = PartyStatus.compute(makeExpedition({}), 1300, Expedition.progressAt, MAX, 0.3)
			expect(s.state).toBe("waiting")
		end)
	end)

	describe("D-212 ピンチ", function()
		it("D-212 今の時点で戦闘不能のメンバーがいればピンチ", function()
			local e = makeExpedition({ { 100, 0, 100, 100 }, { 100, 0, 100, 100 }, { 100, 0, 100, 100 } })
			local s = PartyStatus.compute(e, 1125, Expedition.progressAt, MAX, 0.3)
			expect(s.pinch).toBe(true)
			expect(s.downCount).toBe(1)
		end)
		it("D-212 HP の割合がしきい値より低ければピンチ", function()
			local e = makeExpedition({ { 20, 20, 20, 20 }, { 20, 20, 20, 20 }, { 20, 20, 20, 20 } })
			local s = PartyStatus.compute(e, 1125, Expedition.progressAt, MAX, 0.3)
			expect(s.pinch).toBe(true)
			expect(s.downCount).toBe(0)
		end)
		it("D-212 まだ戦っていない（最初のフロアの途中）はピンチにしない", function()
			local e = makeExpedition({ { 0, 0, 0, 0 } })
			local s = PartyStatus.compute(e, 1105, Expedition.progressAt, MAX, 0.3)
			expect(s.pinch).toBe(false)
		end)
		it("D-214 帰り道ではピンチの印を出さない", function()
			local e = makeExpedition({ { 100, 0, 100, 100 } })
			local s = PartyStatus.compute(e, 1000 + 160 + 10, Expedition.progressAt, MAX, 0.3)
			expect(s.state).toBe("returning")
			expect(s.pinch).toBe(false)
		end)
		it("D-212 しきい値がマスターデータになければ、戦闘不能だけで判定する", function()
			local e = makeExpedition({ { 10, 10, 10, 10 } })
			local s = PartyStatus.compute(e, 1125, Expedition.progressAt, MAX, nil)
			expect(s.pinch).toBe(false)
		end)
	end)

	describe("D-212 マップの配置（MapLayout）", function()
		it(
			"D-212 マップは画面より広く、ダンジョンどうしは 66px の範囲が重ならない",
			function()
				expect(MapLayout.width(12) > 1280).toBe(true)
				local a, b = MapLayout.dungeon(1), MapLayout.dungeon(2)
				expect(b.x - a.x >= 66).toBe(true)
			end
		)
		it("D-212 馬車はギルドとダンジョンのあいだを道のりの位置で動く", function()
			local g, d = MapLayout.guild(), MapLayout.dungeon(1)
			local w = MapLayout.wagon(1, 0.5)
			expect(w.x).toBe((g.x + d.x) / 2)
			expect(MapLayout.wagon(nil, 0.5).x).toBe(g.x)
		end)
		it("D-212 カメラは端ではみ出さない", function()
			expect(MapLayout.cameraX(100, 1280, 4000)).toBe(0)
			expect(MapLayout.cameraX(3900, 1280, 4000)).toBe(4000 - 1280)
			expect(MapLayout.cameraX(2000, 1280, 4000)).toBe(2000 - 640)
		end)
	end)
	describe("D-307 パーティ一覧の HP の棒", function()
		it(
			"D-307 メンバーの HP の合計 ÷ 最大 HP の合計。まだ戦っていなければ 1、待機中は nil",
			function()
				local e = makeExpedition({ { 50, 100, 0, 50 } })
				expect(PartyStatus.compute(e, 1050, Expedition.progressAt, MAX, 0.3).hpRatio).toBe(1)
				expect(PartyStatus.compute(e, 1125, Expedition.progressAt, MAX, 0.3).hpRatio).toBe(0.5)
				expect(PartyStatus.compute(nil, 1125, Expedition.progressAt, MAX, 0.3).hpRatio).toBe(nil)
			end
		)
	end)
	describe("D-304 レアダンジョンへのパーティは行き先が水晶の祠", function()
		it("D-304 宝箱の山が special:rare: の派遣だけ、その時間帯を rareSlot に持つ", function()
			local e = makeExpedition({})
			e.eventSlot = 42
			e.chestPile = "special:rare:dng_ruins"
			expect(PartyStatus.compute(e, 1050, Expedition.progressAt, MAX, 0.3).rareSlot).toBe(42)
			local raid = makeExpedition({})
			raid.eventSlot = 43
			raid.raidDamage = 10
			expect(PartyStatus.compute(raid, 1050, Expedition.progressAt, MAX, 0.3).rareSlot).toBe(nil)
			expect(PartyStatus.compute(makeExpedition({}), 1050, Expedition.progressAt, MAX, 0.3).rareSlot).toBe(nil)
		end)
	end)
	describe("D-274 商人へ向かうパーティの状態", function()
		-- 片道 30 秒、上限 1800 秒とどまる（フロアなし）
		local function merchantExpedition(leaveAt: number?): any
			local stay = if leaveAt then leaveAt - 1030 else 1800
			return {
				merchant = true,
				dungeonId = "dng_graveyard",
				arriveAt = 1030,
				leaveAt = leaveAt,
				returnAt = 1030 + stay + 30,
				log = {
					departAt = 1000,
					travelSeconds = 30,
					replaySeconds = stay,
					totalSeconds = 60 + stay,
					floors = {},
				},
			}
		end
		it(
			"D-274 向かっている間の残りは着くまで。とどまっている間は探索中で残りなし",
			function()
				local e = merchantExpedition(nil)
				local s1 = PartyStatus.compute(e, 1010, Expedition.progressAt, MAX, 0.3)
				expect(s1.state).toBe("moving")
				expect(s1.remaining).toBe(20)
				expect(s1.merchant).toBe(true)
				local s2 = PartyStatus.compute(e, 1100, Expedition.progressAt, MAX, 0.3)
				expect(s2.state).toBe("exploring")
				expect(s2.remaining).toBe(nil)
			end
		)
		it("D-274 Leave の後は帰り道（残りは帰るまで）", function()
			local e = merchantExpedition(1100)
			local s = PartyStatus.compute(e, 1110, Expedition.progressAt, MAX, 0.3)
			expect(s.state).toBe("returning")
			expect(s.remaining).toBe(20)
		end)
	end)
	describe("D-251 マップイベントの仮の場所", function()
		it(
			"上の帯（右上のボタンの高さ）より下で、ダンジョンの丸と重ならない",
			function()
				for i = 1, 4 do
					local p = MapLayout.eventPlace(i)
					expect(p.y >= 300).toBe(true)
					for k = 1, 12 do
						local d = MapLayout.dungeon(k)
						local dist = math.sqrt((p.x - d.x) ^ 2 + (p.y - d.y) ^ 2)
						expect(dist >= 120).toBe(true)
					end
				end
			end
		)
	end)
end
