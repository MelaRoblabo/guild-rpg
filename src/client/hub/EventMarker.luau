--!strict
-- マップイベントの印（D-152・D-208 ⑥・D-213 ⑫・D-215 ③・D-225 ⑥・D-234 ②）。メイン画面のマップの上に1つ。
--   ① 予告（出る mapEventNoticeSeconds 前）：点線の丸の中に種類のアイコン（暗く）と、出るまでの時計。
--   ② 出ている（mapEventWindowSeconds の間）：減っていく輪と種類のアイコン、残りの時計。押すと出発の面（レア・レイド）か商人の面。
--   ③ 残りわずか（30秒から）：輪が点滅し、時計が警告の色。
--   ④ 出発済み：輪の下にパーティの番号（レア・レイド）か、買った印（商人）。
--   種類のアイコン：レアダンジョン＝宝石（門はパーティの「探索中」：D-234 ②）、レイド＝稲妻、商人＝カート。
--   ⑤ 締め切り間近は印が小さく揺れ、締め切ったら「Closed」のハンコを押して消える（D-269 ③。黙って消えていた）。
--   3D マップ（D-270 ⑦）：印は地図の上の場所（Studio の EventPlace01〜）に BillboardGui で出す。
--   旅の商人・レイドボスには印を出さない（D-274・D-275：地図の上の物そのものと頭上の時計：EventWorld）。
--   レアダンジョンも出ている間は印を出さない（D-304：地図の上の水晶の祠）。予告の間だけ印を出す。

local Game = require("@game/ReplicatedStorage/Core/Game")
local Components = require("../ui/Components")
local Create = require("../ui/Create")
local Guide = require("./Guide")
local Motion = require("../ui/Motion")
local Nav = require("../ui/Nav")
local Session = require("../Session")
local Tokens = require("../ui/Tokens")
local master = require("../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local KIND_ICON = { rareDungeon = "@rare_dungeon", raid = "@raid", merchant = "@merchant" }
local ENDING_SECONDS = master.K.mapEventEndingSeconds -- 残りわずか（D-213 ⑫・D-238 ③）

local EventMarker = {}

local marker: TextButton? = nil
local current: any = nil
local board: BillboardGui? = nil -- 印を載せる板（場所の Part に付ける）
local placeFor: ((number) -> BasePart?)? = nil
local lastOpen: { slot: number, place: BasePart }? = nil -- 最後に出ていたイベント

local function clock(s: number): string
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function placeIndex(placeId: string): number
	for i, p in master.mapEventPlaces do
		if p.id == placeId then
			return i
		end
	end
	return 1
end

-- 締め切ったイベントの場所に「Closed」のハンコを押して消す
local function stampClosed(place: BasePart)
	local parentGui = board and board.Parent
	if parentGui == nil then
		return
	end
	local b: BillboardGui = new("BillboardGui", {
		Name = "ClosedStamp",
		Adornee = place,
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(140, 140),
		StudsOffsetWorldSpace = Vector3.new(0, 4, 0),
		Parent = parentGui,
	})
	local holder: Frame = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = b,
	})
	Motion.stamp(holder, "Closed", C.warnDark, 120)
	task.delay(1.4, function()
		b:Destroy()
	end)
end

-- getPlace：イベントの場所の番号 → 地図の上の Part（World3D.eventPlace）。parentGui：板を置く所（PlayerGui の中）
function EventMarker.mount(getPlace: (number) -> BasePart?, parentGui: Instance)
	placeFor = getPlace
	board = new("BillboardGui", {
		Name = "MapEventBoard",
		AlwaysOnTop = true,
		Active = true,
		Enabled = false,
		Size = UDim2.fromOffset(150, 150),
		StudsOffsetWorldSpace = Vector3.new(0, 4, 0),
		Parent = parentGui,
	})
	local m: TextButton = new("TextButton", {
		Name = "MapEvent",
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.6),
		Size = UDim2.fromOffset(96, 96),
		BackgroundColor3 = C.ch16,
		Visible = false,
		ZIndex = 6,
		[CHILDREN] = { Components.corner(48), Components.stroke(C.barFill, 6) },
		Parent = board,
	})
	local icon = Components.text({ text = "", size = 40, color = C.inkLight, font = Tokens.font.number })
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 7
	icon.Parent = m
	local timer = Components.chip("@time", "0:00", C.bronzeHi)
	timer.Name = "Timer"
	timer.AnchorPoint = Vector2.new(0, 1)
	timer.Position = UDim2.fromScale(0.7, 0)
	timer.ZIndex = 7
	timer.Parent = m
	local joined = Components.chip("", "", C.okGreen)
	joined.Name = "Joined"
	joined.AnchorPoint = Vector2.new(0.5, 0)
	joined.Position = UDim2.new(0.5, 0, 1, 4)
	joined.Visible = false
	joined.ZIndex = 7
	joined.Parent = m
	m.Activated:Connect(function()
		local ev = current
		if ev == nil or not ev.open then
			return
		end
		if ev.kind == "merchant" then
			Nav.open("Merchant", { slot = ev.eventSlot })
		else
			Nav.open("EventDepart", { slot = ev.eventSlot })
		end
	end)
	marker = m
