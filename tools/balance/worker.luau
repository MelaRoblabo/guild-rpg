--!strict
-- 成績表の1回分（MB）：自動プレイ（1日の流れ）を1つの型・seed で回し、指標を JSON で書く
-- tools/balance（init.luau）が別のプロセスとして並べて起動する。直接使うときは：
--   lune run tools/balance/worker -- --profile core --seed 1 --days 45 --metrics daysToMaxGrowth,shareGold --out out/balance/x.json
--   [--friends N] [--set パス=値 ...]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Data = require("../../src/data")
local MasterData = require("../../src/core/MasterData")
local Days = require("../autoplay/Days")
local Experience = require("./Experience")
local Policy = require("../autoplay/Policy")
local Schedule = require("../autoplay/Schedule")
local Metrics = require("./Metrics")
local Overrides = require("./Overrides")

local opts: any = { profile = "core", seed = 1, days = 30, policy = "greedy", metrics = {}, sets = {} }
do
	local a = process.args
	local i = 1
	while i <= #a do
		local k, v = a[i], a[i + 1]
		if k == "--" then
			i += 1
			continue
		elseif k == "--profile" then
			opts.profile = v
		elseif k == "--seed" then
			opts.seed = tonumber(v)
		elseif k == "--days" then
			opts.days = tonumber(v)
		elseif k == "--friends" then
			opts.friends = tonumber(v)
		elseif k == "--metrics" then
			opts.metrics = string.split(v, ",")
		elseif k == "--set" then
			table.insert(opts.sets, Overrides.parse(v))
		elseif k == "--out" then
			opts.out = v
		elseif k == "--timeline-out" then
			opts.timelineOut = v
		else
			error(`未知の引数: {k}`)
		end
		i += 2
	end
end
assert(opts.out, "--out が必要")

Overrides.apply(Data, opts.sets)
local master = MasterData.load(Data)
Policy.use(opts.policy)
Policy.configure(Schedule.behavior)

local started = os.clock()
-- 体験の指標（MX）：出来事を記録する
local exp = Experience.new()
opts.trace = Experience.collector(exp)
local r = Days.run(opts, master)
local endAt = r.reachedAt or (r.firstLogin + r.finishedDays * 86400)
r.experience = Experience.finish(exp, endAt, r.onlinePerDay)
local metrics = Metrics.computeAutoplay(r, opts.metrics)
if opts.timelineOut then
	fs.writeFile(opts.timelineOut, serde.encode("json", Experience.timeline(exp), true))
end
fs.writeFile(
	opts.out,
	serde.encode("json", {
		profile = opts.profile,
		seed = opts.seed,
		friends = r.friends,
		days = opts.days,
		elapsed = os.clock() - started,
		metrics = metrics,
	}, true)
)
