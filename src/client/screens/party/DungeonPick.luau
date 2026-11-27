--!strict
-- 行き先の一覧（D-282）。パーティの面（待機）の ▶ Go で開く窓。今このパーティが行けるダンジョン（解放済み）を並べ、
--   選んだ所へ出発する（D-244 ② の「一番浅いダンジョンへ」を置き換え）。
--   - 位置・形はパーティの面にそろえる（左端 x196・幅560・羊皮紙・題の札・× は面の右上の角）。題は Destination。
--   - 行：左に中の背景の絵（Art.background）、ローマ数字＋名前（nameEn）、片道の移動時間（「One way」の語つき。
--     06章 §4 の式を S-15 と同じ Hint.forParty で出す）、右に ▶ Go。
--   - 金の Go は前回の行き先（D-228）の行だけ。ほかの行は茶（金はメイン1つ：D-222）。前回がなく行き先が1つなら、その行を金に。
--   - 初回の誘導（D-244 ①）：パーティの面の Go に続けて、金の行の Go を光らせる。
--   - 出発したら面を全部閉じ、カメラは出た馬車を追う（パーティの面の Go と同じ）。
--   - マップイベント（D-309）：今出ているレイドボス・レアダンジョン・旅の商人に、このパーティが行けるなら一番上に1行。
--     絵は種類ごとの絵（Art.eventBackground）、名前は Raid Boss／Rare Dungeon／Merchant、時間は締め切りまで（Leaves in）。
--     Go＝DispatchEvent。締め切ったら（3分間が過ぎた・出発済み・商人に別のパーティを送った）一覧から消す。

local AutoEquip = require("@game/ReplicatedStorage/Core/AutoEquip")
local ExclusiveGift = require("@game/ReplicatedStorage/Core/ExclusiveGift")
local Formulas = require("@game/ReplicatedStorage/Core/Formulas")
local Game = require("@game/ReplicatedStorage/Core/Game")
local Party = require("@game/ReplicatedStorage/Core/Party")
local Art = require("../../ui/Art")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Guide = require("../../hub/Guide")
local Hint = require("../../party/Hint")
local HubState = require("../../hub/HubState")
local Nav = require("../../ui/Nav")
local Root = require("../../ui/Root")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local Words = require("../../ui/Words")
local WarehouseCommon = require("../warehouse/WarehouseCommon")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local PANEL_X = 196
local PANEL_W = 560 -- 名前と時間が入る幅（パーティの面より広い。左端はそろえる）
local ROW_H = 104
local ROW_GAP = 10
local ART_W = 140 -- 行の左の絵の幅
local TEXT_X = ART_W + 16 -- 名前と時間の左端
local MAX_ROWS = 4 -- これより多いときは一覧を縦に送る
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

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- 今行けるダンジョン（解放済み。浅い順）
local EVENT_WORD = { rareDungeon = "rareDungeon", raid = "raidBoss", merchant = "merchant" } -- Words の鍵
local EVENT_RIM = { rareDungeon = "specialPurple", raid = "warnDark", merchant = "coinGold" } -- 行の縁の色（Tokens.color の鍵）

-- 今出ていて、このパーティが行けるマップイベント（D-309）。{ kind, slot, closesIn } か nil
local function openEvent(view: any, partyIndex: number): any?
	local cur = Game.query.mapEvent(Session.now(), master, view).current
	if cur == nil or not cur.open or EVENT_WORD[cur.kind] == nil then
		return nil
	end
	local slot = cur.eventSlot
	if cur.kind == "rareDungeon" then
		if table.find(Game.query.rareDungeon(view, slot, master).joined, partyIndex) then
			return nil
		end
	elseif cur.kind == "raid" then
		local r = view.raid
		if r and r.eventSlot == slot and table.find(r.parties or {}, partyIndex) then
			return nil
		end
	else
		-- 1つの商人に1パーティだけ（D-274）。もう送っていれば出さない
		local waiting = false
		for _, p in Game.query.merchantPresence(view, Session.now(), master) do
			if p.eventSlot == slot and p.phase == "open" then
				waiting = true
			end
		end
		if not waiting then
			return nil
		end
	end
	return { kind = cur.kind, slot = slot, closesIn = cur.closesIn or 0 }
end

local function openDungeons(view: any): { any }
	local out = {}
	for _, d in master.dungeonList do
		if view.unlockedDungeons and view.unlockedDungeons[d.id] then
			table.insert(out, d)
		end
	end
	return out
end