end

local function setChip(chip: Frame, icon: string, text: string, color: Color3?)
	local labels = {}
	for _, c in chip:GetChildren() do
		if c:IsA("TextLabel") then
			table.insert(labels, c)
		end
	end
	if labels[1] then
		Components.setText(labels[1], icon)
	end
	if labels[2] then
		labels[2].Text = text
		labels[2].TextColor3 = color or C.inkLight
	end
end

-- 毎フレーム近くで呼ぶ（Hub の refreshMoving から）
function EventMarker.refresh(view: any)
	local m = marker
	if m == nil or view == nil then
		return
	end
	local now = Session.now()
	local st = Game.query.mapEvent(now, master, view) -- 管理者が出したイベントも（D-306）
	local cur = st.current
	local notice = false
	local ev = nil
	if cur and cur.open then
		ev = cur
	elseif st.next then
		ev = st.next
		notice = true
	end
	-- 商人・レイドボスは地図の上の物（EventWorld）が出す（D-274・D-275）。
	-- 出ているレアダンジョンも地図の上の水晶の祠が出す（D-304）。予告の間だけ印を出す
	if ev and (ev.kind == "merchant" or ev.kind == "raid" or (ev.kind == "rareDungeon" and not notice)) then
		ev = nil
	end
	current = if notice then nil else ev
	-- 出ていたイベントが締め切られた（次の予告になった・消えた）ら、その場所に Closed のハンコ
	local last = lastOpen
	if last and (current == nil or current.eventSlot ~= last.slot) then
		lastOpen = nil
		stampClosed(last.place)
	end
	local b = board
	if ev == nil or b == nil or placeFor == nil then
		m.Visible = false
		m.Rotation = 0
		if b then
			b.Enabled = false
		end
		return
	end
	local place = (placeFor :: (number) -> BasePart?)(placeIndex(ev.placeId))
	if place == nil then
		b.Enabled = false
		return
	end
	b.Adornee = place
	b.Enabled = true
	m.Visible = true
	local icon = m:FindFirstChild("Icon") :: TextLabel
	Components.setText(icon, KIND_ICON[ev.kind] or "?")
	icon.TextTransparency = if notice then 0.4 else 0
	local stroke = m:FindFirstChildOfClass("UIStroke") :: UIStroke
	local timer = m:FindFirstChild("Timer") :: Frame
	local joinedChip = m:FindFirstChild("Joined") :: Frame
	if notice then
		stroke.Color = C.ch45
		stroke.Thickness = 3
		m.Rotation = 0
		setChip(timer, "@time", clock(ev.startsIn or 0))
		joinedChip.Visible = false
		return
	end
	lastOpen = { slot = ev.eventSlot, place = place }
	local left = ev.closesIn or 0
	local ending = left <= ENDING_SECONDS
	-- 締め切り間近は小さく揺れる（D-269 ③）。「点滅を減らす」なら揺れも小さく（D-145）
	m.Rotation = if ending then math.sin(now * 10) * (if Motion.reduced() then 2 else 5) else 0
	-- 残りわずかは点滅（0.5秒ごと）
	local blink = ending and (math.floor(now * 2) % 2 == 0)
	stroke.Color = if ev.kind == "raid" then C.warnDark else C.barFill
	stroke.Thickness = 6
	stroke.Transparency = if blink then 0.7 else 0
	-- 初回の誘導の間は、誘導の輪と見分けが付かないので予告と同じ細い暗い輪にする（光るのは同時に1つだけ：D-244）
	if Guide.current() ~= nil then
		stroke.Color = C.ch45
		stroke.Thickness = 3
		stroke.Transparency = 0
	end
	setChip(timer, "@time", clock(left), if ending then C.warnDark else nil)
	-- 出発済み・買った印
	local tag = nil
	if ev.kind == "rareDungeon" then
		local rd = Game.query.rareDungeon(view, ev.eventSlot, master)
		if #rd.joined > 0 then
			tag = "♟" .. table.concat(rd.joined, " ")
		end
	elseif ev.kind == "raid" then
		-- HP は seed から作るので端末では計算しない。参加したパーティは要約の raid（その時間帯の分）から見る
		local r = view.raid
		if r and r.eventSlot == ev.eventSlot and #(r.parties or {}) > 0 then
			tag = "♟" .. table.concat(r.parties, " ")
		end
	elseif ev.kind == "merchant" then
		-- 品はサーバーで作るので、買った印は要約の merchant（その時間帯の買った品）から見る
		local sale = view.merchant
		local n = 0
		if sale and sale.eventSlot == ev.eventSlot then
			for _, bought in sale.bought or {} do
				if bought then
					n += 1
				end
			end
		end
		if n > 0 then
			tag = "🛍"
		end
	end
	joinedChip.Visible = tag ~= nil
	if tag then
		setChip(joinedChip, tag, "✓", C.okGreen)
	end
end

return EventMarker
