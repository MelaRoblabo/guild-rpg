--!strict
-- ギルドレベル（ゲーム仕様書08章 §3、D-074、Q-017）
-- state.guild.exp は「次のレベルまでの進み具合」。累計は stats.guildExpTotal。
-- レベルアップ報酬（チケット・ポーション）は src/data/GuildLevels.luau

local Inventory = require("./Inventory")

local Guild = {}

function Guild.maxLevel(master: any): number
	return master.raw.GuildLevels.maxLevel
end

function Guild.expToNext(level: number, master: any): number?
	local row = master.raw.GuildLevels.levels[level]
	return if row then row.expToNext else nil
end

-- ギルド経験値を加え、レベルアップと報酬を処理する。events に GuildLevelUp を積む
function Guild.addExp(state: any, amount: number, master: any, events: { any }, at: number)
	state.stats.guildExpTotal = (state.stats.guildExpTotal or 0) + amount
	state.guild.exp += amount
	local max = Guild.maxLevel(master)
	while state.guild.level < max do
		local need = Guild.expToNext(state.guild.level, master)
		if need == nil or state.guild.exp < need then
			break
		end
		state.guild.exp -= need
		state.guild.level += 1
		local row = master.raw.GuildLevels.levels[state.guild.level]
		local rewards = if row then row.rewards else {}
		for itemId, n in rewards do
			Inventory.gainItem(state, itemId, n, master) -- 売却用アイテムなら売る（D-167）
			if itemId == "itm_slot_ticket" then
				state.stats.ticketsFromGuild = (state.stats.ticketsFromGuild or 0) + n
			end
		end
		table.insert(events, { type = "GuildLevelUp", at = at, level = state.guild.level, rewards = rewards })
	end
	if state.guild.level >= max then
		state.guild.exp = 0
	end
end

return Guild
