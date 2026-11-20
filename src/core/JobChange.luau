--!strict
-- 転職（ゲーム仕様書03章 §4、D-045, D-052、企画書§16.7 仮採用）

local Inventory = require("./Inventory")

local JobChange = {}

-- 転職ポーションのアイテムID
function JobChange.potionId(jobId: string): string
	return "itm_potion_job_" .. string.gsub(jobId, "^job_", "")
end

-- 転職できるか（できなければエラーコード）
function JobChange.check(adv: any, jobId: string, master: any): string?
	local job = master.jobs[jobId]
	if not job then
		return "JOB_NOT_FOUND"
	end
	if adv.jobId == jobId then
		return "SAME_JOB"
	end
	if adv.uniqueId then
		local u = master.uniques[adv.uniqueId]
		if u.jobChange == "none" then
			return "UNIQUE_JOB_RESTRICTED"
		end
		if u.jobChange == "line" and master.jobs[adv.jobId].line ~= job.line then
			return "UNIQUE_JOB_RESTRICTED"
		end
	end
	return nil
end

-- 新しい職業で装備できなくなる装備の枠
function JobChange.unequippableSlots(state: any, adv: any, jobId: string, master: any): { string }
	local out = {}
	for _, slot in Inventory.SLOTS do
		local uid = adv.equipment[slot]
		if uid and not Inventory.canEquip(jobId, state.equipment[uid].baseId, master) then
			table.insert(out, slot)
		end
	end
	return out
end

return JobChange
