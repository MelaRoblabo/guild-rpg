--!strict
-- S-15 行き先・ダンジョンの面（D-048・D-113・D-114・D-130・D-163・D-209・D-225 ③・D-231 ⑤⑦・D-232 ⑨・D-235 ①②）。
--   マップのダンジョンを触って開く。パーティの面と同じ位置・形（x196・幅420・羊皮紙・× は面の角）。中身は3通り：
--   ① パーティから（S-12 の金 → マップで選ぶ：hub/PickMode）：攻略ヒント＋このパーティの4人（有利な区分の人に緑の輪）
--      ＋罠の避けやすさの棒＋移動時間。右下の金＝Go（馬車＋パーティの番号）。
--   ② マップから：攻略ヒント＋適性のある4人（D-114）。下に待機のパーティの札（番号＋状態）を並べて選び、
--      金＝選んだパーティでこのダンジョンへ Go、茶のサブ＝この4人で編成（D-244 ③。D-235 ① の「金＝編成」を置き換え）。
--      探索中の人・ほかのパーティの人は入れられないので、空いている人と選んだパーティの人から選び直す（D-235 ①）。
--   ③ 未解放：ヒントは出す。解放の条件は「鍵 → 前のダンジョンの丸（踏破の印）」。ボタンはない（解放は無料・自動）。
--   攻略ヒント：攻撃の種類の割合（剣と光の玉の帯）、多い種族（英語の短い語を多い順、一番多いものは濃い縁）、罠Lv、フロアの印。
--   派遣費は出さない（D-163）。マップイベント（レアダンジョン・レイド）の面は ④ の画面で作る。

