--!strict
-- シミュレーション用のパーティ（docs/system/09_cli_sim_autoplay.md §2）
-- 基礎ステータス＝雇用範囲の中央値＋職業の成長基準値×(Lv−1)（振れ幅なしの平均的な個体）

local Presets = {}

local JOB_GEAR = {
	job_warrior = { weapon = "eq_wpn_sword", armor = "eq_arm_chainmail", sub = "eq_sub_buckler" },
	job_knight = { weapon = "eq_wpn_sword", armor = "eq_arm_chainmail", sub = "eq_sub_buckler" },
	job_thief = { weapon = "eq_wpn_dagger", armor = "eq_arm_leather", sub = "eq_sub_ring_wind" },
	job_ninja = { weapon = "eq_wpn_dagger", armor = "eq_arm_leather", sub = "eq_sub_ring_wind" },
	job_mage = { weapon = "eq_wpn_staff", armor = "eq_arm_robe", sub = "eq_sub_ring_wisdom" },
	job_sage = { weapon = "eq_wpn_staff", armor = "eq_arm_robe", sub = "eq_sub_ring_wisdom" },
	job_priest = { weapon = "eq_wpn_mace", armor = "eq_arm_vestment", sub = "eq_sub_ring_wisdom" },
	job_bishop = { weapon = "eq_wpn_mace", armor = "eq_arm_vestment", sub = "eq_sub_ring_wisdom" },
}

local STATS = { "str", "mag", "agi", "dex", "hp" }

-- メンバー定義を作る
function Presets.member(
	master: any,
	jobId: string,
	slot: number,
	level: number,
	rarity: number,
	grade: number,
	giftIds: { string }?
)
	local K = master.K
	local job = master.jobs[jobId]
	local base = {}
	for _, s in STATS do
		local r = K.hireStatRange[s]
		base[s] = math.floor((r.min + r.max) / 2) + job.growth[s] * (level - 1)
	end
	local gear = JOB_GEAR[jobId]
	local equipment = {}
	for slotName, baseId in gear do
		equipment[slotName] = { baseId = baseId, rarity = rarity, grade = grade }
	end
	return {
		uid = `sim_{slot}_{jobId}`,
		slot = slot,
		jobId = jobId,
		baseStats = base,
		giftIds = giftIds or {},
		equipment = equipment,
	}
end

local BALANCED = { "job_warrior", "job_thief", "job_mage", "job_priest" }

local function party(
	master: any,
	jobs: { string },
	level: number,
	rarity: number,
	grade: number,
	gifts: { [number]: { string } }?
)
	local members = {}
	for i, jobId in jobs do
		table.insert(members, Presets.member(master, jobId, i, level, rarity, grade, gifts and gifts[i]))
	end
	return members
end

-- 名前 → 作り方。level / rarity は成長段階の目安（仮）
Presets.list = {
	{
		name = "starter",
		desc = "初期状態 Lv1・コモン+0（Q-020）",
		build = function(m)
			return party(m, BALANCED, 1, 1, 0)
		end,
	},
	{
		name = "lv5",
		desc = "Lv5・コモン+1",
		build = function(m)
			return party(m, BALANCED, 5, 1, 1)
		end,
	},
	{
		name = "lv10",
		desc = "Lv10・アンコモン+0",
		build = function(m)
			return party(m, BALANCED, 10, 2, 0)
		end,
	},
	{
		name = "lv15",
		desc = "Lv15・アンコモン+1",
		build = function(m)
			return party(m, BALANCED, 15, 2, 1)
		end,
	},
	{
		name = "lv20",
		desc = "Lv20・レア+0",
		build = function(m)
			return party(m, BALANCED, 20, 3, 0)
		end,
	},
	{
		name = "lv30",
		desc = "Lv30・レア+2",
		build = function(m)
			return party(m, BALANCED, 30, 3, 2)
		end,
	},
	{
		name = "lv20_phys",
		desc = "Lv20 物理偏重（戦士・戦士・盗賊・盗賊）",
		build = function(m)
			return party(m, { "job_warrior", "job_warrior", "job_thief", "job_thief" }, 20, 3, 0)
		end,
	},
	{
		name = "lv20_magic",
		desc = "Lv20 魔法偏重（戦士・魔法使い・魔法使い・僧侶）",
		build = function(m)
			return party(m, { "job_warrior", "job_mage", "job_mage", "job_priest" }, 20, 3, 0)
		end,
	},
	{
		name = "lv20_nohealer",
		desc = "Lv20 回復なし（戦士・盗賊・魔法使い・魔法使い）",
		build = function(m)
			return party(m, { "job_warrior", "job_thief", "job_mage", "job_mage" }, 20, 3, 0)
		end,
	},
	{
		name = "lv20_gifts",
		desc = "Lv20 ギフト持ち（頑健・罠師の勘・退魔の才・幸運）",
		build = function(m)
			return party(m, BALANCED, 20, 3, 0, {
				[1] = { "gift_sturdy" },
				[2] = { "gift_trapsense" },
				[3] = { "gift_exorcist" },
				[4] = { "gift_lucky" },
			})
		end,
	},
}

function Presets.get(name: string)
	for _, p in Presets.list do
		if p.name == name then
			return p
		end
	end
	return nil
end

return Presets
