--!strict
-- パーティの面（S-10 の中。D-212〜D-216・D-225 ③）。一覧の行か馬車を触って開く。
--   - 羊皮紙の面、題の札＝パーティの番号、× は面の右上の角、後ろの暗幕は 50%（D-225 ③）。
--   - 待機：同じ所へ再出発（Go、金）と Menu（茶。S-12 は M8-6）。探索中：フロアの進みと自動再派遣のスイッチだけ（D-214 ⑥）。
--   - 移動中・帰還中：残り時間。メンバーの HP は探索中だけ（戦闘不能は暗くする：D-214 ⑤）。
--   - S-11 探索ウィンドウ（D-213 ⑦・D-236）：出発してから帰るまで、面の上に一枚絵の枠（高さ160）を出す。
--     戦闘はモンスター（仮の名前）と HP の棒、与えたダメージは出た瞬間だけ白い数字（クリティカルは大きく黄色）、回復は緑。
--     イベントはイベントの絵と HP の増減の数字。右上に確保した宝箱、下の端にフロアの印。帰り道は馬車・残り時間・持ち帰る宝箱。

local Game = require("@game/ReplicatedStorage/Core/Game")
local Party = require("@game/ReplicatedStorage/Core/Party")
local TweenService = game:GetService("TweenService")
local Components = require("../ui/Components")
local Create = require("../ui/Create")
local HubState = require("../hub/HubState")
local Nav = require("../ui/Nav")
local Replay = require("../party/Replay")
local Root = require("../ui/Root")
local Session = require("../Session")
local Tokens = require("../ui/Tokens")
local Guide = require("../hub/Guide")
local Words = require("../ui/Words")
local master = require("../Master")

local C = Tokens.color
local I = Components.icon
local new = Create.new
local CHILDREN = Create.Children

local PANEL_W = 420
local PANEL_H = 470
local PANEL_H_EXPLORE = 554 -- 探索ウィンドウ（一枚絵の枠つき）
local SCENE_H = 160
local EVENT_GLYPH = { chest = "▣", item = "🎟", trap = "⚠", fountain = "✚", none = "…" }

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function memberRow(adv: any, hp: number?, maxHp: number?, delta: number?, compact: boolean?): Frame
	local row: Frame = new("Frame", {
		Name = "Member",
		Size = UDim2.new(1, 0, 0, if compact then 46 else 56), -- 探索中は一枚絵の枠のぶん低く
		BackgroundColor3 = C.ch75,
		[CHILDREN] = {
			Components.corner(6),
			Components.padding(0, 12, 0, 12),
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	})
	local down = hp ~= nil and hp <= 0
	-- 顔（仮：バストアップの代わりの丸）
	new("Frame", {
		Name = "Face",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = if down then C.ch45 else C.ch50,
		[CHILDREN] = { Components.corner(8), Components.stroke(C.ch16, 2) },
		Parent = row,
	})
	local name = Components.text({ text = adv.name, size = 23, color = C.inkDark, font = Tokens.font.bodyStrong })
	name.LayoutOrder = 2
	name.TextTransparency = if down then 0.5 else 0
	name.Parent = row
	local lv = Components.text({ text = "Lv " .. adv.level, size = 21, color = C.inkMid, font = Tokens.font.number })
	lv.LayoutOrder = 3
	lv.Parent = row
	if hp ~= nil and maxHp ~= nil and maxHp > 0 then
		local track: Frame = new("Frame", {
			Name = "Hp",
			LayoutOrder = 4,
			Size = UDim2.fromOffset(110, 20),
			BackgroundColor3 = C.barTrack,
			[CHILDREN] = { Components.corner(6) },
			Parent = row,
		})
		new("Frame", {
			Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1),
			BackgroundColor3 = if down then C.warn elseif hp / maxHp < 0.3 then C.dangerRed else C.barFill,
			[CHILDREN] = { Components.corner(6) },
			Parent = track,
		})
	end
	if delta and delta ~= 0 then
		-- 回復・罠・泉の増減（D-236 ②③）
		local d = Components.text({
			text = (if delta > 0 then "+" else "") .. delta,
			size = 23,
			color = if delta > 0 then C.up else C.warnDark,
			font = Tokens.font.number,
			stroke = delta < 0,
		})
		d.LayoutOrder = 5
		d.Parent = row
	end
	return row
