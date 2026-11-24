--!strict
-- パーティの面（S-10 の中。D-212〜D-216・D-225 ③）。一覧の行か馬車を触って開く。
--   - 羊皮紙の面、題の札＝パーティの番号、× は面の右上の角、後ろの暗幕は 50%（D-225 ③）。
--   - 待機：同じ所へ再出発（Go、金）と Menu（茶。S-12 は M8-6）。探索中：フロアの進みと自動再派遣のスイッチだけ（D-214 ⑥）。
--   - 移動中・帰還中：残り時間。メンバーの HP は探索中だけ（戦闘不能は暗くする：D-214 ⑤）。

local Components = require("../ui/Components")
local Create = require("../ui/Create")
local HubState = require("../hub/HubState")
local Nav = require("../ui/Nav")
local Root = require("../ui/Root")
local Session = require("../Session")
local Tokens = require("../ui/Tokens")
local master = require("../Master")

local C = Tokens.color
local I = Components.icon
local new = Create.new
local CHILDREN = Create.Children

local PANEL_W = 420
local PANEL_H = 470

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function memberRow(adv: any, hp: number?, maxHp: number?): Frame
	local row: Frame = new("Frame", {
		Name = "Member",
		Size = UDim2.new(1, 0, 0, 56),
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
			BackgroundColor3 = if down then C.warn else C.barFill,
			[CHILDREN] = { Components.corner(6) },
			Parent = track,
		})
	end
	return row
end

local function build(params: any?, api: Nav.Api): Nav.Built
	local partyIndex = (params :: any).partyIndex :: number
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
			.. tostring(HubState.lastDungeon[partyIndex])
		if s.hp then
			key ..= ":" .. table.concat(s.hp, ",")
		end
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
				text = (if d then d.name else s.dungeonId),
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
				local hp = if s.state == "exploring" and s.hp then s.hp[memberIdx] else nil
				local row = memberRow(view.adventurers[uid], hp, maxHp[memberIdx])
				order += 1
				row.LayoutOrder = order
				row.Parent = body
			end
		end
		if s.state == "waiting" then
			local menu = Components.button({ kind = "brown", width = 120, height = 66, icon = "▤", glyph = "X" })
			menu.LayoutOrder = 1
			menu.Parent = actions
			local dest = HubState.lastDungeon[partyIndex]
			local go = Components.button({
				kind = if dest then "gold" else "disabled",
				width = 200,
				icon = "▶",
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
		else
			-- 探索中：フロアの進み（丸）。移動中・帰還中：残り時間
			if s.state == "exploring" and s.floors then
				local dots: Frame = new("Frame", {
					Name = "Floors",
					LayoutOrder = order + 1,
					Size = UDim2.new(1, 0, 0, 24),
					BackgroundTransparency = 1,
					[CHILDREN] = {
						new("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							Padding = UDim.new(0, 6),
						}),
					},
					Parent = body,
				})
				for f = 1, s.floors do
					new("Frame", {
						Size = UDim2.fromOffset(20, 20),
						BackgroundColor3 = if f < (s.floorIndex or 0)
							then C.barFill
							elseif f == s.floorIndex then C.ctaGold
							else C.ch50,
						[CHILDREN] = { Components.corner(10), Components.stroke(C.ch16, 2) },
						Parent = dots,
					})
				end
			end
			-- 自動再派遣のスイッチ（D-125・D-214 ⑥）
			local on = party.autoRepeat ~= nil
			local toggle = Components.button({
				kind = if on then "gold" else "brown",
				width = 120,
				height = 66,
				icon = I.reroll,
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

	-- 残り時間の札（移動中・帰還中）は毎秒更新
	local remain = Components.text({ text = "", size = 25, color = C.inkDark, font = Tokens.font.number })
	remain.AnchorPoint = Vector2.new(0, 1)
	remain.Position = UDim2.new(0, 0, 1, -20)
	remain.Parent = content
	local alive = true
	task.spawn(function()
		while alive do
			local view = Session.view
			if view then
				local s = HubState.status(view, partyIndex)
				remain.Text = if (s.state == "moving" or s.state == "returning") and s.returnAt
					then clock(s.returnAt - Session.now())
					else ""
				render(view)
			end
			task.wait(0.5)
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
