--!strict
-- S-15 行き先・ダンジョンの面（D-048・D-113・D-130・D-163・D-209・D-225 ③・D-231 ⑤⑦・D-232 ⑨・D-272・D-279・D-282）。
--   マップのダンジョンを触って開く。パーティの面と同じ位置・形（x196・幅420・羊皮紙・× は面の角）。
--   上にそのダンジョンの中の背景の絵を大きく出す（D-282。主役はこの絵）。中身は3通り：
--   ① パーティから（S-12 の金 → マップで選ぶ：hub/PickMode）：中の絵＋攻略ヒント＋罠の避けやすさの棒＋移動時間。
--      右下の金＝Go。
--   ② マップから：中の絵＋攻略ヒント。ボタンは ▶ Go だけ（D-282。冒険者の一覧（D-113）と ＋Form は消した）。
--      Go を押すと待機中のパーティの一覧を出し、選ぶとそのダンジョンへ出発（D-272）。待機中がいなければ灰色で理由。
--   ③ 未解放：中の絵を暗く沈めて鍵と「前のダンジョンの踏破で解放」の印。右下に金の Unlock と金額（D-279）。
--      前のダンジョンが解放済みで、ゴールドが足りるときだけ押せる。押せないときも押せて、理由の吹き出し2秒（D-264）。
--      解放できたらハンコ（D-269）を押して、同じ面を ② の形で作り直す（そのまま Go できる）。
--   攻略ヒント（D-250 ③）：Foes＝多い種族（英語の短い語を多い順、一番多いものは濃い縁）、Traps＝罠Lv の2行だけ。
--   派遣費は出さない（D-163）。レイドの面は ④ の画面（EventDepart）で作る。
--   レアダンジョン（D-307）：地図の水晶の祠を触ると、② と同じ形で開く（params.rareSlot）。題は Rare Dungeon、絵は専用の背景、
--     攻略ヒントは強さの基準のダンジョン（D-187）。絵の左上に締め切りまでの時計。Go → 待機中のパーティ（出発済みは除く）→ DispatchEvent。
--     締め切ったら閉じる。
--   レイドボス（D-309）：地図のレイドボスを触ると、同じ形で開く（params.raidSlot）。題は Raid Boss、絵はレイドの絵。
--     攻略ヒントの代わりに、Boss＝ボスの HP の残りの棒、Joined＝出発したパーティのリーダーの顔。Go → 待機中のパーティ → DispatchEvent。
--   日替わり（D-307）：今日の特性が付いているダンジョンは、絵の右下に太陽と効果（Chests ×1.5 など）を出す。レアダンジョンには出さない（D-187）。

