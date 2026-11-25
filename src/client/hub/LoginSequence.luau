--!strict
-- ログインの流れ（D-132・D-208）。ログイン（reason "load"）で届いた出来事から、
--   S-01 まとめ（留守番が動いた・休息ボーナスがたまった・受け取り箱に届いた、のどれか：D-208 ④）
--   → カットイン（最大1回。設定でオフなら出さない）→ カレンダー（ログインボーナスが届いた日）
--   の順に1枚ずつ出す。次へで差し替え、最後の次へで閉じる。B・Esc で閉じたら残りは出さない。
--   ログインボーナスは留守の計算ではなく、ログイン直後の最初のオンラインの時間経過で届く（D-155、Game の advanceOnline）。
--   そのため LoginBonus はログインの知らせとは別に受け取り、流れの途中なら最後につなぎ、そうでなければ画面が空いたときに出す。

local Game = require("@game/ReplicatedStorage/Core/Game")
local LoginFlow = require("../login/LoginFlow")
local Nav = require("../ui/Nav")
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

local function step()
	index += 1
	local s = steps[index]
	if s == nil then
		running = false
		Nav.close()
		return
	end
	s.params.onNext = step
	if index == 1 then
		Nav.open(s.id, s.params)
	else
		Nav.replace(s.id, s.params)
	end
end

local function run(list: { Step })
	steps, index, running = list, 0, true
	step()
end

-- ログインボーナスのカレンダー（1日1回）。流れの途中なら最後に足し、そうでなければ画面が空くのを待って出す
local function queueCalendar(bonus: any)
	if calendarShown then
		return
	end
	calendarShown = true
	local s = { id = "LoginCalendar", params = { loginBonus = bonus } }
	if not startDone then
		pendingCalendar = s -- まとめより先に届いた：まとめの後ろにつなぐ（LoginSequence.start）
		return
	end
	-- B・Esc で流れを閉じたときは running が残るので、画面が開いているかでも見る
	if running and Nav.depth() > 0 then
		table.insert(steps, s)
		return
	end
	task.spawn(function()
		while Nav.depth() > 0 do
			task.wait(0.5)
		end
		run({ s })
	end)
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
	if sum.cutIn and Game.query.preferences(view, master).cutIns then
		table.insert(list, { id = "CutIn", params = { cutIn = sum.cutIn } })
	end
	local cal = pendingCalendar
	pendingCalendar = nil
	if cal then
		table.insert(list, cal)
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
