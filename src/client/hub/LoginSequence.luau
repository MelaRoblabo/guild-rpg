--!strict
-- ログインの流れ（D-132・D-208・D-281）。ログイン（reason "load"）で届いた出来事から、
--   S-01 まとめ（受け取った報酬があるとき：D-281）
--   → 留守の間に帰ったパーティの獲得演出（パーティごとに左の帰還のトースト。画面を閉じてから出す：D-281）
--   → カットイン（最大1回。設定でオフなら出さない）→ カレンダー（ログインボーナスが届いた日）
--   の順に1枚ずつ出す。次へで差し替え、最後の次へで閉じる。B・Esc で閉じたら残りは出さない。
--   休息ボーナスは廃止（D-280）。
--   カレンダーは初回の誘導を終えるまで出さず、終えたら画面が空いたときに出す（D-289。時機は Guide.CALENDAR_AFTER）。
--   ログインボーナスは留守の計算ではなく、ログイン直後の最初のオンラインの時間経過で届く（D-155、Game の advanceOnline）。
--   そのため LoginBonus はログインの知らせとは別に受け取り、流れの途中なら最後につなぎ、そうでなければ画面が空いたときに出す。

local Game = require("@game/ReplicatedStorage/Core/Game")
local Guide = require("./Guide")
local LoginFlow = require("../login/LoginFlow")
local Nav = require("../ui/Nav")
local ReturnToast = require("./ReturnToast")
local Session = require("../Session")
local master = require("../Master")

local LoginSequence = {}

type Step = { id: string, params: any }

local started = false
local steps: { Step } = {}
local index = 0
local running = false
local calendarShown = false
local startDone = false -- ログインのまとめを出し終えたか（それより先に届いたログインボーナスは、まとめの後ろにつなぐ）
local pendingCalendar: Step? = nil
local opened = false -- 流れの画面が開いているか（トーストの間は閉じている）
local inToasts = false -- 帰還のトーストを出している間（D-281）
local heldCalendar: Step? = nil -- 誘導を終えるまで待たせているカレンダー（D-289）

local function step()
	index += 1
	local s = steps[index]
	if s == nil then
		running = false
		if opened then
			opened = false
			Nav.close()
		end
		return
	end
	if s.id == "ReturnToasts" then
		-- 帰還のトーストはメイン画面の上に出すので、画面を閉じてから（D-281）
		if opened then
			opened = false
			Nav.close()
		end
		inToasts = true
		ReturnToast.playLogin(s.params.groups, function()
			inToasts = false
			step()
		end)
		return
	end
	s.params.onNext = step
	if opened then
		Nav.replace(s.id, s.params)
	else
		opened = true
		Nav.open(s.id, s.params)
	end
end

local function run(list: { Step })
	steps, index, running, opened = list, 0, true, false
	step()
end

-- 画面が空くのを待って1枚の流れとして出す
local function runWhenFree(s: Step)
	task.spawn(function()
		while Nav.depth() > 0 or inToasts do
			task.wait(0.5)
		end
		run({ s })
	end)
end

-- ログインボーナスのカレンダー（1日1回）。流れの途中なら最後に足し、そうでなければ画面が空くのを待って出す。
-- 初回の誘導を終えていなければ、終えるまで待たせる（D-289）
local function queueCalendar(bonus: any)
	if calendarShown then
		return
	end
	calendarShown = true
	local s = { id = "LoginCalendar", params = { loginBonus = bonus } }
	if not Guide.calendarReady() then
		heldCalendar = s
		return
	end
	if not startDone then
		pendingCalendar = s -- まとめより先に届いた：まとめの後ろにつなぐ（LoginSequence.start）
		return
	end
	-- B・Esc で流れを閉じたときは running が残るので、画面が開いているかでも見る
	if running and (Nav.depth() > 0 or inToasts) then
		table.insert(steps, s)
		return
	end
	runWhenFree(s)
end

function LoginSequence.start(events: { any })
	local view = Session.view
	if view == nil then
		startDone = true
		if pendingCalendar then
			run({ pendingCalendar :: Step })
			pendingCalendar = nil
		end
		return
	end
	local sum = LoginFlow.summarize(events, view, Session.now(), master)
	local list: { Step } = {}
	if sum.show then
		table.insert(list, { id = "LoginSummary", params = { summary = sum } })
	end
	if #sum.returned > 0 then
		local groups = {}
		for _, r in sum.returned do
			table.insert(groups, r.events)
		end
		table.insert(list, { id = "ReturnToasts", params = { groups = groups } })
	end
	if sum.cutIn and Game.query.preferences(view, master).cutIns then
		table.insert(list, { id = "CutIn", params = { cutIn = sum.cutIn } })
	end
	local cal = pendingCalendar
	pendingCalendar = nil
	if cal then
		if Guide.calendarReady() then
			table.insert(list, cal)
		else
			heldCalendar = cal -- 誘導を終えるまで待たせる（D-289）
		end
	end
	startDone = true
	if #list > 0 then
		run(list)
	end
	if sum.loginBonus then
		queueCalendar(sum.loginBonus)
	end
end

function LoginSequence.mount()
	-- ログインの知らせは、起動時の取り直し（Sync）と同じころに届く。要約（view）がそろうのを待ってから出す。
	-- 待ち受けを始める前に届いていたら、Session が覚えている分を使う
	local function begin(events: { any })
		if started then
			return
		end
		started = true
		task.spawn(function()
			local waited = 0
			while Session.view == nil and waited < 10 do
				waited += task.wait(0.1)
			end
			LoginSequence.start(events)
		end)
	end
	if Session.loadEvents then
		begin(Session.loadEvents)
	end
	Session.loaded:connect(begin)
	-- 誘導が進んでカレンダーを出してよくなったら、待たせていた分を出す（D-289）
	Guide.changed:connect(function()
		local s = heldCalendar
		if s and Guide.calendarReady() then
			heldCalendar = nil
			runWhenFree(s)
		end
	end)
	-- ログイン直後（や日の区切り）のオンラインの時間経過で届くログインボーナス
	Session.events:connect(function(reason: string, events: { any })
		if reason == "load" then
			return
		end
		for _, e in events do
			if e.type == "LoginBonus" then
				queueCalendar(e)
			end
		end
	end)
end

return LoginSequence