local AutoEquip = require("@game/ReplicatedStorage/Core/AutoEquip")
local ExclusiveGift = require("@game/ReplicatedStorage/Core/ExclusiveGift")
local Formulas = require("@game/ReplicatedStorage/Core/Formulas")
local Game = require("@game/ReplicatedStorage/Core/Game")
local Party = require("@game/ReplicatedStorage/Core/Party")
local Art = require("../ui/Art")
local Components = require("../ui/Components")
local Create = require("../ui/Create")
local Hint = require("../party/Hint")
local HubState = require("../hub/HubState")
local Motion = require("../ui/Motion")
local Nav = require("../ui/Nav")
local PartyIcon = require("../ui/PartyIcon")
local PickMode = require("../hub/PickMode")
local World3D = require("../hub/World3D")
local Root = require("../ui/Root")
local Session = require("../Session")
local Tokens = require("../ui/Tokens")
local Words = require("../ui/Words")
local WarehouseCommon = require("./warehouse/WarehouseCommon")
local master = require("../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local PANEL_X = 196
local PANEL_W = 420
local ART_H = 190 -- 中の背景の絵の高さ（D-282）
local HINT_H = 2 * 46 + 6 + 12
local ACTIONS_H = 82
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

local function roman(d: any): string
	return ROMAN[d.tier] or tostring(d.tier)
end

local function row(parent: GuiObject, order: number, height: number): Frame
	return new("Frame", {
		Name = "Row" .. order,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = C.ch75,
		[CHILDREN] = {
			Components.corner(6),
			Components.padding(0, 12, 0, 12),
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = parent,
	})
end

local function bar(parent: GuiObject, order: number, ratio: number, width: number, height: number): Frame
	local track: Frame = new("Frame", {
		Name = "Bar",
		LayoutOrder = order,
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = C.barTrack,
		[CHILDREN] = { Components.corner(8) },
		Parent = parent,
	})
	new("Frame", {
		Name = "Fill",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(math.clamp(ratio, 0, 1), -4, 1, -4),
		BackgroundColor3 = C.barFill,
		[CHILDREN] = { Components.corner(6) },
		Parent = track,
	})
	return track
end

local function label(parent: GuiObject, order: number, text: string, size: number, color: Color3?): TextLabel
	local t = Components.text({ text = text, size = size, color = color or C.inkDark, font = Tokens.font.number })
	t.LayoutOrder = order
	t.Parent = parent
	return t
end

-- 中の背景の絵（D-282）。locked は暗く沈める（色相は茶のまま：D-222）
local function artFrame(parent: GuiObject, d: any, locked: boolean, image: string?): Frame
	local f: Frame = new("Frame", {
		Name = "Art",
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, ART_H),
		BackgroundColor3 = C.ch13,
		ClipsDescendants = true,
		[CHILDREN] = { Components.corner(8) },
		Parent = parent,
	})
	local img = Art.put(f, image or Art.background(d.id), { scaleType = Enum.ScaleType.Crop, zIndex = f.ZIndex + 1 })
	if img then
		img.Name = "Bg"
		if locked then
			img.ImageColor3 = C.ch45
		end
	else
		-- 絵がまだないダンジョンは、ローマ数字を大きく（仮）
		local t = Components.text({ text = roman(d), size = Tokens.text.display, color = C.ch45 })
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.fromScale(0.5, 0.5)
		t.Parent = f
	end
	if locked then
		new("Frame", {
			Name = "Shade",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C.scrim,
			BackgroundTransparency = 0.45,
			ZIndex = f.ZIndex + 2,
			Parent = f,
		})
	end
	-- 縁（絵の上に重ねる）
	new("Frame", {
		Name = "Rim",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = f.ZIndex + 3,
		[CHILDREN] = { Components.corner(8), Components.stroke(C.ch16, 2) },
		Parent = f,
	})
	return f
end

-- 絵の上に重ねる札（左上の時計・右下の日替わり）。絵の中の物より上に出す
local function onArt(art: Frame, g: GuiObject)
	g.ZIndex = art.ZIndex + 5
	for _, x in g:GetDescendants() do
		if x:IsA("GuiObject") then
			x.ZIndex = art.ZIndex + 6
		end
	end
	g.Parent = art
end

-- 日替わりの特性の効果の語（D-307）。値は「×1.5」「+20%」「−30%」の形
local function traitText(trait: any): string?
	local fmt = Words.dailyTrait[trait.effect]
	if fmt == nil then
		return nil
	end
	local v = trait.value
	local shown = if trait.effect == "travelMult"
		then (1 - v) * 100
		elseif trait.effect == "atkPctPhysical" or trait.effect == "atkPctMagic" then v * 100
		else v
	return string.format(fmt, string.format("%g", math.floor(shown * 100 + 0.5) / 100))
end

local function build(params: any?, api: Nav.Api): Nav.Built
	local rareSlot = (params :: any).rareSlot :: number?
	local raidSlot = (params :: any).raidSlot :: number?
	local eventSlot = rareSlot or raidSlot -- マップイベントの面（D-307・D-309）
	local eventKind: string? = if rareSlot then "rareDungeon" elseif raidSlot then "raid" else nil
	local dungeonId = ((params :: any).dungeonId or "") :: string
	if eventSlot then
		-- レアダンジョン（D-307）：攻略ヒントは強さの基準のダンジョン（D-187）。レイドも同じダンジョンを表示用に持つ
		local v = Session.view
		dungeonId = if v then Game.query.rareDungeon(v, eventSlot, master).dungeonId else ""
	end
	-- レイドのボスの HP は seed から作るのでサーバーに聞く（D-152）。出発したパーティのダメージは要約の raid にある
	local raidQuery: any = nil
	local d = master.dungeons[dungeonId]
	local band = Root.bandBottom()
	local frame: Frame = new("Frame", {
		Name = "DungeonPanel",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	-- 作り直しで消えない演出の置き場（解放のハンコ）。絵と同じ位置
	local inset = Tokens.spacing.frame + 14
	local fx: Frame = new("Frame", {
		Name = "Fx",
		Position = UDim2.fromOffset(PANEL_X + inset, band + 44 + Tokens.spacing.frame + Tokens.spacing.panelPadPlaque),
		Size = UDim2.fromOffset(PANEL_W - inset * 2, ART_H),
		BackgroundTransparency = 1,
		ZIndex = 30,
		Parent = frame,
	})
	local busy = false
	local choosing = false -- Go の後に出す待機のパーティの一覧（D-272）
	local render: () -> ()
	-- ダンジョンを選んだときは、カメラがそのダンジョンへ寄って旋回する（メニューから開いたときも：D-270 ⑤）
	if eventKind and eventSlot then
		World3D.focusEvent(eventKind, eventSlot)
	else
		World3D.focusDungeon(dungeonId)
	end

	render = function()
		body:ClearAllChildren()
		local view = Session.view
		if view == nil or d == nil then
			return
		end
		local unlocked = eventSlot ~= nil or (view.unlockedDungeons and view.unlockedDungeons[dungeonId] == true)
		local fromParty = PickMode.partyIndex
		if eventSlot or (fromParty and HubState.status(view, fromParty).state ~= "waiting") then
			fromParty = nil
		end
		-- レアダンジョンに出発済みのパーティ（1パーティ1回まで：D-152）
		local joined: { [number]: boolean } = {}
		if rareSlot then
			for _, i in Game.query.rareDungeon(view, rareSlot, master).joined do
				joined[i] = true
			end
		end
		-- レイド：出発したパーティとボスの HP（要約の raid がその時間帯のものならそれ、なければ問い合わせ）
		local raidInfo: any = nil
		if raidSlot then
			local live = view.raid
			raidInfo = if live and live.eventSlot == raidSlot then live else raidQuery
			for _, i in (raidInfo and raidInfo.parties) or {} do
				joined[i] = true
			end
		end
		local mode = if not unlocked then "locked" elseif fromParty then "party" else "map"

		local panelH = Tokens.spacing.panelPadPlaque
			+ ART_H
			+ 10
			+ HINT_H
			+ 10
			+ ACTIONS_H
			+ 14
			+ 2 * Tokens.spacing.frame
		if mode == "party" then
			panelH += 44 + 10 -- 罠の避けやすさと移動時間の行
		end
		local panel, content = Components.panel({
			size = UDim2.fromOffset(PANEL_W, panelH),
			position = UDim2.fromOffset(PANEL_X, band + 44),
			title = if rareSlot
				then Words.rareDungeon
				elseif raidSlot then Words.raidBoss
				elseif mode == "locked" then { roman(d), d.nameEn, "@locked" }
				else roman(d) .. "  " .. d.nameEn,
		})
		panel.Name = "Panel"
		panel.Parent = body
		local close = Components.closeButton(api.close)
		close.AnchorPoint = Vector2.new(0.5, 0.5)
		close.Position = UDim2.new(1, -12, 0, 12)
		close.ZIndex = 20
		close.Parent = panel
		new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })

		-- 中の背景の絵（D-282）
		local art = artFrame(content, d, mode == "locked", if eventKind then Art.eventBackground(eventKind) else nil)
		if eventSlot then
			-- 左上：締め切りまでの時計（下の時計の処理で書き換える）
			local timer = Components.chip("@time", "", C.bronzeHi)
			timer.Name = "Timer"
			timer.Position = UDim2.fromOffset(8, 8)
			onArt(art, timer)
		else
			-- 右下：日替わりの特性（太陽・金：D-162）
			for _, dt in Game.query.dailyTraits(Session.now(), master).today do
				local trait = if dt.dungeonId == dungeonId then master.dailyTraits[dt.traitId] else nil
				local text = if trait then traitText(trait) else nil
				if text then
					local chip = Components.chip("@daily", text, C.coinGold)
					chip.Name = "Daily"
					chip.AnchorPoint = Vector2.new(1, 1)
					chip.Position = UDim2.new(1, -8, 1, -8)
					local st = chip:FindFirstChildOfClass("UIStroke")
					if st then
						st.Color = C.coinGold
						st.Thickness = 3
					end
					onArt(art, chip)
				end
			end
		end

		-- 攻略ヒント（D-048。初めての人に読める2行だけ：D-250 ③）
		local hint: Frame = new("Frame", {
			Name = "Hint",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, HINT_H),
			BackgroundColor3 = C.ch50,
			[CHILDREN] = {
				Components.corner(8),
				Components.padding(6, 6, 6, 6),
				new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
			},
			Parent = content,
		})
		local function heading(r: Frame, word: string)
			local t = Components.text({ text = word, size = 21, color = C.inkDark, font = Tokens.font.display })
			t.Name = "Heading"
			t.LayoutOrder = 0
			t.AutomaticSize = Enum.AutomaticSize.None
			t.Size = UDim2.fromOffset(78, 30)
			t.TextXAlignment = Enum.TextXAlignment.Left
			t.Parent = r
		end
		if raidSlot then
			-- レイド（D-309）：ボスの HP の残りと、出発したパーティ
			local rb = row(hint, 1, 46)
			heading(rb, Words.boss)
			local hp = if raidInfo then math.max(1, raidInfo.hp or 1) else 1
			local remain = if raidInfo then math.max(0, hp - (raidInfo.damage or 0)) else hp
			local track = bar(rb, 1, remain / hp, 250, 26)
			local fill = track:FindFirstChild("Fill") :: Frame?
			if fill then
				fill.BackgroundColor3 = C.dangerRed
			end
			local rj = row(hint, 2, 46)
			heading(rj, Words.joined)
			local n = 0
			for i in joined do
				n += 1
				local face = PartyIcon.make(34)
				face.LayoutOrder = i
				face.Parent = rj
				PartyIcon.set(face, view, i)
			end
			if n == 0 then
				label(rj, 1, "—", 23, C.ch45)
			end
		end
		local r2 = row(hint, 1, 46)
		r2.Visible = raidSlot == nil
		heading(r2, Words.foes)
		for i, rc in Hint.races(d, master) do
			local t = WarehouseCommon.pill("", rc.word, 21)
			t.BackgroundColor3 = C.ch75
			local first = i == 1
			Components.stroke(if first then C.inkDark else C.ch45, if first then 3 else 2).Parent = t
			for _, c in t:GetDescendants() do
				if c:IsA("TextLabel") then
					c.TextColor3 = C.inkDark
				end
			end
			t.LayoutOrder = i
			t.Parent = r2
		end
		local r3 = row(hint, 2, 46)
		r3.Visible = raidSlot == nil
		heading(r3, Words.traps)
		label(r3, 1, "⚠", 25)
		local trap = WarehouseCommon.pill("", tostring(d.trapLevel), 23)
		trap.LayoutOrder = 2
		trap.Parent = r3

		local actions: Frame = new("Frame", {
			Name = "Actions",
			LayoutOrder = 9,
			Size = UDim2.new(1, 0, 0, ACTIONS_H),
			BackgroundTransparency = 1,
			[CHILDREN] = {
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Right,
					VerticalAlignment = Enum.VerticalAlignment.Bottom,
					Padding = UDim.new(0, 12), -- サブはメインのすぐ左（D-219 ③）
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = content,
		})

		if mode == "party" then
			-- ① パーティから：罠の避けやすさ、移動時間、Go
			local p = fromParty :: number
			local evade, travel = Hint.forParty(view, p, d, master, deps)
			local est = row(content, 3, 44)
			est.BackgroundTransparency = 1
			-- 罠のよけやすさ：語と % と棒（D-269 ①④。記号の ⚠ だけでは分からなかった）
			label(est, 1, "Dodge", 23)
			bar(est, 2, evade, 116, 26)
			local dp =
				WarehouseCommon.pill("", string.format("%d%%", math.floor(math.clamp(evade, 0, 1) * 100 + 0.5)), 23)
			dp.LayoutOrder = 3
			dp.Parent = est
			label(est, 4, "@time", 25)
			local secs = math.floor(travel + 0.5)
			local tp = WarehouseCommon.pill("", string.format("%d:%02d", secs // 60, secs % 60), 23)
			tp.LayoutOrder = 5
			tp.Parent = est
			local go = Components.button({
				kind = "gold",
				width = 240,
				icon = "▶",
				label = Words.go,
				name = "Go",
				glyph = "A",
				onClick = function()
					if busy then
						return
					end
					busy = true
					local r = Session.sendAndWait({ type = "Dispatch", partyIndex = p, dungeonId = dungeonId })
					busy = false
					if r and r.ok then
						PickMode.stop()
						HubState.selected = p
						api.close()
						task.delay(0.3, function()
							World3D.focusParty(p) -- 出た馬車へカメラを寄せる
						end)
					else
						render()
					end
				end,
			})
			go.Parent = actions
		elseif mode == "map" then
			-- ② マップから：ボタンは Go だけ（D-282）。押すと待機のパーティの一覧を出す（D-272）
			local waiting = {}
			for _, party in view.parties or {} do
				if HubState.status(view, party.index).state == "waiting" and not joined[party.index] then
					local members = 0
					for _, uid in party.slots do
						if view.adventurers[uid] then
							members += 1
						end
					end
					table.insert(waiting, { index = party.index, members = members })
				end
			end
			local anyWaiting = #waiting > 0
			local go = Components.button({
				kind = if anyWaiting then "gold" else "disabled",
				width = 240,
				icon = "▶",
				label = Words.go,
				name = "Go",
				glyph = "A",
				reason = Words.reason.allOut, -- 待機中のパーティがいない（D-272 ②）
				onClick = function()
					if anyWaiting then
						choosing = true
						render()
					end
				end,
			})
			go.Parent = actions
			-- 待機中のパーティの一覧（リーダーのアイコンと名前：D-272 ①・D-271 ③）
			if choosing and anyWaiting then
				local scrim: TextButton = new("TextButton", {
					Name = "PartyChooser",
					Text = "",
					AutoButtonColor = false,
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = C.scrim,
					BackgroundTransparency = 0.45,
					ZIndex = 40,
					Parent = body,
				})
				scrim.Activated:Connect(function()
					choosing = false
					render()
				end)
				local sheet, sc = Components.panel({
					size = UDim2.fromOffset(420, 120 + #waiting * 84),
					position = UDim2.fromScale(0.5, 0.5),
					anchor = Vector2.new(0.5, 0.5),
					title = Words.go,
				})
				sheet.ZIndex = 41
				sheet.Parent = scrim
				new("UIListLayout", {
					Padding = UDim.new(0, 10),
					SortOrder = Enum.SortOrder.LayoutOrder,
					Parent = sc,
				})
				for k, w in waiting do
					local rowB: TextButton = new("TextButton", {
						Name = "Party" .. w.index,
						LayoutOrder = k,
						Text = "",
						AutoButtonColor = false,
						Size = UDim2.new(1, 0, 0, 74),
						BackgroundColor3 = C.ch28,
						ZIndex = 42,
						[CHILDREN] = { Components.corner(12), Components.stroke(C.bronze, 3) },
						Parent = sc,
					})
					local icon = PartyIcon.make(56)
					icon.Position = UDim2.fromOffset(10, 9)
					icon.Parent = rowB
					PartyIcon.set(icon, view, w.index, "waiting")
					local nm = Components.text({
						text = PartyIcon.name(view, w.index),
						size = 25,
						color = C.inkLight,
						font = Tokens.font.display,
						xAlign = Enum.TextXAlignment.Left,
					})
					nm.AnchorPoint = Vector2.new(0, 0.5)
					nm.Position = UDim2.new(0, 80, 0.5, 0)
					nm.Parent = rowB
					local cnt = WarehouseCommon.pill("@roster", tostring(w.members), 21)
					cnt.AnchorPoint = Vector2.new(1, 0.5)
					cnt.Position = UDim2.new(1, -12, 0.5, 0)
					cnt.Parent = rowB
					rowB.Activated:Connect(function()
						if busy then
							return
						end
						busy = true
						local r = Session.sendAndWait(
							if eventSlot
								then { type = "DispatchEvent", partyIndex = w.index, eventSlot = eventSlot }
								else { type = "Dispatch", partyIndex = w.index, dungeonId = dungeonId }
						)
						busy = false
						choosing = false
						if r and r.ok then
							HubState.selected = w.index
							api.close()
							task.delay(0.3, function()
								World3D.focusParty(w.index) -- 出た馬車へカメラを寄せる
							end)
						else
							render()
						end
					end)
				end
			end
		else
			-- ③ 未解放：絵の上に「鍵 → 前のダンジョン（踏破の印）」。踏破の無料の解放は残す（D-279）
			local prevId = d.unlockAfterClear
			local prev = if prevId then master.dungeons[prevId] else nil
			local cond: Frame = new("Frame", {
				Name = "Condition",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, 0, 0, 66),
				BackgroundTransparency = 1,
				ZIndex = art.ZIndex + 4,
				[CHILDREN] = {
					new("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 16),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				},
				Parent = art,
			})
			local function raise(g: GuiObject)
				g.ZIndex = art.ZIndex + 5
				for _, x in g:GetDescendants() do
					if x:IsA("GuiObject") then
						x.ZIndex = art.ZIndex + 6
					end
				end
			end
			raise(label(cond, 1, "@locked", 48, C.inkLight))
			if prev then
				raise(label(cond, 2, "→", 30, C.inkLight))
				local circle = WarehouseCommon.pill("✓", roman(prev), 23)
				circle.LayoutOrder = 3
				circle.Parent = cond
				raise(circle)
			end
			-- 金の Unlock と金額（D-279）。前のダンジョンが解放済みで、ゴールドが足りるときだけ押せる
			local price = (d :: any).unlockGold :: number?
			if price then
				local prevOpen = prevId == nil or (view.unlockedDungeons and view.unlockedDungeons[prevId] == true)
				local enough = (view.gold or 0) >= price
				local can = prevOpen and enough
				local unlockBtn = Components.button({
					kind = if can then "gold" else "disabled",
					width = 300,
					icon = "@locked",
					label = Words.unlock,
					cost = HubState.formatNumber(price),
					name = "Unlock",
					glyph = "A",
					reason = if not prevOpen then Words.reason.prevLocked else Words.reason.notEnoughGold,
					onClick = function()
						if busy then
							return
						end
						busy = true
						local r = Session.sendAndWait({ type = "UnlockDungeon", dungeonId = dungeonId })
						busy = false
						if r and r.ok then
							render() -- 解放済みの形（② の Go）で作り直す
							-- 解放のハンコ（D-269）。絵の上に押して、少し見せたら消す
							local stamp = Motion.stamp(fx, Words.unlocked, C.okGreen, 170)
							task.delay(Motion.T.bubble, function()
								stamp:Destroy()
							end)
							return
						end
						local why = if r and r.error == "NOT_ENOUGH_GOLD"
							then Words.reason.notEnoughGold
							elseif r and r.error == "DUNGEON_PREV_LOCKED" then Words.reason.prevLocked
							else nil
						-- DUNGEON_ALREADY_UNLOCKED などは作り直せば解放済みの形になる
						render()
						if why then
							local b = body:FindFirstChild("Unlock", true)
							local face = if b then b:FindFirstChild("Face") else nil
							if face and face:IsA("GuiObject") then
								Motion.reason(face, why)
							end
						end
					end,
				})
				unlockBtn.Parent = actions
			end
		end
	end

	-- 面の中身が変わるもの（解放・ゴールド・待機のパーティ・選んだパーティのメンバー）が変わったときだけ作り直す。
	-- 毎回作り直すと中の絵の読み込みがちらつくため
	local function keyOf(view: any): string
		local parts = {
			tostring(view.unlockedDungeons and view.unlockedDungeons[dungeonId]),
			if rareSlot then table.concat(Game.query.rareDungeon(view, rareSlot, master).joined, ",") else "",
			if raidSlot
					and view.raid
					and view.raid.eventSlot == raidSlot
				then table.concat(view.raid.parties or {}, ",") .. ":" .. tostring(view.raid.damage)
				else tostring(raidQuery ~= nil),
			tostring(view.unlockedDungeons and d and d.unlockAfterClear and view.unlockedDungeons[d.unlockAfterClear]),
			tostring(view.gold),
			tostring(PickMode.partyIndex),
		}
		for _, party in view.parties or {} do
			table.insert(parts, HubState.status(view, party.index).state .. ":" .. table.concat(party.slots, ","))
		end
		return table.concat(parts, "|")
	end
	local lastKey = ""
	render()
	if Session.view then
		lastKey = keyOf(Session.view)
	end
	local conn = Session.changed:connect(function(view: any)
		if busy or view == nil then
			return
		end
		local key = keyOf(view)
		if key ~= lastKey then
			lastKey = key
			render()
		end
	end)
	-- レアダンジョン：左上の時計を書き換え、締め切ったら閉じる（D-307）
	local alive = true
	if raidSlot then
		task.spawn(function()
			raidQuery = Session.query({ kind = "raid", eventSlot = raidSlot })
			if alive and not busy then
				render()
				if Session.view then
					lastKey = keyOf(Session.view)
				end
			end
		end)
	end
	if eventSlot then
		task.spawn(function()
			while alive do
				local view = Session.view
				local cur = if view then Game.query.mapEvent(Session.now(), master, view).current else nil
				if cur == nil or not cur.open or cur.kind ~= eventKind or cur.eventSlot ~= eventSlot then
					api.close()
					return
				end
				local timer = body:FindFirstChild("Timer", true)
				if timer then
					local labels = {}
					for _, c in timer:GetChildren() do
						if c:IsA("TextLabel") then
							table.insert(labels, c)
						end
					end
					local left = math.max(0, math.ceil(cur.closesIn or 0))
					local lbl = labels[2]
					if lbl then
						lbl.Text = string.format("%s %d:%02d", Words.leavesIn, left // 60, left % 60)
						lbl.TextColor3 = if left <= master.K.mapEventEndingSeconds then C.warn else C.inkLight
					end
				end
				task.wait(0.25)
			end
		end)
	end
	return {
		frame = frame,
		scrim = 0.5, -- 後ろの暗幕は 50%（D-225 ③）
		passThrough = true, -- 開いたままでも 3D マップのカメラを動かせる（D-270）
		destroy = function()
			alive = false
			conn.disconnect()
		end,
	}
end

Nav.register("DungeonPanel", build)

return {}
