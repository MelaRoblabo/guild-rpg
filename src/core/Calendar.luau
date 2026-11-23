--!strict
-- 日・週の番号（D-168、docs/system/06_formulas.md §11）
-- 日・週で区切る処理（クエスト・プレイ時間・ログインボーナス・日替わり・今週の訪問者）はすべてここから使う。
-- 時刻は呼び出し側の ctx.now を受け取る。os.time・os.date は使わない（08章）。
-- 下の数は暦の決まり（1日の秒数・1週の日数・1970-01-01 が木曜であること）で、ゲームの調整値ではない。

local Calendar = {}

local SECONDS_PER_DAY = 86400
local DAYS_PER_WEEK = 7
local EPOCH_TO_MONDAY = 3 -- 1970-01-01 は木曜。+3 日で週の始まりを月曜に合わせる

-- 日の番号：UTC 0時（日本の朝9時）で区切る
function Calendar.dayIndex(now: number): number
	return math.floor(now / SECONDS_PER_DAY)
end

-- 週の番号：月曜の UTC 0時で区切る
function Calendar.weekIndex(now: number): number
	return math.floor((Calendar.dayIndex(now) + EPOCH_TO_MONDAY) / DAYS_PER_WEEK)
end

-- その日の区切りの時刻（プレイ時間を日の区切りで分けるのに使う：06章 §20）
function Calendar.dayStart(now: number): number
	return Calendar.dayIndex(now) * SECONDS_PER_DAY
end

-- 次の日の区切りの時刻（画面の残り時間・「明日の日替わり」の表示用）
function Calendar.nextDayStart(now: number): number
	return (Calendar.dayIndex(now) + 1) * SECONDS_PER_DAY
end

-- 次の週の区切り（月曜 UTC 0時）の時刻（今週の訪問者の残り日数の表示用：D-158）
function Calendar.nextWeekStart(now: number): number
	return ((Calendar.weekIndex(now) + 1) * DAYS_PER_WEEK - EPOCH_TO_MONDAY) * SECONDS_PER_DAY
end

return Calendar
