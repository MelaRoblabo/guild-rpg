--!strict
-- S-15 の攻略ヒントと適性の4人（D-048・D-113・D-114・D-231 ⑤・D-232 ⑨・D-235 ①②）。純粋な関数（Lune でテストする）。
--   - 攻撃の種類の割合（物理：魔法）、多い種族（出現の重みの多い順の英語の短い語）、罠Lv、フロア数。
--   - 有利な攻撃区分：敵の防御の低い方を突ける区分。物理防御＝魔法防御なら有利なし（D-235 ②）。
--   - 適性の4人：有利な区分か→Lv→攻撃力（D-114）。onlyFree なら探索中・ほかのパーティの探索中の人を除く（D-235 ①）。
--   - パーティから：罠の避けやすさ（06章 §5。技巧×罠師の勘の合計）と片道の移動時間（06章 §4）。
--   - core の関数は呼び出し側から deps で受け取る（Roblox と Lune で require の道が違うため）。

export type Deps = {
	weights: (dungeonId: string?, master: any) -> (number, number), -- AutoEquip.weights
	snapshot: (state: any, uid: string, master: any) -> any, -- Game.query.snapshot
	busy: (state: any, uid: string) -> boolean, -- Party.isAdventurerBusy
	partySnapshots: (state: any, partyIndex: number, master: any) -> { any }, -- Game.query.partySnapshots
	trapEvadeRate: (dexSum: number, trapLevel: number, K: any) -> number, -- Formulas.trapEvadeRate
	travelSeconds: (snaps: { any }, dungeon: any, K: any, mult: number?) -> number, -- Formulas.travelSeconds
	partyTravelMult: (snaps: { any }, master: any) -> number, -- ExclusiveGift.partyEffects(...).travelMult
}

local Hint = {}

-- 種族の短い語（D-231 ⑤：アイコンにせず語。英語は仮）
Hint.RACE_WORD = {
	undead = "Undead",
	demon = "Demon",
	beast = "Beast",
	construct = "Construct",
	plant = "Plant",
	spirit = "Spirit",
	aquatic = "Aquatic",
	dragon = "Dragon",
	knight = "Knight",
}

-- 多い種族（出現の重みの多い順）：{ { tag, word, weight } }
function Hint.races(dungeon: any, master: any): { any }
	local by: { [string]: number } = {}
	for _, m in dungeon.monsters do
		local mon = master.monsters[m.id]
		if mon then
			by[mon.raceTag] = (by[mon.raceTag] or 0) + m.weight
		end
	end
	local out = {}
	for tag, w in by do
		table.insert(out, { tag = tag, word = Hint.RACE_WORD[tag] or tag, weight = w })
	end
	table.sort(out, function(a, b)
		if a.weight ~= b.weight then
			return a.weight > b.weight
		end
		return a.tag < b.tag
	end)
	return out
end

-- 有利な攻撃区分（"physical" / "magic" / nil＝有利なし）
function Hint.favored(dungeon: any): string?
	local b = dungeon.base
	if b.pdef < b.mdef then
		return "physical"
	elseif b.mdef < b.pdef then
		return "magic"
	end
	return nil
end

-- 適性の4人（D-114・D-235）
function Hint.suited(state: any, dungeon: any, onlyFree: boolean, master: any, deps: Deps): { string }
	local fav = Hint.favored(dungeon)
	local rows = {}
	for uid, adv in state.adventurers do
		if not (onlyFree and deps.busy(state, uid)) then
			local job = master.jobs[adv.jobId]
			local snap = deps.snapshot(state, uid, master)
			table.insert(rows, {
				uid = uid,
				fav = if fav and job and job.attackType == fav then 1 else 0,
				level = adv.level,
				atk = snap.atk,
			})
		end
	end
	table.sort(rows, function(a, b)
		if a.fav ~= b.fav then
			return a.fav > b.fav
		end
		if a.level ~= b.level then
			return a.level > b.level
		end
		if a.atk ~= b.atk then
			return a.atk > b.atk
		end
		return a.uid < b.uid
	end)
	local out = {}
	for i = 1, math.min(4, #rows) do
		table.insert(out, rows[i].uid)
	end
	return out
end

-- パーティからの見込み：罠の避けやすさ（0〜1）と片道の移動時間（秒）
function Hint.forParty(state: any, partyIndex: number, dungeon: any, master: any, deps: Deps): (number, number)
	local snaps = deps.partySnapshots(state, partyIndex, master)
	local dexSum = 0
	for _, s in snaps do
		dexSum += s.dex * s.trapDexMult
	end
	local evade = deps.trapEvadeRate(dexSum, dungeon.trapLevel, master.K)
	local travel = if #snaps > 0
		then deps.travelSeconds(snaps, dungeon, master.K, deps.partyTravelMult(snaps, master))
		else 0
	return evade, travel
end

return Hint
