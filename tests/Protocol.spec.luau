--!strict
local serde = require("@lune/serde")

local Game = require("../src/core/Game")
local Protocol = require("../src/core/Protocol")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1767225600

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()

	local function ctx(now: number)
		return { now = now, master = master, online = true }
	end

	describe("D-101 コマンドの形の検証", function()
		it("D-101 Game のコマンドは GrantPurchase 以外すべて受け付ける表がある", function()
			for _, name in Game.COMMANDS do
				if not Protocol.SERVER_ONLY[name] then
					expect(Protocol.CLIENT_COMMANDS[name] ~= nil).toBe(true)
				end
			end
			for name in Protocol.CLIENT_COMMANDS do
				expect(table.find(Game.COMMANDS, name) ~= nil).toBe(true)
			end
		end)
		it("D-101 正しい形は通る", function()
			local cases = {
				{ type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" },
				{ type = "SetPartySlot", partyIndex = 1, slot = 2 },
				{ type = "Sell", equipmentUids = { "eq_1", "eq_2" } },
				{ type = "HireStart" },
				{ type = "HireChoose", which = "previous" },
				{ type = "SetAutoSell", enabled = true, maxRarity = 2 },
				{ type = "OpenChests", pileKey = "special:rare:dng_sky_throne" }, -- D-166
				{ type = "BulkSell", equipmentUids = { "eq_1" } }, -- D-167
			}
			for _, c in cases do
				local ok, err = Protocol.validateCommand(c)
				expect({ ok, err }).toEqual({ true, nil })
			end
		end)
		it("D-101 サーバー専用・知らないコマンド・形の違うものは通さない", function()
			local bad = {
				"Dispatch",
				{ type = 1 },
				{ type = "GrantPurchase", productId = 1 },
				{ type = "Nope" },
				{ type = "Dispatch", partyIndex = 1.5, dungeonId = "dng_graveyard" }, -- 整数でない
				{ type = "Dispatch", partyIndex = 0, dungeonId = "dng_graveyard" }, -- 範囲外
				{ type = "Dispatch", partyIndex = 1 }, -- 必須がない
				{ type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard", extra = true }, -- 知らない引数
				{ type = "Unequip", adventurerUid = "adv_1", slot = "__index" }, -- 決まった値以外
				{ type = "Rename", adventurerUid = "adv_1", name = string.rep("あ", 30) }, -- 長すぎる
				{ type = "Sell", equipmentUids = { a = "eq_1" } }, -- 配列でない
				{ type = "SetLock", uid = "eq_1", locked = "yes" }, -- 真偽値でない
				{ type = "OpenChests", dungeonId = "dng_ruins" }, -- 宝箱の山は pileKey（D-166）
				{ type = "BulkSell" }, -- 対象の装備がない
			}
			for _, c in bad do
				local ok = Protocol.validateCommand(c)
				expect(ok).toBe(false)
			end
		end)
	end)

	-- ゲームを少し進めた状態の列（派遣・帰還・開封・雇用）
	local function playSteps(): { any }
		local s = Game.newState(master, 7, T0)
		local views = { Protocol.view(s, master) }
		local function step(cmd: any?, now: number)
			Game.advance(s, ctx(now))
			if cmd then
				Game.execute(s, cmd, ctx(now))
			end
			table.insert(views, Protocol.view(s, master))
		end
		step({ type = "SetAutoRepeat", partyIndex = 1, dungeonId = "dng_graveyard" }, T0)
		step({ type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, T0)
		step(nil, T0 + 600)
		step({ type = "OpenChests", pileKey = "dng_graveyard" }, T0 + 600)
		step({ type = "HireStart" }, T0 + 610)
		step({ type = "HirePick", candidateIndex = 1 }, T0 + 611)
		step({ type = "HireReroll" }, T0 + 612)
		step({ type = "HireChoose", which = "current" }, T0 + 613)
		step(nil, T0 + 1800)
		return views
	end

	describe("D-087 要約で隠す情報", function()
		it("D-087 乱数の元・宝箱のランクを要約に含めない", function()
			local s = Game.newState(master, 3, T0)
			Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx(T0))
			Game.advance(s, ctx(T0 + 600))
			Game.execute(s, { type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" }, ctx(T0 + 600))
			local v = Protocol.view(s, master)
			expect(v.seed).toBe(nil)
			expect(v.rngCounter).toBe(nil)
			expect(v.stats).toBe(nil)
			-- 宝箱は山ごとの数だけ（{ pileKey, count } の配列。特別な宝箱の山も含む：D-166）
			for _, c in v.chests do
				expect(type(c.pileKey)).toBe("string")
				expect(type(c.count)).toBe("number")
				expect(c.rank).toBe(nil)
			end
			-- 探索ログにランクが残っていない
			local json = serde.encode("json", v)
			expect(string.find(json, '"ranks"', 1, true)).toBe(nil)
			expect(string.find(json, '"rank"', 1, true)).toBe(nil)
			expect(string.find(json, '"clearChestRanks"', 1, true)).toBe(nil)
			for _, e in v.expeditions do
				expect(e.seed).toBe(nil)
				expect(type(e.log.rewards.chestCount)).toBe("number")
			end
		end)
		it(
			"D-087 D-166 要約の chests は特別な宝箱を含む全部の山の { pileKey, count } の配列（ランクは隠す）",
			function()
				local s = Game.newState(master, 3, T0)
				s.chests = {
					dng_ruins = { 2, 1 },
					dng_graveyard = { 4 },
					["special:raid"] = { 0, 0, 2 },
					["special:rare:dng_castle"] = { 0, 1 },
					["special:quest"] = { 0, 0 }, -- 空の山は出さない
				}
				local v = Protocol.view(s, master)
				-- 普通の山はダンジョンの順、続けて特別な宝箱の山を鍵の順
				expect(v.chests).toEqual({
					{ pileKey = "dng_graveyard", count = 4 },
					{ pileKey = "dng_ruins", count = 3 },
					{ pileKey = "special:raid", count = 2 },
					{ pileKey = "special:rare:dng_castle", count = 1 },
				})
				for _, c in v.chests do
					local n = 0
					for _ in c do
						n += 1
					end
					expect(n).toBe(2) -- pileKey と count だけ
				end
				expect(serde.decode("json", serde.encode("json", v.chests))).toEqual(v.chests)
				-- 宝箱がなければ空
				expect(Protocol.view(Game.newState(master, 3, T0), master).chests).toEqual({})
			end
		)
		it("D-192 他のプレイヤーの UserId を要約・events に入れない", function()
			local s = Game.newState(master, 3, T0)
			s.referral.rewardedInvitees = { ["12345"] = true }
			s.referral.claimedDeliveries = { ["referral:12345"] = true }
			s.referral.referredBy = 67890
			s.referral.weekCount = 1
			local v = Protocol.view(s, master)
			expect(v.referral.rewardedInvitees).toBe(nil)
			expect(v.referral.claimedDeliveries).toBe(nil)
			expect(v.referral.referredBy).toBe(nil)
			expect(v.referral.weekCount).toBe(1) -- ほかの項目は残す
			expect(v.referral.inviteeRewardDone).toBe(false)
			local json = serde.encode("json", v)
			expect(string.find(json, "12345", 1, true)).toBe(nil)
			expect(string.find(json, "67890", 1, true)).toBe(nil)
			-- 元の状態は変えない
			expect(s.referral.rewardedInvitees["12345"]).toBe(true)
			-- 紹介の結果の event から相手の UserId を除く
			local out = Protocol.redactEvents({
				{ type = "ReferralGranted", at = T0, role = "inviter", userId = 12345, inboxUid = "inb_1" },
			})
			expect(out[1].userId).toBe(nil)
			expect(out[1].role).toBe("inviter")
			expect(out[1].inboxUid).toBe("inb_1")
		end)
		it("D-087 events のランクは除く。開封結果（ChestsOpened）は残す", function()
			local events = {
				{ type = "ExpeditionReturned", chests = 2, detail = { ranks = { 1, 2 } } },
				{ type = "ChestsOpened", special = { { rank = 4, effect = true } } },
			}
			local out = Protocol.redactEvents(events)
			expect(out[1].detail.ranks).toBe(nil)
			expect(out[1].chests).toBe(2)
			expect(out[2].special[1].rank).toBe(4)
		end)
		it("D-103 要約は JSON にして戻しても同じ（辞書と配列を混ぜていない）", function()
			for _, v in playSteps() do
				expect(serde.decode("json", serde.encode("json", v))).toEqual(v)
			end
		end)
	end)

	describe("D-103 差分", function()
		local function roundTrip(a: any, b: any)
			local patched = Protocol.applyPatch(Protocol.deepCopy(a), Protocol.diff(a, b))
			expect(patched).toEqual(b)
		end
		it("D-103 値の変更・追加・削除・入れ子の辞書", function()
			local a = { gold = 1, equipment = { eq_1 = { grade = 0 }, eq_2 = { grade = 1 } }, x = { y = { z = 1 } } }
			local b = { gold = 5, equipment = { eq_1 = { grade = 2 }, eq_3 = { grade = 0 } }, x = { y = { z = 1 } } }
			local patch = Protocol.diff(a, b)
			roundTrip(a, b)
			-- 変わっていない x は差分に入らない。eq_1 は grade だけ
			for _, op in patch do
				expect(op.path[1] ~= "x").toBe(true)
			end
			local found = false
			for _, op in patch do
				if op.path[2] == "eq_1" then
					expect(op.path).toEqual({ "equipment", "eq_1", "grade" })
					found = true
				end
			end
			expect(found).toBe(true)
		end)
		it("D-103 配列は変わったら丸ごと置き換える", function()
			local a = { slots = { "adv_1", "adv_2", "", "" } }
			local b = { slots = { "adv_2", "adv_1", "", "" } }
			expect(Protocol.diff(a, b)).toEqual({ { path = { "slots" }, value = { "adv_2", "adv_1", "", "" } } })
			roundTrip(a, b)
		end)
		it("D-103 空の表・配列と辞書の入れ替わり・真偽値 false", function()
			roundTrip({ a = {}, b = { 1, 2 }, c = { k = 1 }, d = true }, { a = { 1 }, b = {}, c = {}, d = false })
			roundTrip({ a = { 1, 2 } }, { a = { k = "v" } })
			roundTrip({}, { gold = 0 })
			expect(Protocol.diff({ a = { b = 1 } }, { a = { b = 1 } })).toEqual({})
		end)
		it("D-103 ゲームを進めた状態でも、差分を当てると次の要約と一致する", function()
			local views = playSteps()
			for i = 2, #views do
				roundTrip(views[i - 1], views[i])
			end
		end)
		it("D-103 開封のような操作の差分は、全体よりずっと小さい", function()
			local views = playSteps()
			local full = #serde.encode("json", views[#views])
			local patch = Protocol.diff(views[#views - 1], views[#views])
			local size = #serde.encode("json", patch)
			expect(size < full).toBe(true)
		end)
	end)
end
