--!strict
-- S-12 編成の面（タイトル Edit Party：D-265 ④⑥。D-005・D-120・D-130・D-216・D-231 ⑦⑨⑩・D-232 ⑧・D-266・D-269）。
--   開き方：待機中のパーティの面の Edit Party、採用の後の Add to Party、冒険者の詳細の Add to Party。× は右上。
--   - 上：羊皮紙のパネルに隊列1〜4のカード（左が1番）。題の札＝パーティの印＋番号＋Edit Party。
--     カード：肖像＋名前＋職業の札＋★転生＋Lv／ATK・DEF・MDEF の凹み（語つき：D-269 ④）／最大HP の棒／装備の枠3つ（押すと S-42）。
--     被弾の ⚠＋棒は出さない（D-269 ①）。代わりにカードの下の縁に的の印（D-284）：よく狙われる隊列ほど大きく明るい。
--     率は D-005 の hitWeights（マスターデータ）を入っている人だけで按分する（HitMark）。文字・数字は出さない。
--   - パーティの中の並び替え（D-284）：隊列のカードを持ち上げてほかの隊列へ落とすと入れ替わる（空きなら移る）。
--     SetPartySlot 1回で入れ替わる（同じパーティの人なら入れ替え）。2人の顔が互いの隊列へ飛ぶ。
--   - 左下：控えの列（Reserve）を常に出す。カードは顔の絵・名前・Lv・職業のアイコン。新しく来た人は先頭に NEW で脈打つ。
--     ほかのパーティの人は番号つきで沈める（入れられない）。
--   - 入れ替え（D-265 ④）：
--       ドラッグ：控えのカードを持ち上げると隊列のカードが脈打ち、落とした隊列と入れ替わる。
--       タップ：控えのカードを押す → 隊列のカードが脈打つ → 隊列を押す。隊列を先に押すと控えのカードが脈打つ。
--     初めて雇った人がいるときは、控えの列の上に1行の案内（Drag a reserve onto a member：D-264 ④）。
--   - 控えから入った人は、その人の分だけ Auto Equip を確認なしで行う。装備が枠へ飛び、数字がカウントアップする（D-266 ②）。
--     Undo で入れ替えと自動装備をまとめて戻す（D-266 ③）。
--   - 右下：茶＝Undo（入れ替えた直後だけ）・Auto Equip（付け替えがなくても押せて理由を出す：D-266 ④）、金＝▶ Go（行けるダンジョンの一覧の窓 DungeonPick：D-282）。
--     Auto Equip は押すとすぐ決めず、変わるカードの差（▲▼）を見せる。金の Equip で決め、茶の Cancel でやめる（D-231 ⑨・D-235 ③）。

local UserInputService = game:GetService("UserInputService")

local AutoEquip = require("@game/ReplicatedStorage/Core/AutoEquip")
local Formulas = require("@game/ReplicatedStorage/Core/Formulas")
local Party = require("@game/ReplicatedStorage/Core/Party")
local AdvCommon = require("../adventurers/AdvCommon")
local ChestCommon = require("../chest/ChestCommon")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Art = require("../../ui/Art")
local HitMark = require("./HitMark")
local HubState = require("../../hub/HubState")
local Motion = require("../../ui/Motion")
local Portrait = require("../../ui/Portrait")
local Nav = require("../../ui/Nav")
require("./DungeonPick") -- 行き先の一覧の窓を登録する（D-282）
local Root = require("../../ui/Root")
local Screen = require("../Screen")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local Words = require("../../ui/Words")
local WarehouseCommon = require("../warehouse/WarehouseCommon")
local master = require("../../Master")

local C = Tokens.color
local I = AdvCommon.icon
local new = Create.new
local CHILDREN = Create.Children

local AUTO_ICON = "@auto_equip" -- 自動装備（D-258 の ui_auto_equip。絵がなければ記号）
local PANEL_H = 408 -- 隊列のパネルの高さ（被弾の帯をやめた分だけ低い）
local RESERVE_W = 560 -- 控えの列の幅（右下のボタンと重ならない幅）
local DRAG_START = 12 -- これだけ動いたらドラッグ（基準の単位ではなく画面の画素）

local STAT_WORD = { atk = "ATK", pdef = "DEF", mdef = "MDEF" } -- 意味の決まらない数字に語（D-264 ②・D-269 ④）

-- 自動装備の提案を当てたときの、その人の実効値
local function snapAfter(view: any, adv: any, slot: number, plan: { any }): any
	local def = Party.memberDef(view, adv, slot)
	local eq = table.clone(def.equipment)
	for _, c in plan do
		if c.advUid == adv.uid then
			local e = view.equipment[c.to]
			eq[c.slot] = {
				baseId = e.baseId,
				rarity = e.rarity,
				grade = e.grade,
				itemLevel = e.itemLevel,
				modifierId = e.modifierId,
				modifierValue = e.modifierValue,
			}
		end
	end
	def.equipment = eq
	return Formulas.memberSnapshot(def, master)
