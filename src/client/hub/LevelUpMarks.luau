--!strict
-- レベルが上がった冒険者の印（D-246 ④）。純粋なモジュール（Lune でテストする）。
--   帰還のトーストが LevelUp の出来事で note し、パーティの面が lit で「今 Lv を光らせるか」を聞く。
--   初めて聞かれたときから LIT_SECONDS の間だけ光らせる（面を作り直しても続く）。その後は消える。

local LevelUpMarks = {}

LevelUpMarks.LIT_SECONDS = 1.5 -- 光らせる長さ（画面の動きの長さ。ゲームの数値ではない）

-- 値：0＝まだ見せていない、正の数＝光らせ終わる時刻
local marks: { [string]: number } = {}

function LevelUpMarks.note(uid: string)
	marks[uid] = 0
end

function LevelUpMarks.lit(uid: string, now: number): boolean
	local t = marks[uid]
	if t == nil then
		return false
	end
	if t == 0 then
		marks[uid] = now + LevelUpMarks.LIT_SECONDS
		return true
	end
	if now < t then
		return true
	end
	marks[uid] = nil
	return false
end

function LevelUpMarks.clear()
	table.clear(marks)
end

return LevelUpMarks