local function build(params: any?, api: Nav.Api): Nav.Built
	local partyIndex = (params :: any).partyIndex :: number
	local band = Root.bandBottom()
	local frame: Frame = new("Frame", {
		Name = "DungeonPick",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local busy = false
	local closed = false

	local lastKey = ""

	local function render()
		local view = Session.view
		if view == nil or HubState.status(view, partyIndex).state ~= "waiting" then
			body:ClearAllChildren()
			lastKey = ""
			return
		end
		local list = openDungeons(view)
		local last = nil
		local slots = ""
		for _, p in view.parties or {} do
			if p.index == partyIndex then
				last = p.lastDungeonId
				slots = table.concat(p.slots, ",")
			end
		end
		-- 行き先・前回の行き先・メンバーが変わったときだけ作り直す（送った位置と絵の読み込みを保つ）
		local ids = {}
		for _, d in list do
			table.insert(ids, d.id)
		end
		local ev = openEvent(view, partyIndex)
		local key = table.concat(ids, ",")
			.. "|"
			.. tostring(last)
			.. "|"
			.. slots
			.. "|"
			.. (if ev then ev.kind .. ev.slot else "")
		if key == lastKey then
			return
		end
		lastKey = key
		body:ClearAllChildren()
		local mainId = nil -- 金の Go の行（D-228 の前回の行き先。なければ行き先が1つのときだけ）
		for _, d in list do
			if d.id == last then
				mainId = d.id
			end
		end
		if mainId == nil and #list == 1 then
			mainId = list[1].id
		end

		local shown = math.min(#list + (if ev then 1 else 0), MAX_ROWS)
		local listH = shown * ROW_H + math.max(shown - 1, 0) * ROW_GAP
		local panel, content = Components.panel({
			size = UDim2.fromOffset(PANEL_W, Tokens.spacing.panelPadPlaque + listH + 14 + 2 * Tokens.spacing.frame),
			position = UDim2.fromOffset(PANEL_X, band + 40),
			title = Words.destination,
		})
		panel.Parent = body
		local close = Components.closeButton(api.close)
		close.AnchorPoint = Vector2.new(0.5, 0.5)
		close.Position = UDim2.new(1, -12, 0, 12)
		close.ZIndex = 20
		close.Parent = panel

		local scroll: ScrollingFrame = new("ScrollingFrame", {
			Name = "List",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = C.ch45,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ZIndex = content.ZIndex,
			[CHILDREN] = {
				new("UIListLayout", {
					Padding = UDim.new(0, ROW_GAP),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = content,
		})

		local mainGo: Frame? = nil
		-- マップイベントの行（D-309）：一番上
		if ev then
			local r: Frame = new("Frame", {
				Name = "Row_event",
				LayoutOrder = 0,
				Size = UDim2.new(1, -8, 0, ROW_H),
				BackgroundColor3 = C.ch75,
				[CHILDREN] = {
					Components.corner(8),
					Components.stroke((C :: any)[EVENT_RIM[ev.kind]] or C.bronze, 3),
				},
				Parent = scroll,
			})
			local art: Frame = new("Frame", {
				Name = "Art",
				Position = UDim2.fromOffset(8, 8),
				Size = UDim2.fromOffset(ART_W, ROW_H - 16),
				BackgroundColor3 = C.ch13,
				ClipsDescendants = true,
				[CHILDREN] = { Components.corner(6) },
				Parent = r,
			})
			Art.put(art, Art.eventBackground(ev.kind), { scaleType = Enum.ScaleType.Crop })
			local name = Components.text({
				text = (Words :: any)[EVENT_WORD[ev.kind]],
				size = Tokens.text.label,
				color = C.inkDark,
				font = Tokens.font.display,
				xAlign = Enum.TextXAlignment.Left,
			})
			name.AutomaticSize = Enum.AutomaticSize.None
			name.Size = UDim2.new(1, -(TEXT_X + 122), 0, 30)
			name.Position = UDim2.fromOffset(TEXT_X, 12)
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.Parent = r
			-- 締め切りまで（下の時計の処理で毎秒書き換える）
			local timePill = WarehouseCommon.pill("@time", Words.leavesIn .. " " .. clock(ev.closesIn), 21)
			timePill.Name = "EventTimer"
			timePill.AnchorPoint = Vector2.new(0, 1)
			timePill.Position = UDim2.new(0, TEXT_X, 1, -12)
			timePill.Parent = r
			local go = Components.button({
				kind = "brown",
				width = 100,
				height = 66,
				icon = "▶",
				label = Words.go,
				name = "Go",
				onClick = function()
					if busy then
						return
					end
					busy = true
					local res =
						Session.sendAndWait({ type = "DispatchEvent", partyIndex = partyIndex, eventSlot = ev.slot })
					busy = false
					if res and res.ok then
						HubState.selected = partyIndex
						HubState.following = true -- 出た馬車をカメラが追う
						api.home()
					else
						lastKey = ""
						render()
					end
				end,
			})
			go.AnchorPoint = Vector2.new(1, 0.5)
			go.Position = UDim2.new(1, -10, 0.5, 0)
			go.Parent = r
		end
		for i, d in list do
			local isMain = d.id == mainId
			local r: Frame = new("Frame", {
				Name = "Row_" .. d.id,
				LayoutOrder = i,
				Size = UDim2.new(1, -8, 0, ROW_H),
				BackgroundColor3 = C.ch75,
				[CHILDREN] = {
					Components.corner(8),
					Components.stroke(if isMain then C.bronze else C.ch50, 2),
				},
				Parent = scroll,
			})
			-- 中の背景の絵（左）
			local art: Frame = new("Frame", {
				Name = "Art",
				Position = UDim2.fromOffset(8, 8),
				Size = UDim2.fromOffset(ART_W, ROW_H - 16),
				BackgroundColor3 = C.ch13,
				ClipsDescendants = true,
				[CHILDREN] = { Components.corner(6) },
				Parent = r,
			})
			if Art.put(art, Art.background(d.id), { scaleType = Enum.ScaleType.Crop }) == nil then
				local t = Components.text({ text = ROMAN[d.tier] or tostring(d.tier), size = 30, color = C.ch45 })
				t.AnchorPoint = Vector2.new(0.5, 0.5)
				t.Position = UDim2.fromScale(0.5, 0.5)
				t.Parent = art
			end
			-- 名前（ローマ数字＋英語の名前）
			local name = Components.text({
				text = (ROMAN[d.tier] or tostring(d.tier)) .. "  " .. d.nameEn,
				size = Tokens.text.label,
				color = C.inkDark,
				font = Tokens.font.display,
				xAlign = Enum.TextXAlignment.Left,
			})
			name.AutomaticSize = Enum.AutomaticSize.None
			name.Size = UDim2.new(1, -(TEXT_X + 122), 0, 30)
			name.Position = UDim2.fromOffset(TEXT_X, 12)
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.Parent = r
			-- 片道の移動時間（06章 §4。数字だけでは往復か片道か分からないので語を添える：D-264）
			local _, travel = Hint.forParty(view, partyIndex, d, master, deps)
			local timePill = WarehouseCommon.pill("@time", Words.oneWay .. " " .. clock(travel), 21)
			timePill.AnchorPoint = Vector2.new(0, 1)
			timePill.Position = UDim2.new(0, TEXT_X, 1, -12)
			timePill.Parent = r
			-- ▶ Go
			local go = Components.button({
				kind = if isMain then "gold" else "brown",
				width = 100,
				height = 66,
				icon = "▶",
				label = Words.go,
				name = "Go",
				glyph = if isMain then "A" else nil,
				onClick = function()
					if busy then
						return
					end
					busy = true
					local res = Session.sendAndWait({ type = "Dispatch", partyIndex = partyIndex, dungeonId = d.id })
					busy = false
					if res and res.ok then
						HubState.selected = partyIndex
						HubState.following = true -- 出た馬車をカメラが追う
						api.home()
					else
						lastKey = ""
						render()
					end
				end,
			})
			go.AnchorPoint = Vector2.new(1, 0.5)
			go.Position = UDim2.new(1, -10, 0.5, 0)
			go.Parent = r
			if isMain then
				mainGo = go
			end
		end
		-- 初回の誘導（D-244 ①）：パーティの面の Go に続けて、ここでも金の Go を光らせる
		local mg = mainGo
		if mg then
			Guide.mark(mg, Guide.is("go"), 18)
		end
	end

	render()
	-- マップイベントの行の時計（D-309）：毎秒書き換え、締め切ったら一覧を作り直して消す
	task.spawn(function()
		while not closed do
			task.wait(0.25)
			if closed or busy then
				continue
			end
			render() -- 出ている・行けるが変わったときだけ作り直す（key を比べる）
			local view = Session.view
			local ev = if view then openEvent(view, partyIndex) else nil
			local pill = body:FindFirstChild("EventTimer", true)
			if ev and pill then
				for _, c in pill:GetDescendants() do
					if c:IsA("TextLabel") and string.sub(c.Text, 1, #Words.leavesIn) == Words.leavesIn then
						c.Text = Words.leavesIn .. " " .. clock(ev.closesIn)
						c.TextColor3 = if ev.closesIn <= master.K.mapEventEndingSeconds then C.warn else C.inkLight
					end
				end
			end
		end
	end)
	local conn = Session.changed:connect(function(view: any)
		if busy or closed then
			return
		end
		-- 待機でなくなった（ほかの画面から出発した・自動で出た）ら、この窓だけ閉じる
		if view and HubState.status(view, partyIndex).state ~= "waiting" then
			closed = true
			api.close()
			return
		end
		render()
	end)
	return {
		frame = frame,
		scrim = 0.5, -- パーティの面と同じ（D-225 ③）
		passThrough = true, -- 開いたままでも 3D マップのカメラを動かせる（D-270）
		destroy = function()
			closed = true
			conn.disconnect()
		end,
	}
end

Nav.register("DungeonPick", build)

return {}
