--!strict
-- マップイベントの出発（レアダンジョン・レイド。D-152・D-179・D-187・D-208・D-231 ⑬⑰・D-234 ①②）。
--   マップの印を触ると、パーティの面と同じ位置（x196・幅420）に羊皮紙の面。上の札は種類のアイコン、× は面の角。
--   - 上：残り時間（176×56 の札）。
--   - レア：強さ＝踏破済みの一番深いダンジョンの番号に ✓ と攻撃の種類の割合／★の宝箱 ×倍率／
--     選んだパーティの4人（有利な区分に緑の輪）と罠の避けやすさの棒（S-15 と同じ物差し：D-234 ①）。
--   - レイド：ボスの HP の棒に、選んだパーティのダメージの見込みを薄く重ねる（数字なし：D-231 ⑬）／
--     参加したら★の宝箱（出発したパーティのリーダーの顔と ✓：D-288）。
--   - パーティは「リーダーの顔＋状態の札」から選ぶ（D-231 ⑰・D-288）。探索中は押せない、出発済みは ✓。
--   - 旅の商人（D-274）：片道の時間（One way）と品のレアリティの形。送れるのは1パーティだけ。着いたら商人の面で買う。
--   - 金の Go（馬車＋種類のアイコン）＝DispatchEvent。

local AutoEquip = require("@game/ReplicatedStorage/Core/AutoEquip")
local ExclusiveGift = require("@game/ReplicatedStorage/Core/ExclusiveGift")
local Formulas = require("@game/ReplicatedStorage/Core/Formulas")
local Game = require("@game/ReplicatedStorage/Core/Game")
local Party = require("@game/ReplicatedStorage/Core/Party")
local ChestCommon = require("../chest/ChestCommon")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Hint = require("../../party/Hint")
local HubState = require("../../hub/HubState")
local Nav = require("../../ui/Nav")
local PartyIcon = require("../../ui/PartyIcon")
local Root = require("../../ui/Root")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local Words = require("../../ui/Words")
local WarehouseCommon = require("../warehouse/WarehouseCommon")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local KIND_ICON = { rareDungeon = "@rare_dungeon", raid = "@raid", merchant = "@merchant" }
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII" }
local deps = {
	weights = AutoEquip.weights,
	snapshot = Game.query.snapshot,
	busy = Party.isAdventurerBusy,
	partySnapshots = Game.query.partySnapshots,
	trapEvadeRate = Formulas.trapEvadeRate,
	travelSeconds = Formulas.travelSeconds,
	partyTravelMult = function(snaps, m)
		return ExclusiveGift.partyEffects(snaps, m).travelMult
	end,
}