local AutoEquip = require("@game/ReplicatedStorage/Core/AutoEquip")
local ExclusiveGift = require("@game/ReplicatedStorage/Core/ExclusiveGift")
local Formulas = require("@game/ReplicatedStorage/Core/Formulas")
local Game = require("@game/ReplicatedStorage/Core/Game")
local Party = require("@game/ReplicatedStorage/Core/Party")
local Components = require("../ui/Components")
local Create = require("../ui/Create")
local Hint = require("../party/Hint")
local HubState = require("../hub/HubState")
local Nav = require("../ui/Nav")
local PickMode = require("../hub/PickMode")
local Root = require("../ui/Root")
local Session = require("../Session")
local Tokens = require("../ui/Tokens")
local WarehouseCommon = require("./warehouse/WarehouseCommon")
local master = require("../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local PANEL_X = 196
local PANEL_W = 420
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

-- 顔の札（66×66。右下に攻撃の区分の丸：有利なら緑の縁）
local function face(parent: GuiObject, order: number, adv: any, fav: string?, dim: boolean, partyTag: string?): Frame
	local job = master.jobs[adv.jobId]
	local holder: Frame = new("Frame", {
		Name = "Face_" .. adv.uid,
		LayoutOrder = order,
		Size = UDim2.fromOffset(78, 96),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local f: Frame = new("Frame", {
		Name = "Face",
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.fromOffset(66, 66),
		BackgroundColor3 = C.ch13,
		BackgroundTransparency = if dim then 0.5 else 0,
		[CHILDREN] = { Components.corner(12), Components.stroke(C.ch16, 2) },
		Parent = holder,
	})
	local g = Components.text({ text = "♟", size = 30, color = C.ch45, font = Tokens.font.number })
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Position = UDim2.fromScale(0.5, 0.5)
	g.Parent = f
	local isFav = fav ~= nil and job ~= nil and job.attackType == fav
	new("TextLabel", {
		Name = "Attack",
		Text = if job and job.attackType == "magic" then "◈" else "⚔",
		TextSize = 16,
		FontFace = Tokens.font.number,
		TextColor3 = C.inkLight,
		BackgroundColor3 = C.ch16,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 1, -4),
		Size = UDim2.fromOffset(30, 30),
		ZIndex = 3,
		[CHILDREN] = {
			Components.corner(15),
			Components.stroke(if isFav then C.okGreen else C.bronze, if isFav then 3 else 2),
		},
		Parent = f,
	})
	if partyTag then
		local tag = WarehouseCommon.pill("", partyTag, 21)
		tag.AnchorPoint = Vector2.new(0, 0)
		tag.Position = UDim2.fromOffset(-8, -8)
		tag.ZIndex = 3
		tag.Parent = f
	end
	local nm = Components.text({ text = adv.name, size = 21, color = C.inkDark, font = Tokens.font.number })
	nm.AnchorPoint = Vector2.new(0.5, 0)
	nm.Position = UDim2.new(0.5, 0, 0, 70)
	nm.AutomaticSize = Enum.AutomaticSize.None
	nm.Size = UDim2.fromOffset(90, 26)
	nm.TextTruncate = Enum.TextTruncate.AtEnd
	nm.Parent = holder
	return holder
end

local function build(params: any?, api: Nav.Api): Nav.Built
	local dungeonId = (params :: any).dungeonId :: string
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
	local pickParty: number? = nil -- マップから：編成先の待機のパーティ
	local busy = false
	local render: () -> ()

	render = function()
		body:ClearAllChildren()
		local view = Session.view
		if view == nil or d == nil then
			return
		end
		local unlocked = view.unlockedDungeons and view.unlockedDungeons[dungeonId] == true
		local fromParty = PickMode.partyIndex
		if fromParty and HubState.status(view, fromParty).state ~= "waiting" then
			fromParty = nil
		end
		local mode = if not unlocked then "locked" elseif fromParty then "party" else "map"
		local fav = Hint.favored(d)

		local panel, content = Components.panel({
			size = UDim2.fromOffset(PANEL_W, if mode == "locked" then 420 else 556),
			position = UDim2.fromOffset(PANEL_X, band + 44),
			title = roman(d) .. "  " .. d.nameEn .. (if mode == "locked" then "  🔒" else ""),
		})
		panel.Name = "Panel"
		panel.Parent = body
		local close = Components.closeButton(api.close)
		close.AnchorPoint = Vector2.new(0.5, 0.5)
		close.Position = UDim2.new(1, -12, 0, 12)
		close.ZIndex = 20
		close.Parent = panel
		new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })

		-- 攻略ヒント（D-048）
		local hint: Frame = new("Frame", {
			Name = "Hint",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 4 * 46 + 3 * 6 + 12),
			BackgroundColor3 = C.ch50,
			[CHILDREN] = {
				Components.corner(8),
				Components.padding(6, 6, 6, 6),
				new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
			},
			Parent = content,
		})
		local phys = AutoEquip.weights(dungeonId, master)
		local r1 = row(hint, 1, 46)
		label(r1, 1, "⚔", 25)
		bar(r1, 2, phys, 260, 22)
		label(r1, 3, "◈", 25, C.statMag)
		local r2 = row(hint, 2, 46)
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
		local r3 = row(hint, 3, 46)
		label(r3, 1, "⚠", 25)
		local trap = WarehouseCommon.pill("", tostring(d.trapLevel), 23)
		trap.LayoutOrder = 2
		trap.Parent = r3
		local r4 = row(hint, 4, 46)
		r4:FindFirstChildOfClass("UIListLayout").Padding = UDim.new(0, 4)
		for f = 1, d.floors do
			local boss = f == d.floors
			local event = f % 2 == 0 and not boss
			new("Frame", {
				Name = "Floor" .. f,
				LayoutOrder = f,
				Size = UDim2.fromOffset(if boss then 20 else 14, if boss then 20 else 14),
				Rotation = if event then 45 else 0,
				BackgroundTransparency = 1,
				[CHILDREN] = { Components.corner(if event then 2 else 10), Components.stroke(C.inkMid, 2) },
				Parent = r4,
			})
		end

		local actions: Frame = new("Frame", {
			Name = "Actions",
			LayoutOrder = 9,
			Size = UDim2.new(1, 0, 0, 82),
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
		})

		if mode == "party" then
			-- ① パーティから：4人（有利な区分に緑の輪）、罠の避けやすさ、移動時間、Go
			local p = fromParty :: number
			local faces: Frame = new("Frame", {
				Name = "Members",
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 96),
				BackgroundTransparency = 1,
				[CHILDREN] = {
					new("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						Padding = UDim.new(0, 8),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				},
				Parent = content,
			})
			for i, uid in view.parties[p].slots do
				local adv = view.adventurers[uid]
				if adv then
					face(faces, i, adv, fav, false, nil)
				end
			end
			local evade, travel = Hint.forParty(view, p, d, master, deps)
			local est = row(content, 3, 44)
			est.BackgroundTransparency = 1
			label(est, 1, "⚠", 25)
			bar(est, 2, evade, 190, 26)
			label(est, 3, "🕒", 25) -- ◷ は出ない
			local secs = math.floor(travel + 0.5)
			local tp = WarehouseCommon.pill("", string.format("%d:%02d", secs // 60, secs % 60), 23)
			tp.LayoutOrder = 4
			tp.Parent = est
			actions.Parent = content
			local go = Components.button({
				kind = "gold",
				width = 240,
				icon = "▶",
				label = tostring(p),
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
						HubState.following = true
						api.close()
					else
						render()
					end
				end,
			})
			go.Parent = actions
		elseif mode == "map" then
			-- ② マップから：適性の4人＋待機のパーティの札＋この4人で編成
			local waiting = {}
			for _, party in view.parties or {} do
				if HubState.status(view, party.index).state == "waiting" then
					table.insert(waiting, party.index)
				end
			end
			if pickParty == nil or table.find(waiting, pickParty) == nil then
				pickParty = waiting[1]
			end
			-- 入れられる人：探索中でなく、どのパーティにもいないか、選んだパーティにいる（D-235 ①・SetPartySlot）
			local sub = table.clone(view)
			local advs = {}
			for uid, a in view.adventurers do
				local inParty = Party.find(view, uid)
				if not Party.isAdventurerBusy(view, uid) and (inParty == nil or inParty == pickParty) then
					advs[uid] = a
				end
			end
			sub.adventurers = advs
			local suited = Hint.suited(sub, d, true, master, deps)
			local faces: Frame = new("Frame", {
				Name = "Suited",
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 96),
				BackgroundTransparency = 1,
				[CHILDREN] = {
					new("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						Padding = UDim.new(0, 8),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				},
				Parent = content,
			})
			for i, uid in suited do
				local inParty = Party.find(view, uid)
				face(faces, i, view.adventurers[uid], fav, false, if inParty then "♟" .. inParty else nil)
			end
			-- 待機のパーティの札（番号＋状態。D-231 ⑰と同じ形）
			local picks: Frame = new("Frame", {
				Name = "Parties",
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, 66),
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
			for _, party in view.parties or {} do
				local st = HubState.status(view, party.index).state
				local ok = st == "waiting"
				local sel = ok and pickParty == party.index
				local b: TextButton = new("TextButton", {
					Name = "Party" .. party.index,
					LayoutOrder = party.index,
					Text = party.index .. "  " .. (if ok then "⌂" else "●"),
					TextSize = 25,
					FontFace = Tokens.font.display,
					TextColor3 = C.inkLight,
					TextTransparency = if ok then 0 else 0.5,
					AutoButtonColor = false,
					Active = ok,
					Size = UDim2.fromOffset(109, 66),
					BackgroundColor3 = if ok then C.ch28 else C.ch16,
					[CHILDREN] = {
						Components.corner(14),
						Components.stroke(if sel then C.selAmber elseif ok then C.bronze else C.ch28, 3),
					},
					Parent = picks,
				})
				if ok then
					b.Activated:Connect(function()
						pickParty = party.index
						render()
					end)
				end
			end
			actions.Parent = content
			local form = Components.button({
				kind = if pickParty and #suited > 0 then "brown" else "disabled",
				width = 130,
				height = 66,
				icon = "♟✚",
				name = "Form",
				glyph = "X",
				onClick = function()
					if busy or pickParty == nil then
						return
					end
					busy = true
					for slot, uid in suited do
						Session.sendAndWait({
							type = "SetPartySlot",
							partyIndex = pickParty,
							slot = slot,
							adventurerUid = uid,
						})
					end
					busy = false
					HubState.selected = pickParty
					api.close()
				end,
			})
			form.LayoutOrder = 1
			form.Parent = actions
			-- 金＝選んだパーティでこのダンジョンへ Go（D-244 ③）。メンバーがいなければ押せない色
			local members = 0
			if pickParty then
				for _, uid in view.parties[pickParty].slots do
					if view.adventurers[uid] then
						members += 1
					end
				end
			end
			local canGo = pickParty ~= nil and members > 0
			local go = Components.button({
				kind = if canGo then "gold" else "disabled",
				width = 240,
				icon = "▶",
				label = if pickParty then tostring(pickParty) else nil,
				name = "Go",
				glyph = "A",
				onClick = function()
					if busy or not canGo then
						return
					end
					busy = true
					local r = Session.sendAndWait({ type = "Dispatch", partyIndex = pickParty, dungeonId = dungeonId })
					busy = false
					if r and r.ok then
						HubState.selected = pickParty
						HubState.following = true
						api.close()
					else
						render()
					end
				end,
			})
			go.LayoutOrder = 2
			go.Parent = actions
		else
			-- ③ 未解放：鍵 → 前のダンジョン（踏破の印）
			local prev = if d.unlockAfterClear then master.dungeons[d.unlockAfterClear] else nil
			local cond = row(content, 2, 66)
			cond.BackgroundTransparency = 1
			cond:FindFirstChildOfClass("UIListLayout").HorizontalAlignment = Enum.HorizontalAlignment.Center
			cond:FindFirstChildOfClass("UIListLayout").Padding = UDim.new(0, 16)
			label(cond, 1, "🔒", 30)
			label(cond, 2, "→", 30)
			if prev then
				local circle = WarehouseCommon.pill("✓", roman(prev), 23)
				circle.LayoutOrder = 3
				circle.Parent = cond
			end
		end
	end

	render()
	local conn = Session.changed:connect(function()
		if not busy then
			render()
		end
	end)
	return {
		frame = frame,
		scrim = 0.5, -- 後ろの暗幕は 50%（D-225 ③）
		destroy = function()
			conn.disconnect()
		end,
	}
end

Nav.register("DungeonPanel", build)

return {}
