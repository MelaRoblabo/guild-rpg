--!strict
-- ログインの流れ（D-132・D-208）。ログイン（reason "load"）で届いた出来事から、
--   S-01 まとめ（留守の間の出来事があれば）→ カットイン（最大1回。設定でオフなら出さない）→ カレンダー（ログインボーナスが届いた日）
--   の順に1枚ずつ出す。次へで差し替え、最後の次へで閉じる。B・Esc で閉じたら残りは出さない。

local Game = require("@game/ReplicatedStorage/Core/Game")
local LoginFlow = require("../login/LoginFlow")
local Nav = require("../ui/Nav")
local Session = require("../Session")
local master = require("../Master")

local LoginSequence = {}

local started = false

local function run(steps: { { id: string, params: any } })
	local i = 0
	local function step()
		i += 1
		local s = steps[i]
		if s == nil then
			Nav.close()
			return
		end
		s.params.onNext = step
		if i == 1 then
			Nav.open(s.id, s.params)
		else
			Nav.replace(s.id, s.params)
		end
	end
	step()
end

function LoginSequence.start(events: { any })
	local view = Session.view
	if view == nil then
		return
	end
	local sum = LoginFlow.summarize(events, view)
	local steps = {}
	if sum.show then
		table.insert(steps, { id = "LoginSummary", params = { summary = sum } })
	end
	if sum.cutIn and Game.query.preferences(view, master).cutIns then
		table.insert(steps, { id = "CutIn", params = { cutIn = sum.cutIn } })
	end
	if sum.loginBonus then
		table.insert(steps, { id = "LoginCalendar", params = { loginBonus = sum.loginBonus } })
	end
	if #steps > 0 then
		run(steps)
	end
end

function LoginSequence.mount()
	Session.events:connect(function(reason: string, events: { any })
		if reason ~= "load" or started then
			return
		end
		started = true
		-- 要約（view）を当ててから出す（events は view より先に届く）
		task.defer(LoginSequence.start, events)
	end)
end

return LoginSequence