local function clock(s: number): string
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function row(parent: GuiObject, order: number, height: number): Frame
	return new("Frame", {
		Name = "Row" .. order,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = C.ch75,
		[CHILDREN] = {
			Components.corner(8),
			Components.padding(0, 12, 0, 12),
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = parent,
	})
end

local function label(parent: GuiObject, order: number, text: string, size: number, color: Color3?)
	local t = Components.text({ text = text, size = size, color = color or C.inkDark, font = Tokens.font.number })
	t.LayoutOrder = order
	t.Parent = parent
	return t
end

local function bar(parent: GuiObject, order: number, width: number, height: number): Frame
	return new("Frame", {
		Name = "Bar",
		LayoutOrder = order,
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = C.barTrack,
		ClipsDescendants = true,
		[CHILDREN] = { Components.corner(6) },
		Parent = parent,
	})
end

local function build(params: any?, api: Nav.Api): Nav.Built
	local slot = (params :: any).slot :: number
	local band = Root.bandBottom()
	local frame: Frame = new("Frame", {
		Name = "EventDepart",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local pick: number? = nil
	local busy = false
	local alive = true
	local render: () -> ()
	-- レイドの HP は seed から作るのでサーバーに問い合わせる（開いたときと出発のあと）。ダメージ・参加は要約の raid から
	local raidQuery: any = nil
	local function fetchRaid()
		raidQuery = Session.query({ kind = "raid", eventSlot = slot })
	end
	-- 商人の品もサーバーで作る（seed は要約で隠している）。開いたときに一度だけ
	local merchantQuery: any = nil

	render = function()
		body:ClearAllChildren()
		local view = Session.view
		if view == nil then
			return
		end
		local now = Session.now()
		local ev = Game.query.mapEvent(now, master, view).current
		if ev == nil or ev.eventSlot ~= slot or not ev.open then
			api.close() -- 締め切り
			return
		end
		local raid = ev.kind == "raid"
		local merchant = ev.kind == "merchant"
		if merchant then
			-- もう送った（向かっている・着いている）なら閉じる（D-274：1パーティだけ）
			local waiting = false
			for _, p in Game.query.merchantPresence(view, now, master) do
				if p.eventSlot == slot and p.phase == "open" then
					waiting = true
				end
			end
			if not waiting then
				api.close()
				return
			end
			if merchantQuery == nil then
				merchantQuery = Session.query({ kind = "merchant", eventSlot = slot }) or {}
			end
		end
		local joined: { number } = {}
		local raidInfo = nil
		local target = nil
		if raid then
			if raidQuery == nil then
				fetchRaid()
			end
			local live = view.raid
			if live and live.eventSlot == slot then
				raidInfo = live
			else
				raidInfo = raidQuery
			end
			joined = (raidInfo and raidInfo.parties) or {}
		elseif not merchant then
			target = Game.query.rareDungeon(view, slot, master)
			joined = target.joined
		end
		-- 選べるパーティ：待機中で、まだこのイベントに出ていない
		local function canGo(p: number): boolean
			return HubState.status(view, p).state == "waiting" and table.find(joined, p) == nil
		end
		if pick == nil or not canGo(pick) then
			pick = nil
			for _, party in view.parties do
				if not Party.isEmpty(party) and canGo(party.index) then
					pick = party.index
					break
				end
			end
		end

		local panel, content = Components.panel({
			size = UDim2.fromOffset(420, 560),
			position = UDim2.fromOffset(196, band + 20),
			title = KIND_ICON[ev.kind] or "?",
		})
		panel.Name = "Panel"
		panel.Parent = body
		local close = Components.closeButton(api.close)
		close.AnchorPoint = Vector2.new(0.5, 0.5)
		close.Position = UDim2.new(1, -12, 0, 12)
		close.ZIndex = 20
		close.Parent = panel
		new("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = content,
		})
		-- 残り時間
		local timer = WarehouseCommon.pill("@time", clock(ev.closesIn or 0), 30)
		timer.Name = "Timer"
		timer.LayoutOrder = 1
		timer.Parent = content
		-- 中身
		local box: Frame = new("Frame", {
			Name = "Info",
			LayoutOrder = 2,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = C.ch50,
			[CHILDREN] = {
				Components.corner(8),
				Components.padding(10, 10, 10, 10),
				new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
			},
			Parent = content,
		})
		if merchant then
			-- 片道の時間（D-274）と品のレアリティの形（差を見せる：D-218）
			local r1 = row(box, 1, 60)
			label(r1, 1, "@time", 28)
			label(r1, 2, Words.oneWay .. " " .. clock(Game.query.merchantTravelSeconds(ev.placeId, master)), 25)
			local r2 = row(box, 2, 60)
			label(r2, 1, "@merchant", 28)
			for i, it in (merchantQuery and merchantQuery.items) or {} do
				label(r2, 1 + i, ChestCommon.rarityShape(it.rarity), 28, ChestCommon.rarityColor(it.rarity))
			end
		elseif not raid and target then
			local d = master.dungeons[target.dungeonId]
			local r1 = row(box, 1, 60)
			local num = WarehouseCommon.pill("✓", if d then ROMAN[d.tier] or tostring(d.tier) else "?", 23)
			num.LayoutOrder = 1
			num.Parent = r1
			label(r1, 2, "@job_physical", 25)
			local mix = bar(r1, 3, 150, 24)
			new("Frame", {
				Size = UDim2.fromScale(AutoEquip.weights(target.dungeonId, master), 1),
				BackgroundColor3 = C.barFill,
				Parent = mix,
			})
			label(r1, 4, "@job_magic", 25, C.statMag)
			local r2 = row(box, 2, 60)
			label(r2, 1, "@chest", 28)
			label(r2, 2, "×" .. master.K.rareDungeonChestMult, 25, C.ctaGoldRim)
			-- S-15 と同じ物差し（D-234 ①）：選んだパーティの4人と罠の避けやすさ
			local r3 = row(box, 3, 60)
			if pick and d then
				local fav = Hint.favored(d)
				for i, uid in view.parties[pick].slots do
					local adv = view.adventurers[uid]
					if adv then
						local job = master.jobs[adv.jobId]
						local isFav = fav ~= nil and job ~= nil and job.attackType == fav
						local f: TextLabel = new("TextLabel", {
							Name = "Member" .. i,
							LayoutOrder = i,
							Text = "",
							TextSize = 21,
							FontFace = Tokens.font.number,
							TextColor3 = C.inkLight,
							BackgroundColor3 = C.ch16,
							Size = UDim2.fromOffset(40, 40),
							[CHILDREN] = {
								Components.corner(20),
								Components.stroke(if isFav then C.okGreen else C.ch28, 3),
							},
							Parent = r3,
						})
						Components.setText(
							f,
							if job and job.attackType == "magic" then "@job_magic" else "@job_physical"
						)
					end
				end
				-- 罠のよけやすさ：語と %（D-269 ①④）
				label(r3, 8, "Dodge", 21)
				local evade = Hint.forParty(view, pick, d, master, deps)
				local eb = bar(r3, 9, 90, 22)
				new(
					"Frame",
					{ Size = UDim2.fromScale(math.clamp(evade, 0, 1), 1), BackgroundColor3 = C.barFill, Parent = eb }
				)
				label(r3, 10, string.format("%d%%", math.floor(math.clamp(evade, 0, 1) * 100 + 0.5)), 21)
			end
		elseif raidInfo then
			-- ボスの HP の棒と、選んだパーティのダメージの見込み（数字なし：D-231 ⑬）
			local hp = math.max(1, raidInfo.hp)
			local remain = math.max(0, hp - (raidInfo.damage or 0))
			local proj = if pick then math.min(remain, Game.query.raidDamage(view, pick, master)) else 0
			local r1 = row(box, 1, 60)
			label(r1, 1, "☠", 30, C.warn)
			local hb = bar(r1, 2, 280, 30)
			new(
				"Frame",
				{ Name = "Remain", Size = UDim2.fromScale(remain / hp, 1), BackgroundColor3 = C.barFill, Parent = hb }
			)
			new("Frame", {
				Name = "Hit",
				Position = UDim2.fromScale((remain - proj) / hp, 0),
				Size = UDim2.fromScale(proj / hp, 1),
				BackgroundColor3 = C.inkWhite,
				BackgroundTransparency = 0.45,
				Parent = hb,
			})
			local r2 = row(box, 2, 60)
			label(r2, 1, "@chest", 28)
			label(r2, 2, "@party", 25)
			for i, p in joined do
				-- 参加したパーティ：✓＋リーダーの顔（番号ではなく顔：D-288）
				local j = WarehouseCommon.pill("✓", "", 21, C.okGreen)
				for _, c in j:GetChildren() do
					if c:IsA("TextLabel") and c.LayoutOrder == 2 then
						c:Destroy() -- 空の語の枠は要らない
					end
				end
				local face = PartyIcon.make(30)
				face.LayoutOrder = 3
				face.Parent = j
				PartyIcon.set(face, view, p)
				j.LayoutOrder = 2 + i
				j.Parent = r2
			end
		end
		-- パーティの札（リーダーの顔＋状態の印：D-231 ⑰・D-288。番号ではなく顔）
		local picks: Frame = new("Frame", {
			Name = "Parties",
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, 88),
			BackgroundTransparency = 1,
			[CHILDREN] = {
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding = UDim.new(0, 12),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = content,
		})
		for _, party in view.parties do
			if not Party.isEmpty(party) then
				local p = party.index
				local done = table.find(joined, p) ~= nil
				local ok = canGo(p)
				local sel = pick == p
				local b: TextButton = new("TextButton", {
					Name = "Party" .. p,
					LayoutOrder = p,
					Text = if done then "✓" elseif ok then "▶" else "●", -- 状態の印は右、顔は左（D-288）
					TextSize = 25,
					FontFace = Tokens.font.display,
					TextColor3 = if done then C.okGreen else C.inkLight,
					TextTransparency = if ok or done then 0 else 0.5,
					TextXAlignment = Enum.TextXAlignment.Right,
					AutoButtonColor = false,
					Active = ok,
					Size = UDim2.fromOffset(109, 88),
					BackgroundColor3 = if ok then C.ch28 else C.ch16,
					[CHILDREN] = {
						Components.corner(14),
						Components.stroke(if sel then C.selAmber elseif ok then C.bronze else C.ch28, 3),
						Components.padding(0, 14, 0, 0),
					},
					Parent = picks,
				})
				local face = PartyIcon.make(56)
				face.AnchorPoint = Vector2.new(0, 0.5)
				face.Position = UDim2.new(0, 8, 0.5, 0)
				face.BackgroundTransparency = if ok or done then 0 else 0.5
				face.Parent = b
				PartyIcon.set(face, view, p)
				if ok then
					b.Activated:Connect(function()
						pick = p
						render()
					end)
				end
			end
		end
		-- Go（馬車＋種類のアイコン）
		local go = Components.button({
			kind = if pick then "gold" else "disabled",
			width = 240,
			icon = "▶",
			label = Words.go,
			reason = Words.reason.allOut, -- 出かけ中で出発できない理由（D-269 ④）
			name = "Go",
			glyph = "A",
			onClick = function()
				if busy or pick == nil then
					return
				end
				busy = true
				local r = Session.sendAndWait({ type = "DispatchEvent", partyIndex = pick, eventSlot = slot })
				busy = false
				if r and r.ok then
					HubState.selected = pick
					api.close()
				else
					render()
				end
			end,
		})
		go.LayoutOrder = 4
		go.Parent = content
	end

	render()
	-- 残り時間を毎秒更新
	task.spawn(function()
		while alive do
			task.wait(1)
			if alive and not busy then
				render()
			end
		end
	end)
	return {
		frame = frame,
		scrim = 0.5,
		destroy = function()
			alive = false
		end,
	}
end

Nav.register("EventDepart", build)

return {}
