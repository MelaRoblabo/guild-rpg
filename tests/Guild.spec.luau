--!strict
local Chest = require("../src/core/Chest")
local Game = require("../src/core/Game")
local Guild = require("../src/core/Guild")
local Inventory = require("../src/core/Inventory")
local Fixtures = require("./helpers/Fixtures")

local T0 = 1767225600

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local master = Fixtures.master()

	local function ctx(now: number?)
		return { now = now or T0, master = master, online = true }
	end
	local function exec(s: any, cmd: any)
		return Game.execute(s, cmd, ctx())
	end

	describe("ギルドレベル（D-074）", function()
		it("D-074 経験値が貯まるとレベルが上がり、報酬のチケットがもらえる", function()
			local s = Game.newState(master, 1, T0)
			local need = Guild.expToNext(1, master)
			local reward = master.raw.GuildLevels.levels[2].rewards.itm_slot_ticket
			local events = {}
			Guild.addExp(s, need, master, events, T0)
			expect(s.guild.level).toBe(2)
			expect(s.items.itm_slot_ticket).toBe(reward)
			expect(events[1].type).toBe("GuildLevelUp")
		end)
		it("D-074 10の倍数のレベルでポーションももらえる", function()
			local s = Game.newState(master, 1, T0)
			local total = 0
			for lv = 1, 9 do
				total += Guild.expToNext(lv, master)
			end
			Guild.addExp(s, total, master, {}, T0)
			expect(s.guild.level).toBe(10)
			expect(s.items.itm_potion_appearance_change).toBe(1)
			expect(s.items.itm_potion_appearance_keep).toBe(1)
		end)
		it("最大レベルで止まる", function()
			local s = Game.newState(master, 1, T0)
			Guild.addExp(s, 10 ^ 12, master, {}, T0)
			expect(s.guild.level).toBe(Guild.maxLevel(master))
			expect(s.guild.exp).toBe(0)
		end)
	end)

	describe("拡張（08章 §4、D-075）", function()
		it(
			"D-075 パーティ枠はダンジョンの踏破とゴールドが必要。買うとパーティが増える",
			function()
				local s = Game.newState(master, 1, T0)
				s.gold = 10 ^ 9
				expect(exec(s, { type = "BuyExpansion", expansionId = "exp_party" }).error).toBe("DUNGEON_NOT_CLEARED")
				s.clearedDungeons.dng_ruins = true
				expect(exec(s, { type = "BuyExpansion", expansionId = "exp_party" }).ok).toBeTruthy()
				expect(#s.parties).toBe(2)
				expect(s.parties[2].slots).toEqual({ "", "", "", "" })
			end
		)
		it("ギルドレベルが足りなければ買えない", function()
			local s = Game.newState(master, 1, T0)
			s.gold = 10 ^ 9
			expect(exec(s, { type = "BuyExpansion", expansionId = "exp_candidate" }).error).toBe("GUILD_LEVEL_TOO_LOW")
		end)
		it("ゴールドが足りなければ買えず、買えば減る", function()
			local s = Game.newState(master, 1, T0)
			s.guild.level = 100
			s.gold = 0
			expect(exec(s, { type = "BuyExpansion", expansionId = "exp_warehouse" }).error).toBe("NOT_ENOUGH_GOLD")
			local step = master.expansions.exp_warehouse.steps[1]
			s.gold = step.gold
			expect(exec(s, { type = "BuyExpansion", expansionId = "exp_warehouse" }).ok).toBeTruthy()
			expect(s.gold).toBe(0)
			expect(s.expansions.warehouseSize).toBe(step.value)
		end)
		it("最後まで買うと EXPANSION_MAXED", function()
			local s = Game.newState(master, 1, T0)
			s.guild.level = 100
			s.gold = 10 ^ 12
			for _ in master.expansions.exp_candidate.steps do
				expect(exec(s, { type = "BuyExpansion", expansionId = "exp_candidate" }).ok).toBeTruthy()
			end
			expect(exec(s, { type = "BuyExpansion", expansionId = "exp_candidate" }).error).toBe("EXPANSION_MAXED")
		end)
	end)

	describe("自動売却（06章 §6）", function()
		local function withChests(n: number, rank: number)
			local s = Game.newState(master, 1, T0)
			for _ = 1, n do
				Chest.add(s, "dng_ruins", rank, 1)
			end
			-- 初めて開ける宝箱の確定の装備（D-246 ①）は FirstChest.spec で見る。ここは普通の宝箱の決まりだけを見る
			s.stats.firstChestOpenedAt = T0
			return s
		end
		it("指定レアリティ以下の装備は開封時に売る（修飾語つきは残す）", function()
			local s = withChests(50, 1)
			exec(s, { type = "SetAutoSell", enabled = true, maxRarity = 1, keepModified = true })
			local gold0 = s.gold
			exec(s, { type = "OpenChests", pileKey = "dng_ruins" })
			for _, e in s.equipment do
				if e.equippedBy == nil then
					expect(e.modifierId ~= nil).toBeTruthy()
				end
			end
			expect(s.gold > gold0).toBeTruthy()
		end)
		it("指定より高いレアリティは売らない", function()
			local s = withChests(10, 3)
			exec(s, { type = "SetAutoSell", enabled = true, maxRarity = 2, keepModified = false })
			exec(s, { type = "OpenChests", pileKey = "dng_ruins" })
			expect(Inventory.warehouseUsage(s) > 0).toBeTruthy()
		end)
		it("無効なら売らない", function()
			local s = withChests(10, 1)
			exec(s, { type = "SetAutoSell", enabled = false }) -- 初期値はオン（D-167）なので切る
			exec(s, { type = "OpenChests", pileKey = "dng_ruins" })
			expect(Inventory.warehouseUsage(s) >= 10).toBeTruthy()
		end)
	end)

	describe("設定（D-117・D-237 ③）", function()
		it("D-237 ③ 保存がなければ初期値、送った項目だけ変わる", function()
			local s = Game.newState(master, 1, T0)
			local p = Game.query.preferences(s, master)
			expect(p.musicVolume).toBe(master.raw.StarterSet.preferences.musicVolume)
			expect(p.chestAnimation).toBe(true)
			expect(exec(s, { type = "SetSettings", musicVolume = 3, cutIns = false }).ok).toBe(true)
			p = Game.query.preferences(s, master)
			expect(p.musicVolume).toBe(3)
			expect(p.cutIns).toBe(false)
			expect(p.otherCarts).toBe(true)
		end)
		it("音量は 0〜volumeSteps", function()
			local s = Game.newState(master, 1, T0)
			expect(exec(s, { type = "SetSettings", soundVolume = master.K.volumeSteps + 1 }).error).toBe(
				"INVALID_VOLUME"
			)
		end)
	end)

	describe("一覧の並べ方と一括売却の上限（D-117・D-231 ⑮）", function()
		it(
			"D-231 ⑮ 保存がなければ初期値（Lv の高い順・レアリティの高い順・一括売却の上限はレア）",
			function()
				local s = Game.newState(master, 1, T0)
				local p = Game.query.listPrefs(s, master)
				expect(p.advSort).toBe("level")
				expect(p.advDesc).toBe(true)
				expect(p.whSort).toBe("rarity")
				expect(p.bulkSellMaxRarity).toBe(3)
			end
		)
		it("D-117 送った項目だけ変わり、保存される", function()
			local s = Game.newState(master, 1, T0)
			expect(exec(s, { type = "SetListPrefs", advSort = "attack", advDesc = false }).ok).toBe(true)
			expect(exec(s, { type = "SetListPrefs", bulkSellMaxRarity = 4 }).ok).toBe(true)
			local p = Game.query.listPrefs(s, master)
			expect(p.advSort).toBe("attack")
			expect(p.advDesc).toBe(false)
			expect(p.whSort).toBe("rarity")
			expect(p.bulkSellMaxRarity).toBe(4)
			expect(s.settings.listPrefs.bulkSellMaxRarity).toBe(4)
		end)
		it("不正な並べ替え・レアリティは断る", function()
			local s = Game.newState(master, 1, T0)
			expect(exec(s, { type = "SetListPrefs", whSort = "level" }).error).toBe("INVALID_SORT")
			expect(exec(s, { type = "SetListPrefs", bulkSellMaxRarity = master.rarityCount + 1 }).error).toBe(
				"INVALID_RARITY"
			)
			expect(s.settings.listPrefs).toBe(nil)
		end)
	end)

	describe("ユニークの初回踏破報酬（02章 §2）", function()
		it("騎士の古城の初回踏破で白銀のブランが加入する（1回だけ）", function()
			local s = Game.newState(master, 1, T0)
			local events = {}
			-- 踏破した探索を直接作る
			s.expeditions.ex_test = {
				uid = "ex_test",
				partyIndex = 1,
				dungeonId = "dng_castle",
				seed = 1,
				departAt = T0,
				returnAt = T0 + 10,
				memberUids = {},
				log = {
					result = "clear",
					rewards = { exp = {}, gold = 0, chests = {}, items = {}, floorsCleared = 13, guildExp = 0 },
				},
			}
			for _, e in Game.advance(s, ctx(T0 + 10)) do
				table.insert(events, e)
			end
			local joined = 0
			for _, e in events do
				if e.type == "UniqueJoined" then
					joined += 1
					expect(e.uniqueId).toBe("uni_bran")
				end
			end
			expect(joined).toBe(1)
		end)
	end)
end