end

-- 品の絵（飛ばす物）。絵がなければ枠の記号
local function itemVisual(item: any, slot: string): GuiObject
	local f: Frame = new("Frame", {
		Name = "FlyingItem",
		BackgroundColor3 = C.secondary,
		[CHILDREN] = {
			Components.corner(14),
			Components.stroke(ChestCommon.rarityColor(item.rarity), 3),
		},
	})
	if not Art.put(f, Art.equip(item), { inset = 6 }) then
		local t = Components.text({ text = I[slot], size = 28, color = C.inkLight, font = Tokens.font.number })
		t.AutomaticSize = Enum.AutomaticSize.None
		t.Size = UDim2.fromScale(1, 1)
		t.Parent = f
	end
	return f
end

type Undo = { slot: number, prevUid: string, uid: string, prevEquip: { [string]: string? } }

local function build(params: any?, api: Nav.Api): Nav.Built
	local partyIndex = (params :: any).partyIndex :: number
	local band = Root.bandBottom()
	local frame = Screen.scene("PartyMenu")
	Screen.closeTopRight(frame, api.close)
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local pickSlot: number? = nil -- タップで先に選んだ隊列
	local pickAdv: string? = nil -- タップで先に選んだ控えの人（次に押した隊列へ入れる）
	-- 雇ったばかりの人（採用の画面・帰還後の誘導から開いたとき）。控えの先頭で NEW・脈打つ
	local newcomer: string? = (params :: any).newcomer
	local equipMode = false -- 自動装備の差を見せている
	local undo: Undo? = nil
	local busy = false
	local stops: { () -> () } = {} -- 脈打つ動きを止める
	local cards: { [number]: Frame } = {} -- 隊列のカード（ドラッグの落とし先・飛ぶ先）
	local statLabels: { [number]: { [string]: TextLabel } } = {}
	local reserveCards: { [string]: GuiObject } = {}
	local markSize: { [number]: number } = {} -- 前に描いた的の直径（変わったら育つ・縮む）
	local render: () -> ()

	local function send(cmd: any): any?
		busy = true
		local r = Session.sendAndWait(cmd)
		busy = false
		return r
	end

	-- 控えの人（uid）を隊列（slot）へ入れる。入った人の分だけ自動装備し、動きで見せる（D-266 ②）
	local function swapIn(slot: number, uid: string)
		local view = Session.view
		if view == nil or busy then
			return
		end
		local party = view.parties[partyIndex]
		local prevUid = party.slots[slot]
		local adv = view.adventurers[uid]
		if adv == nil or prevUid == uid then
			return
		end
		local from = reserveCards[uid]
		local fromAt = if from then Motion.center(from) else nil
		local prevEquip = table.clone(adv.equipment)
		local r = send({ type = "SetPartySlot", partyIndex = partyIndex, slot = slot, adventurerUid = uid })
		if not (r and r.ok) then
			render()
			return
		end
		HubState.newcomers[uid] = nil
		if newcomer == uid then
			newcomer = nil
		end
		-- 入った直後の値（自動装備の前）
		local v2 = Session.view
		local before = Formulas.memberSnapshot(Party.memberDef(v2, v2.adventurers[uid], slot), master)
		local plan = AutoEquip.plan(v2, partyIndex, master, uid)
		if #plan > 0 then
			send({ type = "AutoEquip", partyIndex = partyIndex, adventurerUid = uid })
		end
		undo = { slot = slot, prevUid = prevUid, uid = uid, prevEquip = prevEquip }
		render()
		-- 入った人のカードが弾み、控えから顔が飛んで来る
		local card = cards[slot]
		if card and fromAt then
			local face: Frame = new("Frame", {
				BackgroundColor3 = C.ch13,
				[CHILDREN] = { Components.corner(12) },
			})
			Portrait.fill(face, adv.appearanceId)
			Motion.fly({ from = fromAt, to = card, visual = face, size = 80, endSize = 96, duration = 0.4 })
		end
		-- 自動装備：倉庫（右下の Auto Equip の辺り）から品が枠へ飛び、数字がカウントアップする
		local v3 = Session.view
		local after = Formulas.memberSnapshot(Party.memberDef(v3, v3.adventurers[uid], slot), master)
		for i, c in plan do
			local item = v3.equipment[c.to]
			local target = card and card:FindFirstChild("Slot_" .. c.slot, true)
			if item and target then
				Motion.fly({
					from = Vector2.new(980, 640),
					to = target :: GuiObject,
					visual = itemVisual(item, c.slot),
					size = 80,
					endSize = 66,
					delay = 0.35 + (i - 1) * 0.15,
				})
			end
		end
		local labels = statLabels[slot]
		if labels and #plan > 0 then
			task.delay(0.35 + #plan * 0.15 + 0.4, function()
				for key, label in labels do
					if label.Parent and before[key] ~= after[key] then
						Motion.countUp(label, before[key], after[key])
					end
				end
			end)
		end
	end

	-- 入れ替えと自動装備をまとめて戻す（D-266 ③）
	local function doUndo()
		local u = undo
		local view = Session.view
		if u == nil or view == nil or busy then
			return
		end
		undo = nil
		local adv = view.adventurers[u.uid]
		if adv then
			for _, s in { "weapon", "armor" } do
				local want = u.prevEquip[s]
				if adv.equipment[s] ~= want then
					if want and view.equipment[want] and view.equipment[want].equippedBy == nil then
						send({ type = "Equip", adventurerUid = u.uid, equipmentUid = want })
					elseif want == nil then
						send({ type = "Unequip", adventurerUid = u.uid, slot = s })
					end
				end
			end
		end
		send({ type = "SetPartySlot", partyIndex = partyIndex, slot = u.slot, adventurerUid = u.prevUid })
		render()
	end

	-- 顔の絵（飛ばす物）
	local function faceVisual(adv: any): Frame
		local face: Frame = new("Frame", {
			BackgroundColor3 = C.ch13,
			[CHILDREN] = { Components.corner(12) },
		})
		Portrait.fill(face, adv.appearanceId)
		return face
	end

	-- パーティの中で隊列 from の人を隊列 to へ（to に人がいれば入れ替え、空きなら移る：D-284）。
	--   SetPartySlot は同じパーティの人なら1回で入れ替えるので、途中の状態はできない。
	--   from が空きで to に人がいるときは、to の人を from へ移す（タップで空きを先に選んだとき）。
	--   fromAt：持ち上げた顔が飛び立つ所（ドラッグなら落とした所）
	local function moveWithin(from: number, to: number, fromAt: Vector2?)
		local view = Session.view
		if view == nil or busy or from == to then
			render()
			return
		end
		local party = view.parties[partyIndex]
		local a, b = party.slots[from], party.slots[to]
		local advA, advB = view.adventurers[a], view.adventurers[b]
		if advA == nil and advB == nil then
			render()
			return
		end
		local atFrom = if cards[from] then Motion.center(cards[from]) else nil
		local atTo = if cards[to] then Motion.center(cards[to]) else nil
		pickSlot, pickAdv = nil, nil
		undo = nil -- Undo は控えから入れた直後だけ（D-266 ③）
		local r = if advA
			then send({ type = "SetPartySlot", partyIndex = partyIndex, slot = to, adventurerUid = a })
			else send({ type = "SetPartySlot", partyIndex = partyIndex, slot = from, adventurerUid = b })
		render()
		if not (r and r.ok) then
			return
		end
		-- 2人の顔が互いの隊列へ飛ぶ（D-269 ⑤ の Fly）
		if advA and cards[to] and (fromAt or atFrom) then
			Motion.fly({
				from = (fromAt or atFrom) :: Vector2,
				to = cards[to],
				visual = faceVisual(advA),
				size = 96,
				endSize = 96,
				duration = 0.35,
			})
		end
		if advB and cards[from] and atTo then
			Motion.fly({
				from = atTo,
				to = cards[from],
				visual = faceVisual(advB),
				size = 96,
				endSize = 96,
				duration = 0.35,
			})
		end
	end

	-- ドラッグ（控えのカードを隊列へ落とす。隊列のカードをほかの隊列へ落とす：D-265 ④・D-284）
	--   from：隊列から持ち上げたときのその隊列（控えからなら nil）
	local drag: { uid: string, from: number?, start: Vector2, ghost: GuiObject?, moved: boolean }? = nil
	local justDragged = false
	-- ドラッグ中か、ドラッグを終えた直後か（指を離した所のボタンの Activated を無視する）
	local function dragging(): boolean
		local d = drag
		return justDragged or (d ~= nil and d.moved)
	end
	local function dropSlotAt(pos: Vector2): number?
		local pg = (game:GetService("Players").LocalPlayer :: Player):FindFirstChildOfClass("PlayerGui")
		if pg == nil then
			return nil
		end
		for _, g in pg:GetGuiObjectsAtPosition(pos.X, pos.Y) do
			for slot, card in cards do
				if g == card or g:IsDescendantOf(card) then
					return slot
				end
			end
		end
		return nil
	end
	local function toCanvas(pos: Vector2): Vector2
		local scale = math.max(Root.frame.scale, 0.01)
		return (pos - Root.canvas.AbsolutePosition) / scale
	end
	local dragConns: { RBXScriptConnection } = {}
	table.insert(
		dragConns,
		UserInputService.InputChanged:Connect(function(input)
			local d = drag
			if d == nil then
				return
			end
			local t = input.UserInputType
			if t ~= Enum.UserInputType.MouseMovement and t ~= Enum.UserInputType.Touch then
				return
			end
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			if not d.moved and (pos - d.start).Magnitude >= DRAG_START then
				d.moved = true
				local adv = Session.view and Session.view.adventurers[d.uid]
				local ghost: Frame = new("Frame", {
					Name = "DragGhost",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(96, 96),
					BackgroundColor3 = C.ch13,
					ZIndex = 905,
					[CHILDREN] = { Components.corner(14), Components.stroke(C.selAmber, 4) },
					Parent = Motion.layer(),
				})
				if adv then
					Portrait.fill(ghost, adv.appearanceId)
				end
				d.ghost = ghost
				-- 隊列のカードが脈打って「ここに落とせる」を示す（持ち上げた隊列は除く）
				for slot, card in cards do
					if slot ~= d.from then
						table.insert(stops, Motion.pulse(card))
					end
				end
				-- 持ち上げた隊列のカードは顔を薄くして「ここから動いている」を示す
				local src = if d.from then cards[d.from] else nil
				local srcFace = if src then src:FindFirstChild("Face") else nil
				if srcFace and srcFace:IsA("Frame") then
					srcFace.BackgroundTransparency = 0.6
					for _, g in srcFace:GetDescendants() do
						if g:IsA("ImageLabel") then
							g.ImageTransparency = 0.6
						end
					end
				end
			end
			if d.ghost then
				local c = toCanvas(pos)
				d.ghost.Position = UDim2.fromOffset(c.X, c.Y)
			end
		end)
	)
	table.insert(
		dragConns,
		UserInputService.InputEnded:Connect(function(input)
			local d = drag
			if d == nil then
				return
			end
			local t = input.UserInputType
			if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then
				return
			end
			drag = nil
			if d.ghost then
				d.ghost:Destroy()
			end
			if d.moved then
				justDragged = true
				task.defer(function()
					justDragged = false
				end)
				local at = Vector2.new(input.Position.X, input.Position.Y)
				local slot = dropSlotAt(at)
				pickAdv, pickSlot = nil, nil
				if slot and d.from then
					moveWithin(d.from, slot, toCanvas(at)) -- パーティの中の入れ替え（D-284）
				elseif slot then
					swapIn(slot, d.uid)
				else
					render()
				end
			end
		end)
	)

	render = function()
		for _, stop in stops do
			stop()
		end
		stops = {}
		cards = {}
		statLabels = {}
		reserveCards = {}
		body:ClearAllChildren()
		local view = Session.view
		if view == nil then
			return
		end
		local party = view.parties[partyIndex]
		if party == nil or Party.isBusy(view, partyIndex) then
			api.close()
			return
		end
		local plan = AutoEquip.plan(view, partyIndex, master)
		if equipMode and #plan == 0 then
			equipMode = false
		end
		if newcomer ~= nil and (view.adventurers[newcomer] == nil or Party.find(view, newcomer) ~= nil) then
			newcomer = nil
		end

		-- 隊列のパネル（題の札＝パーティの番号＋画面のタイトル：D-264 ②）
		local panel, content = Components.panel({
			size = UDim2.new(1, -80, 0, PANEL_H),
			position = UDim2.fromOffset(40, band + 44),
			title = { I.party, tostring(partyIndex), Words.title.editParty },
		})
		panel.Name = "Formation"
		panel.Parent = body
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = content,
		})
		-- 最大HP の棒の尺度：パーティで一番高い人が 3/4（宝箱 v3 と同じ表示用の倍率。Q6）
		local hpTop = 1
		for _, u in party.slots do
			local a = view.adventurers[u]
			if a then
				hpTop = math.max(hpTop, Formulas.memberSnapshot(Party.memberDef(view, a, 1), master).maxHp / 0.75)
			end
		end
		-- 被弾の割合（D-005 を入っている人だけで按分）。的の大きさと明るさにする（D-284）
		local shares = HitMark.shares(party.slots, master.K.hitWeights, Party.EMPTY)
		local topShare = HitMark.top(shares)
		local sizes: { [number]: number } = {}
		for slot = 1, Party.SIZE do
			local uid = party.slots[slot]
			local adv = view.adventurers[uid]
			local selected = pickSlot == slot
			local card: TextButton = new("TextButton", {
				Name = "Card" .. slot,
				LayoutOrder = slot,
				Text = "",
				AutoButtonColor = false,
				Size = UDim2.new(0.25, -8, 1, 0),
				BackgroundColor3 = C.ch75,
				[CHILDREN] = {
					Components.corner(6),
					Components.padding(10, 12, 10, 12),
					Components.stroke(
						if selected or pickAdv ~= nil then C.selAmber else C.ch68,
						if selected then 4 else 2
					),
				},
				Parent = content,
			})
			cards[slot] = card
			if pickAdv ~= nil then
				table.insert(stops, Motion.pulse(card)) -- 控えを選んでいる：入れられる隊列が脈打つ
			end
			-- 肖像
			local face: Frame = new("Frame", {
				Name = "Face",
				Size = UDim2.fromOffset(96, 120),
				BackgroundColor3 = C.ch13,
				[CHILDREN] = { Components.corner(8), Components.stroke(C.ch16, 2) },
				Parent = card,
			})
			if not (adv and Portrait.fill(face, adv.appearanceId)) then
				local t = Components.text({
					text = if adv then I.party else "✚",
					size = 44,
					color = if adv then C.ch45 else C.inkMid,
					font = Tokens.font.number,
				})
				t.AutomaticSize = Enum.AutomaticSize.None
				t.Size = UDim2.fromScale(1, 1)
				t.Parent = face
			end
			-- 被弾の的（カードの下の縁。空いている隊列には出さない：D-284）
			local share = shares[slot]
			if adv and share then
				local d = HitMark.diameter(share, topShare)
				local mark = HitMark.make(d, if topShare > 0 then share / topShare else 0, markSize[slot])
				mark.Position = UDim2.new(0.5, 0, 1, 4)
				mark.Parent = card
				sizes[slot] = d
			end
			-- 隊列のカードを持ち上げて、ほかの隊列へ落とす（D-284。マウスと指）
			if adv then
				card.InputBegan:Connect(function(input)
					local t = input.UserInputType
					if
						(t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch)
						and not busy
						and not equipMode
					then
						drag = {
							uid = adv.uid,
							from = slot,
							start = Vector2.new(input.Position.X, input.Position.Y),
							moved = false,
						}
					end
				end)
			end
			card.Activated:Connect(function()
				if equipMode or busy or dragging() then
					return
				end
				if pickAdv ~= nil then
					local a = pickAdv
					pickAdv = nil
					swapIn(slot, a)
					return
				end
				if pickSlot == nil then
					pickSlot = slot
					render()
				elseif pickSlot == slot then
					pickSlot = nil
					render()
				else
					-- 同じパーティ内の入れ替え（ドラッグと同じ。SetPartySlot は同じパーティの人なら入れ替える）
					moveWithin(pickSlot :: number, slot)
				end
			end)
			if adv then
				local job = master.jobs[adv.jobId]
				local info: Frame = new("Frame", {
					Name = "Info",
					Position = UDim2.fromOffset(106, 0),
					Size = UDim2.new(1, -106, 0, 120),
					BackgroundTransparency = 1,
					[CHILDREN] = {
						new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
					},
					Parent = card,
				})
				local nm = Components.text({
					text = adv.name,
					size = 23,
					color = C.inkDark,
					font = Tokens.font.display,
					xAlign = Enum.TextXAlignment.Left,
				})
				nm.LayoutOrder = 1
				nm.AutomaticSize = Enum.AutomaticSize.None
				nm.Size = UDim2.new(1, 0, 0, 28)
				nm.TextTruncate = Enum.TextTruncate.AtEnd
				nm.Parent = info
				local jt = WarehouseCommon.pill(
					if job and job.attackType == "magic" then "@job_magic" else "@job_physical",
					if job then job.nameEn else adv.jobId,
					21,
					C.inkLight
				)
				jt.LayoutOrder = 2
				jt.Parent = info
				local lv = Components.text({
					text = "",
					size = 21,
					color = C.inkDark,
					font = Tokens.font.number,
					xAlign = Enum.TextXAlignment.Left,
				})
				Components.setParts(lv, { I.rebirth, tostring(adv.rebirthCount or 0), "Lv" .. adv.level })
				lv.LayoutOrder = 3
				lv.Parent = info
				-- ATK・DEF・MDEF（語つき。自動装備の差は ▲▼）
				local before = Formulas.memberSnapshot(Party.memberDef(view, adv, slot), master)
				local after = if equipMode then snapAfter(view, adv, slot, plan) else before
				local stats: Frame = new("Frame", {
					Name = "Stats",
					Position = UDim2.fromOffset(0, 128),
					Size = UDim2.new(1, 0, 0, 54),
					BackgroundTransparency = 1,
					[CHILDREN] = {
						new("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							Padding = UDim.new(0, 4),
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
					},
					Parent = card,
				})
				statLabels[slot] = {}
				-- 3つの暗い凹み。上に語（ATK・DEF・MDEF）、下に数字（数字は暗い凹み：Guild UI 配色の決まり ⑦）
				local function stat(order: number, key: string)
					local b, a = before[key], after[key]
					local mark = if a > b then "▲" elseif a < b then "▼" else ""
					local well: Frame = new("Frame", {
						Name = "Stat_" .. key,
						LayoutOrder = order,
						Size = UDim2.new(1 / 3, -3, 1, 0),
						BackgroundColor3 = C.ch13,
						[CHILDREN] = { Components.corner(10) },
						Parent = stats,
					})
					local w = Components.text({
						text = STAT_WORD[key],
						size = 21,
						color = C.bronzeHi,
						font = Tokens.font.number,
					})
					w.AutomaticSize = Enum.AutomaticSize.None
					w.Position = UDim2.fromOffset(0, 2)
					w.Size = UDim2.new(1, 0, 0, 24)
					w.Parent = well
					local n = Components.text({
						text = tostring(a) .. mark,
						size = 21,
						color = if mark ~= "" then C.numHi else C.inkLight,
						font = Tokens.font.number,
					})
					n.AutomaticSize = Enum.AutomaticSize.None
					n.Position = UDim2.fromOffset(0, 26)
					n.Size = UDim2.new(1, 0, 0, 26)
					n.Parent = well
					statLabels[slot][key] = n
				end
				stat(1, "atk")
				stat(2, "pdef")
				stat(3, "mdef")
				-- 最大HP の棒（語と数字は棒の中）
				local hpTrack: Frame = new("Frame", {
					Name = "HP",
					Position = UDim2.fromOffset(30, 192),
					Size = UDim2.new(1, -30, 0, 32),
					BackgroundColor3 = C.barTrack,
					[CHILDREN] = { Components.corner(8) },
					Parent = card,
				})
				local ht = Components.text({ text = I.hp, size = 21, color = C.statHp, font = Tokens.font.number })
				ht.Position = UDim2.fromOffset(0, 196)
				ht.Parent = card
				new("Frame", {
					Name = "Fill",
					Position = UDim2.fromOffset(2, 2),
					Size = UDim2.new(math.clamp(after.maxHp / hpTop, 0, 1), -4, 1, -4),
					BackgroundColor3 = C.barFill,
					[CHILDREN] = { Components.corner(6) },
					Parent = hpTrack,
				})
				local hn = Components.text({
					text = "HP " .. tostring(after.maxHp),
					size = 23,
					color = C.inkWhite,
					font = Tokens.font.number,
					stroke = true,
				})
				hn.AnchorPoint = Vector2.new(0.5, 0.5)
				hn.Position = UDim2.fromScale(0.5, 0.5)
				hn.Parent = hpTrack
				-- 装備の枠3つ（押すと S-42）
				local eqRow: Frame = new("Frame", {
					Name = "Equipment",
					Position = UDim2.fromOffset(0, 234),
					Size = UDim2.new(1, 0, 0, 66),
					BackgroundTransparency = 1,
					[CHILDREN] = {
						new("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							Padding = UDim.new(0, 8),
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
					},
					Parent = card,
				})
				for k, s in { "weapon", "armor", "sub" } do
					local itemUid = adv.equipment[s]
					local item = if itemUid then view.equipment[itemUid] else nil
					local changing = false
					if equipMode then
						for _, c in plan do
							if c.advUid == adv.uid and c.slot == s then
								changing = true
							end
						end
					end
					local b: TextButton = new("TextButton", {
						Name = "Slot_" .. s,
						LayoutOrder = k,
						Text = Components.plain(I[s]),
						TextSize = 28,
						FontFace = Tokens.font.number,
						TextColor3 = if item then C.inkLight else C.ch45,
						AutoButtonColor = false,
						Size = UDim2.fromOffset(66, 66),
						BackgroundColor3 = C.secondary,
						[CHILDREN] = {
							Components.corner(14),
							Components.stroke(
								if changing
									then C.okGreen
									elseif item then ChestCommon.rarityColor(item.rarity)
									else C.secondaryRim,
								3
							),
						},
						Parent = eqRow,
					})
					if Art.put(b, Art.equip(item), { inset = 6 }) then
						b.Text = "" -- 付けている品の絵（D-254）
					end
					b.Activated:Connect(function()
						if not equipMode and pickSlot == nil and pickAdv == nil and not dragging() then
							api.open("EquipSelect", { uid = adv.uid, slot = s })
						end
					end)
				end
			end
		end

		markSize = sizes

		-- 控えの列（常に出す：D-265 ④）
		local reserve: Frame = new("Frame", {
			Name = "Reserve",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 40, 1, -12),
			Size = UDim2.fromOffset(RESERVE_W, 118),
			BackgroundColor3 = C.ch10,
			[CHILDREN] = { Components.corner(12), Components.padding(30, 12, 8, 12) },
			Parent = body,
		})
		local ribbon = Components.text({ text = "Reserve", size = 21, color = C.bronzeHi, font = Tokens.font.display })
		ribbon.AnchorPoint = Vector2.new(0, 1)
		ribbon.Position = UDim2.fromOffset(4, -4)
		ribbon.Parent = reserve
		if newcomer ~= nil then
			-- 初めての人がいるときだけ1行の案内（D-264 ④）
			local hint = Components.text({
				text = Words.hint.dragReserve,
				size = 21,
				color = C.inkWhite,
				font = Tokens.font.body,
				stroke = true,
			})
			hint.AnchorPoint = Vector2.new(0, 1)
			hint.Position = UDim2.fromOffset(110, -4)
			hint.Parent = reserve
		end
		local scroll: ScrollingFrame = new("ScrollingFrame", {
			Name = "List",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 4,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ScrollingDirection = Enum.ScrollingDirection.X,
			[CHILDREN] = {
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 8),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = reserve,
		})
		-- 隊列を先に選んでいるときだけ、左端に「外す」
		if pickSlot ~= nil then
			local empty: TextButton = new("TextButton", {
				Name = "LeaveEmpty",
				LayoutOrder = 0,
				Text = "○",
				TextSize = 28,
				FontFace = Tokens.font.number,
				TextColor3 = C.inkLight,
				AutoButtonColor = false,
				Size = UDim2.fromOffset(66, 66),
				BackgroundColor3 = C.ch13,
				[CHILDREN] = { Components.corner(12), Components.stroke(C.ch28, 2) },
				Parent = scroll,
			})
			empty.Activated:Connect(function()
				if not busy and pickSlot then
					local s = pickSlot
					pickSlot = nil
					undo = nil
					send({ type = "SetPartySlot", partyIndex = partyIndex, slot = s, adventurerUid = Party.EMPTY })
					render()
				end
			end)
		end
		local others = {}
		for uid, a in view.adventurers do
			local p = Party.find(view, uid)
			if p ~= partyIndex then
				table.insert(others, { uid = uid, adv = a, p = p })
			end
		end
		table.sort(others, function(x, y)
			if (x.uid == newcomer) ~= (y.uid == newcomer) then
				return x.uid == newcomer -- 新しく来た人は先頭
			end
			if (x.p == nil) ~= (y.p == nil) then
				return x.p == nil
			end
			if x.adv.level ~= y.adv.level then
				return x.adv.level > y.adv.level
			end
			return x.uid < y.uid
		end)
		for i, o in others do
			local free = o.p == nil
			local lit = o.uid == newcomer or o.uid == pickAdv
			local rc: TextButton = new("TextButton", {
				Name = "Adv_" .. o.uid,
				LayoutOrder = i,
				Text = "",
				AutoButtonColor = false,
				Active = free,
				Size = UDim2.fromOffset(176, 76),
				BackgroundColor3 = if free then C.ch28 else C.ch13,
				[CHILDREN] = {
					Components.corner(12),
					Components.stroke(if lit then C.selAmber else C.ch28, if lit then 4 else 2),
				},
				Parent = scroll,
			})
			reserveCards[o.uid] = rc
			local face: Frame = new("Frame", {
				Name = "Face",
				Position = UDim2.fromOffset(5, 5),
				Size = UDim2.fromOffset(66, 66),
				BackgroundColor3 = C.ch13,
				[CHILDREN] = { Components.corner(10) },
				Parent = rc,
			})
			Portrait.fill(face, o.adv.appearanceId, not free)
			local job = master.jobs[o.adv.jobId]
			local nm = Components.text({
				text = o.adv.name,
				size = 21,
				color = C.inkLight,
				font = Tokens.font.display,
				xAlign = Enum.TextXAlignment.Left,
			})
			nm.AutomaticSize = Enum.AutomaticSize.None
			nm.Position = UDim2.fromOffset(78, 8)
			nm.Size = UDim2.fromOffset(94, 26)
			nm.TextTruncate = Enum.TextTruncate.AtEnd
			nm.TextTransparency = if free then 0 else 0.5
			nm.Parent = rc
			local sub = Components.text({
				text = "",
				size = 21,
				color = C.inkLight,
				font = Tokens.font.number,
				xAlign = Enum.TextXAlignment.Left,
			})
			sub.Position = UDim2.fromOffset(78, 40)
			Components.setParts(
				sub,
				if free
					then {
						if job and job.attackType == "magic" then "@job_magic" else "@job_physical",
						"Lv" .. o.adv.level,
					}
					else { I.party, tostring(o.p) } -- ほかのパーティの人は番号（入れられない）
			)
			sub.TextTransparency = if free then 0 else 0.5
			sub.Parent = rc
			if o.uid == newcomer then
				new("TextLabel", {
					Name = "New",
					Text = "NEW",
					TextSize = 18,
					FontFace = Tokens.font.number,
					TextColor3 = C.inkDark,
					BackgroundColor3 = C.okGreen,
					Position = UDim2.fromOffset(-6, -8),
					Size = UDim2.fromOffset(52, 24),
					ZIndex = 5,
					[CHILDREN] = { Components.corner(12) },
					Parent = rc,
				})
				if pickAdv == nil then
					table.insert(stops, Motion.pulse(rc))
				end
			elseif free and pickSlot ~= nil then
				table.insert(stops, Motion.pulse(rc)) -- 隊列を選んでいる：入れられる控えが脈打つ
			end
			if free then
				rc.InputBegan:Connect(function(input)
					local t = input.UserInputType
					if
						(t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch)
						and not busy
						and not equipMode
					then
						drag = { uid = o.uid, start = Vector2.new(input.Position.X, input.Position.Y), moved = false }
					end
				end)
				rc.Activated:Connect(function()
					if busy or equipMode or dragging() then
						return
					end
					if pickSlot ~= nil then
						local s = pickSlot
						pickSlot = nil
						swapIn(s, o.uid)
						return
					end
					-- 空きがあればそこへ入れ、なければこの人を選んで隊列を待つ
					local emptySlot = table.find(party.slots, Party.EMPTY)
					if emptySlot then
						swapIn(emptySlot, o.uid)
					else
						pickAdv = if pickAdv == o.uid then nil else o.uid
						render()
					end
				end)
			end
		end

		-- 右下：Undo（茶）・自動装備（茶）・行き先（金）。自動装備の差を見せている間は Cancel（茶）と Equip（金）
		local actions = Screen.actionRow(body)
		if equipMode then
			local cancel = Components.button({
				kind = "brown",
				width = 180,
				height = 66,
				label = Words.cancel,
				name = "Cancel",
				glyph = "Y",
				onClick = function()
					equipMode = false
					render()
				end,
			})
			cancel.LayoutOrder = 1
			cancel.Parent = actions
			local equip = Components.button({
				kind = "gold",
				width = 260,
				icon = "@slot_weapon", -- Equip＝武器の枠（D-256）
				label = Words.equip,
				name = "Equip",
				glyph = "A",
				onClick = function()
					if busy then
						return
					end
					undo = nil
					send({ type = "AutoEquip", partyIndex = partyIndex })
					equipMode = false
					render()
				end,
			})
			equip.LayoutOrder = 2
			equip.Parent = actions
		else
			if undo ~= nil then
				local u = Components.button({
					kind = "brown",
					width = 140,
					height = 66,
					icon = "@back",
					label = Words.undo,
					name = "Undo",
					glyph = "Y",
					onClick = doUndo,
				})
				u.LayoutOrder = 0
				u.Parent = actions
			end
			local auto = Components.button({
				kind = if #plan > 0 then "brown" else "disabled",
				width = 220,
				height = 66,
				icon = AUTO_ICON,
				label = Words.autoEquip,
				name = "AutoEquip",
				glyph = "X",
				reason = Words.reason.noBetterGear, -- 付け替えがなくても押せて理由を出す（D-266 ④）
				onClick = function()
					if #plan > 0 then
						equipMode = true
						render()
					end
				end,
			})
			auto.LayoutOrder = 1
			auto.Parent = actions
			if #plan > 0 then
				-- より良い装備があるときは緑の ▲（D-216）
				new("TextLabel", {
					Name = "Better",
					Text = "▲",
					TextSize = 18,
					FontFace = Tokens.font.number,
					TextColor3 = C.inkDark,
					BackgroundColor3 = C.okGreen,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(4, 4),
					Size = UDim2.fromOffset(30, 30),
					ZIndex = 5,
					[CHILDREN] = { Components.corner(15) },
					Parent = auto,
				})
			end
			local dest = Components.button({
				kind = "gold",
				width = 260,
				icon = "▶",
				label = Words.go,
				name = "Go",
				glyph = "A",
				onClick = function()
					-- 行けるダンジョンの一覧の窓（パーティの面の Go と同じ：D-282）。選ぶとこのパーティで出発する
					api.open("DungeonPick", { partyIndex = partyIndex })
				end,
			})
			dest.LayoutOrder = 2
			dest.Parent = actions
		end
	end

	render()
	local conn = Session.changed:connect(function()
		if not busy and drag == nil then
			render()
		end
	end)
	return {
		frame = frame,
		scrim = 1,
		destroy = function()
			conn.disconnect()
			for _, c in dragConns do
				c:Disconnect()
			end
			for _, stop in stops do
				stop()
			end
		end,
	}
end

Nav.register("PartyMenu", build)

return {}