end

local function build(params: any?, api: Nav.Api): Nav.Built
	local partyIndex = (params :: any).partyIndex :: number
	Guide.done("wagon") -- 初回の誘導：馬車（パーティの面を開いた：D-244 ①）
	local band = Root.bandBottom()
	local frame: Frame = new("Frame", {
		Name = "PartyPanel",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	local panel, content = Components.panel({
		size = UDim2.fromOffset(PANEL_W, PANEL_H),
		position = UDim2.fromOffset(196, band + 40),
		title = "Party " .. partyIndex,
	})
	panel.Parent = frame
	local close = Components.closeButton(api.close)
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.fromOffset(196 + PANEL_W - 12, band + 40 + 12)
	close.Parent = frame

	-- S-11 の一枚絵の枠（出発してから帰るまで）
	local scene: Frame = new("Frame", {
		Name = "Scene",
		Size = UDim2.new(1, 0, 0, SCENE_H),
		BackgroundColor3 = C.ch13,
		Visible = false,
		ClipsDescendants = true,
		[CHILDREN] = { Components.corner(8), Components.stroke(C.ch16, 2) },
		Parent = content,
	})
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = content,
	})
	local actions: Frame = new("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 85),
		BackgroundTransparency = 1,
		[CHILDREN] = {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				Padding = UDim.new(0, 12),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = content,
	})

	local lastKey = ""
	local replay: Replay.State? = nil -- 今の再生（探索中だけ）
	local function render(view: any)
		if view == nil then
			return
		end
		local s = HubState.status(view, partyIndex)
		local party = nil
		for _, p in view.parties or {} do
			if p.index == partyIndex then
				party = p
			end
		end
		if party == nil then
			return
		end
		-- 状態が変わったときだけ作り直す（毎フレームは作らない）
		local key = s.state
			.. ":"
			.. tostring(s.floorIndex)
			.. ":"
			.. tostring(s.pinch)
			.. ":"
			.. tostring(party.autoRepeat and party.autoRepeat.dungeonId)
			.. ":"
			.. tostring(party.lastDungeonId)
		if s.hp then
			key ..= ":" .. table.concat(s.hp, ",")
		end
		local rp = replay
		if rp then
			key ..= ":" .. rp.phase .. ":" .. table.concat(rp.hp, ",") .. ":" .. tostring(rp.turn) .. ":" .. #rp.deltas
		end
		local exploring = s.state ~= "waiting"
		scene.Visible = exploring
		body.Position = UDim2.fromOffset(0, if exploring then SCENE_H + 10 else 0)
		body.Size = UDim2.new(1, 0, 1, if exploring then -(SCENE_H + 10) else 0)
		panel.Size = UDim2.fromOffset(PANEL_W, if exploring then PANEL_H_EXPLORE else PANEL_H)
		if key == lastKey then
			return
		end
		lastKey = key
		body:ClearAllChildren()
		actions:ClearAllChildren()
		new("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = body,
		})
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = actions,
		})
		-- 行き先と残り時間（移動中・帰還中・探索中）
		if s.state ~= "waiting" and s.dungeonId then
			local d = master.dungeons[s.dungeonId]
			local line = Components.text({
				text = (if d then d.nameEn else s.dungeonId),
				size = 23,
				color = C.inkDark,
				font = Tokens.font.bodyStrong,
			})
			line.LayoutOrder = 0
			line.Parent = body
		end
		local maxHp = {}
		local ok, snaps = pcall(function()
			return require("@game/ReplicatedStorage/Core/Game").query.partySnapshots(view, partyIndex, master)
		end)
		if ok and type(snaps) == "table" then
			for i, sn in snaps do
				maxHp[i] = sn.maxHp
			end
		end
		local order = 1
		local memberIdx = 0
		for _, uid in party.slots do
			if uid ~= "" and view.adventurers[uid] then
				memberIdx += 1
				local hp = if rp and rp.phase ~= "outbound"
					then rp.hp[memberIdx]
					elseif s.state == "exploring" and s.hp then s.hp[memberIdx]
					else nil
				local delta = nil
				if rp and rp.phase == "floor" then
					for _, d in rp.deltas do
						if d.index == memberIdx then
							delta = d.amount
						end
					end
					local _, mySlot = Party.find(view, uid)
					for _, a in rp.actions do
						if a.kind == "heal" and a.target == mySlot then
							delta = a.amount
						end
					end
				end
				local row = memberRow(view.adventurers[uid], hp, maxHp[memberIdx], delta, exploring)
				order += 1
				row.LayoutOrder = order
				row.Parent = body
			end
		end
		if s.state == "waiting" then
			local menu = Components.button({
				kind = "brown",
				width = 150,
				height = 66,
				icon = "▤",
				label = Words.menu,
				name = "Menu",
				glyph = "X",
				onClick = function()
					api.open("PartyMenu", { partyIndex = partyIndex }) -- S-12（M8-6）
				end,
			})
			menu.LayoutOrder = 1
			menu.Parent = actions
			-- 最後の行き先（D-228）。まだ一度も出ていなければ、解放済みで一番浅いダンジョン（D-244 ②）
			local dest = party.lastDungeonId or HubState.firstUnlocked(view)
			local go = Components.button({
				kind = if dest then "gold" else "disabled",
				width = 200,
				icon = "▶",
				label = Words.go,
				name = "Go",
				glyph = "A",
				onClick = function()
					if dest then
						local r = Session.send({ type = "Dispatch", partyIndex = partyIndex, dungeonId = dest })
						if r and r.ok then
							HubState.selected = partyIndex
							HubState.following = true
							api.close()
						end
					end
				end,
			})
			go.LayoutOrder = 2
			go.Parent = actions
			Guide.mark(go, Guide.is("go") and dest ~= nil, 18) -- 初回の誘導：Go
		else
			-- 自動再派遣のスイッチ（D-125・D-214 ⑥）
			local on = party.autoRepeat ~= nil
			local toggle = Components.button({
				kind = if on then "gold" else "brown",
				width = 170,
				height = 66,
				icon = I.reroll,
				label = Words.repeatOn,
				name = "Repeat",
				glyph = "X",
				onClick = function()
					Session.send({
						type = "SetAutoRepeat",
						partyIndex = partyIndex,
						dungeonId = if on then nil else s.dungeonId,
					})
				end,
			})
			toggle.LayoutOrder = 1
			toggle.Parent = actions
		end
	end

	-- 一枚絵の枠の中身（再生に合わせて 0.25 秒ごと）
	local slotsOf: { [string]: { slots: { number }, maxHp: { number } } } = {}
	local lastTurn = ""
	local function popup(text: string, size: number, color: Color3)
		local t = Components.text({ text = text, size = size, color = color, font = Tokens.font.number, stroke = true })
		t.Name = "Popup"
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.fromScale(0.5, 0.45)
		t.ZIndex = 10
		t.Parent = scene
		TweenService:Create(t, TweenInfo.new(0.8), { Position = UDim2.fromScale(0.5, 0.2), TextTransparency = 1 })
			:Play()
		task.delay(0.85, function()
			t:Destroy()
		end)
	end
	local function drawScene(view: any)
		local e = Game.query.expeditionOf(view, partyIndex)
		if e == nil or e.log == nil then
			replay = nil
			return
		end
		local info = slotsOf[e.uid]
		if info == nil then
			local slots, mh = {}, {}
			local snaps = Game.query.partySnapshots(view, partyIndex, master)
			for i, uid in e.memberUids do
				local _, slot = Party.find(view, uid)
				slots[i] = slot or i
				mh[i] = if snaps[i] then snaps[i].maxHp else 1
			end
			info = { slots = slots, maxHp = mh }
			slotsOf[e.uid] = info
		end
		local st = Replay.at(e.log, info.slots, info.maxHp, Session.now(), master.K)
		replay = st
		for _, c in scene:GetChildren() do
			if c.Name ~= "Popup" and not c:IsA("UICorner") and not c:IsA("UIStroke") then
				c:Destroy()
			end
		end
		local function center(text: string, size: number, color: Color3, y: number)
			local t = Components.text({ text = text, size = size, color = color, font = Tokens.font.display })
			t.AnchorPoint = Vector2.new(0.5, 0.5)
			t.Position = UDim2.fromScale(0.5, y)
			t.Parent = scene
		end
		local function chestPill()
			local p = Components.chip("▣", tostring(st.chests), C.bronzeHi)
			p.AnchorPoint = Vector2.new(1, 0)
			p.Position = UDim2.new(1, -6, 0, 6)
			p.Parent = scene
		end
		if st.phase ~= "floor" then
			-- 移動中・帰り道：馬車と残り時間（帰り道は持ち帰る宝箱も：D-236 ④）
			local toGo = if st.phase == "outbound"
				then e.departAt + e.log.travelSeconds - Session.now()
				else st.remaining
			center(if st.phase == "outbound" then "▶" else "◀", 40, C.inkLight, 0.4)
			center(clock(toGo), 30, C.inkLight, 0.72)
			if st.phase ~= "outbound" then
				chestPill()
			end
			return
		end
		-- フロア：戦闘はモンスターと HP の棒、イベントはイベントの絵
		local d = master.dungeons[e.dungeonId]
		if st.kind == "battle" then
			local mon = if st.monsterId then master.monsters[st.monsterId] else nil
			center(if mon then mon.nameEn else "?", 25, C.inkLight, 0.5)
			local track: Frame = new("Frame", {
				Name = "MonsterHp",
				Position = UDim2.fromOffset(12, 12),
				Size = UDim2.new(1, -120, 0, 16),
				BackgroundColor3 = C.barTrack,
				[CHILDREN] = { Components.corner(6) },
				Parent = scene,
			})
			new("Frame", {
				Size = UDim2.fromScale(st.monsterRatio or 1, 1),
				BackgroundColor3 = C.warnDark,
				[CHILDREN] = { Components.corner(6) },
				Parent = track,
			})
			-- 与えたダメージは出た瞬間だけ（D-236 ②）
			local key = tostring(st.floorIndex) .. ":" .. tostring(st.turn)
			if key ~= lastTurn then
				lastTurn = key
				local total, crit = 0, false
				for _, a in st.actions do
					if a.kind == "attack" then
						total += a.amount
						crit = crit or a.crit == true
					end
				end
				if total > 0 then
					popup(tostring(total), if crit then 44 else 30, if crit then C.numHi else C.inkWhite)
				end
			end
		else
			center(EVENT_GLYPH[st.event or "none"] or "…", 48, C.inkLight, 0.5)
		end
		chestPill()
		-- フロアの印（済み＝青銅、今＝光る。偶数＝イベントは角、最後＝大きな丸＝ボス）
		local marks: Frame = new("Frame", {
			Name = "Floors",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -16, 0, 18),
			BackgroundTransparency = 1,
			[CHILDREN] = {
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 4),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = scene,
		})
		local total = if d then d.floors else st.floors
		for f = 1, total do
			local boss = f == total
			new("Frame", {
				Name = "F" .. f,
				LayoutOrder = f,
				Size = UDim2.fromOffset(if boss then 16 else 12, if boss then 16 else 12),
				BackgroundColor3 = if f < (st.floor or 0) then C.bronze elseif f == st.floor then C.numHi else C.ch16,
				[CHILDREN] = { Components.corner(if f % 2 == 0 and not boss then 2 else 8) },
				Parent = marks,
			})
		end
	end
	local alive = true
	task.spawn(function()
		while alive do
			local view = Session.view
			if view then
				drawScene(view)
				render(view)
			end
			task.wait(0.25)
		end
	end)
	local conn = Session.changed:connect(render)
	render(Session.view)
	return {
		frame = frame,
		scrim = 0.5, -- D-225 ③
		destroy = function()
			alive = false
			conn.disconnect()
		end,
	}
end

Nav.register("PartyPanel", build)

return {}
