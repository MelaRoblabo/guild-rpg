--!strict
-- セーブデータの移行（docs/system/03_state_model.md「セーブの移行」）
-- 形式を変えたら CURRENT を上げ、STEPS[旧版] に旧版→新版の変換を追加する。
-- M7b は段階ごとに version を上げる（v5→v6 は M7b-2、以降の段階は v6→v7 …）。
-- マスターデータが要る手順（売却価格・初期値）があるので、migrate には master を渡す。

local ExclusiveGift = require("./ExclusiveGift")

local Migration = {}

Migration.CURRENT = 13

local STEPS: { [number]: (any, any) -> () } = {
	-- [1] = function(state) ... state.version = 2 end,
	-- v1 → v2：トレーニング場（D-077）と解錠技術（D-078）
	[1] = function(state)
		state.expansions.trainingLevel = state.expansions.trainingLevel or 1
		state.expansions.unlockRank = state.expansions.unlockRank or 2
		state.version = 2
	end,
	-- v2 → v3：宝箱を「ダンジョン×ランクの数」で持つ（D-084）
	[2] = function(state)
		local counts = {}
		for _, c in state.chests do
			counts[c.dungeonId] = counts[c.dungeonId] or { 0, 0, 0, 0, 0 }
			counts[c.dungeonId][c.rank] += 1
		end
		state.chests = counts
		state.version = 3
	end,
	-- v3 → v4：解錠技術をダンジョン単位に（D-088）。旧ランクの上限を近い難度に置き換える
	[3] = function(state)
		local ex = state.expansions
		if ex then
			ex.unlockTier = math.max(2, 2 * ((ex.unlockRank or 2) - 1))
			ex.unlockRank = nil
		end
		state.version = 4
	end,
	-- v4 → v5：解錠技術を廃止（D-091）
	[4] = function(state)
		if state.expansions then
			state.expansions.unlockTier = nil
		end
		state.version = 5
	end,
	-- v5 → v6（M7b-2。D-177 のうちこの段階の分）
	--   宝箱の鍵：dungeonId のまま宝箱の山の鍵として使う（変換しない。D-166）
	--   自動売却：初期値（オン）に合わせる（D-167）
	--   売却用アイテム：持っている分を今までと同じ売却価格で売ってゴールドにする（D-167）
	[5] = function(state, master)
		assert(master, "version 5 → 6 の移行には master が要る")
		state.settings = state.settings or {}
		state.settings.autoSell = table.clone(master.raw.StarterSet.autoSell)
		local items = state.items or {}
		local ids = {}
		for itemId in items do
			table.insert(ids, itemId)
		end
		table.sort(ids)
		for _, itemId in ids do
			local item = master.items[itemId]
			local n = items[itemId]
			if item and item.kind == "sellable" then
				if n > 0 then
					local gold = item.sellPrice * n
					state.gold = (state.gold or 0) + gold
					if state.stats then
						state.stats.goldFromSales = (state.stats.goldFromSales or 0) + gold
					end
				end
				items[itemId] = nil
			end
		end
		state.version = 6
	end,
	-- v6 → v7（M7b-3。留守番・休息ボーナス・日替わりの特性：D-161, D-156）
	--   lastSavedAt：lastAdvancedAt を入れる / restBonusSeconds：0
	--   探索の offline・dailyTraitId：nil のまま（旧版の探索は普通の探索で、特性なし）
	[6] = function(state)
		if state.lastSavedAt == nil then
			state.lastSavedAt = state.lastAdvancedAt
		end
		state.restBonusSeconds = state.restBonusSeconds or 0
		state.version = 7
	end,
	-- v7 → v8（M7b-4 前半。受け取り箱・クエスト・ログインボーナス・プレイ時間：D-164, D-153, D-155, D-154）
	--   quests：空（次のオンラインの advance で今日・今週の分を作る）
	--   login：lastDayIndex = -1, day = 1, cycle = 1（次のオンラインの advance で1日目）
	--   playtime：dayIndex = -1, seconds = 0, claimedSteps = 0
	--   inbox：空
	-- 形は Quest.newState・Login.newState・Playtime.newState と同じ（循環を避けるためここに書く）
	[7] = function(state)
		state.quests = state.quests
			or {
				daily = { dayIndex = -1, entries = {}, bonusDone = false },
				weekly = { weekIndex = -1, entries = {}, bonusDone = false },
			}
		state.login = state.login or { lastDayIndex = -1, day = 1, cycle = 1 }
		state.playtime = state.playtime or { dayIndex = -1, seconds = 0, claimedSteps = 0 }
		state.inbox = state.inbox or {}
		state.version = 8
	end,
	-- v8 → v9（M7b-4 後半の担当A。フレンドボタン・紹介・専用ギフト：D-157, D-180, D-165, D-177, D-185）
	--   friend：nextAt = 0, dayIndex = -1, todayCount = 0
	--   referral：まだ何も受け取っていない形（届け物の id の記録・招待した人へ届けた印を含む）
	--   ユニークの冒険者：専用ギフトを足す。枠がいっぱいなら giftIds の先頭（一番古いギフト）と入れ替える
	-- 形は Friend.newState・Friend.newReferralState と同じ（循環を避けるためここに書く）
	[8] = function(state, master)
		assert(master, "version 8 → 9 の移行には master が要る")
		state.friend = state.friend or { nextAt = 0, dayIndex = -1, todayCount = 0 }
		state.referral = state.referral
			or {
				inviteeRewardDone = false,
				inviterDelivered = false,
				rewardedInvitees = {},
				claimedDeliveries = {},
				weekIndex = -1,
				weekCount = 0,
			}
		local uids = {}
		for uid in state.adventurers or {} do
			table.insert(uids, uid)
		end
		table.sort(uids)
		for _, uid in uids do
			ExclusiveGift.grant(state.adventurers[uid], master)
		end
		state.version = 9
	end,
	-- v9 → v10（M7b-4 後半・担当B。マップイベント・レアダンジョン・レイド・旅の商人：D-152, D-175）
	--   expeditions[*] の eventSlot・raidDamage・arriveAt・chestPile：nil のまま（旧版の探索は普通の探索）
	--   equipment[*].fromMerchant：nil のまま（旧版の装備は商人で買ったものではない）
	--   merchant・raid・rareDungeonSlots：nil のまま（参加したイベントはない）
	[9] = function(state)
		state.merchant = nil
		state.raid = nil
		state.rareDungeonSlots = nil
		state.version = 10
	end,
	-- v10 → v11（M7b-5 の決定 D-195・D-196 の反映）
	--   stats.rebirths（転生回数の累計。紹介の進み具合：D-195）：今いる冒険者の rebirthCount の合計を下限にする
	--     （すでに数えている累計のほうが大きければそのまま。解雇した冒険者の分を失わない）
	--   loginTimes：空（次のログインからサーバーが足す：D-196）
	--   settings.notifyPrompt：firstReturn = false, loginDay2 = false（通知の許可の画面をまだ出していない：D-196）
	-- 形は Notify.newPromptState と同じ（循環を避けるためここに書く）
	[10] = function(state)
		local sum = 0
		for _, a in state.adventurers or {} do
			sum += a.rebirthCount or 0
		end
		state.stats = state.stats or {}
		state.stats.rebirths = math.max(state.stats.rebirths or 0, sum)
		state.loginTimes = state.loginTimes or {}
		state.settings = state.settings or {}
		state.settings.notifyPrompt = state.settings.notifyPrompt or { firstReturn = false, loginDay2 = false }
		state.version = 11
	end,
	-- v11 → v12（M8-2 の決定 D-228）
	--   parties[*].lastDungeonId（最後の行き先。「同じ所へ再出発」の行き先）：今いる普通の探索があればその行き先、
	--   なければ自動再派遣の行き先、どちらもなければ nil
	[11] = function(state)
		for _, party in state.parties or {} do
			if party.lastDungeonId == nil then
				for _, e in state.expeditions or {} do
					if e.partyIndex == party.index and e.eventSlot == nil and e.raidDamage == nil then
						party.lastDungeonId = e.dungeonId
					end
				end
				if party.lastDungeonId == nil and party.autoRepeat then
					party.lastDungeonId = party.autoRepeat.dungeonId
				end
			end
		end
		state.version = 12
	end,
	-- v12 → v13（D-280）：休息ボーナスを廃止。restBonusSeconds を消す
	[12] = function(state)
		state.restBonusSeconds = nil
		state.version = 13
	end,
}

function Migration.migrate(state: any, master: any?): any
	assert(type(state) == "table" and type(state.version) == "number", "セーブデータに version がない")
	assert(state.version <= Migration.CURRENT, `未来の版のセーブデータ: {state.version}`)
	while state.version < Migration.CURRENT do
		local step = STEPS[state.version]
		assert(step, `移行手順がない: {state.version}`)
		step(state, master)
	end
	return state
end

return Migration
