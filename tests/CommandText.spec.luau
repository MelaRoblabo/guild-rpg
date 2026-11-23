--!strict
local CommandText = require("../src/core/CommandText")
local Protocol = require("../src/core/Protocol")

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe(
		"D-101 テキストの書式 → コマンド（テキスト版とデバッグ画面で共通）",
		function()
			it("D-101 / D-166 / D-167 主な書式が対応するコマンドになる", function()
				expect(CommandText.parse("go 1 dng_graveyard")).toEqual({
					type = "Dispatch",
					partyIndex = 1,
					dungeonId = "dng_graveyard",
				})
				expect(CommandText.parse("party 1 2 -")).toEqual({ type = "SetPartySlot", partyIndex = 1, slot = 2 })
				expect(CommandText.parse("repeat 2 off")).toEqual({ type = "SetAutoRepeat", partyIndex = 2 })
				expect(CommandText.parse("sell eq_1 eq_2")).toEqual({
					type = "Sell",
					equipmentUids = { "eq_1", "eq_2" },
				})
				expect(CommandText.parse("sell item itm_bone_fragment 3")).toEqual({
					type = "Sell",
					itemId = "itm_bone_fragment",
					count = 3,
				})
				expect(CommandText.parse("choose prev")).toEqual({ type = "HireChoose", which = "previous" })
				expect(CommandText.parse("rb-choose cur")).toEqual({ type = "RebirthChoose", which = "current" })
				expect(CommandText.parse("unlock eq_9")).toEqual({ type = "SetLock", uid = "eq_9", locked = false })
				expect(CommandText.parse("open dng_ruins 10")).toEqual({
					type = "OpenChests",
					pileKey = "dng_ruins",
					count = 10,
				})
				expect(CommandText.parse("open special:raid")).toEqual({ type = "OpenChests", pileKey = "special:raid" })
				expect(CommandText.parse("sellweak eq_1 eq_2")).toEqual({
					type = "BulkSell",
					equipmentUids = { "eq_1", "eq_2" },
				})
				expect(CommandText.parse("sellweak")).toEqual({ type = "BulkSell", equipmentUids = {} })
				expect(CommandText.parse("train adv_1 max")).toEqual({
					type = "Train",
					adventurerUid = "adv_1",
					sessions = CommandText.TRAIN_MAX,
				})
			end)
			it("D-101 表示用・知らない書式は nil（呼び出し側が扱う）", function()
				for _, line in { "status", "roster", "help", "wait 10", "watch 1", "nope", "" } do
					expect(CommandText.parse(line)).toBe(nil)
				end
			end)
			it("D-101 正しく書いた書式は、サーバーの形の検証をすべて通る", function()
				local lines = {
					"party 1 2 adv_3",
					"party 1 4 -",
					"equip adv_1 eq_2",
					"unequip adv_1 weapon",
					"go 1 dng_graveyard",
					"repeat 1 dng_graveyard",
					"repeat 1 off",
					"open dng_graveyard",
					"open dng_graveyard 10",
					"open special:rare:dng_sky_throne",
					"sellweak eq_1 eq_2",
					"sell eq_1 eq_2",
					"sell item itm_bone_fragment",
					"lock eq_1",
					"hire",
					"pick 2",
					"reroll",
					"choose cur",
					"cancel",
					"rename adv_1 ネム",
					"dismiss adv_4",
					"rebirth adv_1 keep",
					"rb-reroll",
					"rb-choose prev",
					"jobchange adv_1 job_knight",
					"looks adv_1",
					"looks-choose cur",
					"expand exp_party",
					"train adv_1",
					"train adv_1 max",
					"autosell on 2 keep",
					"autosell off",
				}
				for _, line in lines do
					local ok, err = Protocol.validateCommand(CommandText.parse(line))
					expect({ line, ok, err }).toEqual({ line, true, nil })
				end
			end)
		end
	)
end
