--!strict
-- ダンジョンの面（S-15 の最小版。M8-2）。マップのダンジョンを触って開く（D-113）。
-- M8-2 では「選んでいる待機中のパーティをここへ出発させる」までを置く。攻略ヒント・適性のあるキャラ上位4人は M8-6。

local Components = require("../ui/Components")
local Create = require("../ui/Create")
local HubState = require("../hub/HubState")
local Nav = require("../ui/Nav")
local Root = require("../ui/Root")
local Session = require("../Session")
local Tokens = require("../ui/Tokens")
local master = require("../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local PANEL_W = 420
local PANEL_H = 300

-- 出発させるパーティ：選んでいるパーティが待機中ならそれ、なければ番号の小さい待機中のパーティ
local function pickParty(view: any): number?
	local sel = HubState.selected
	if sel and HubState.status(view, sel).state == "waiting" then
		return sel
	end
	for _, p in view.parties or {} do
		local hasMember = false
		for _, uid in p.slots do
			if uid ~= "" then
				hasMember = true
			end
		end
		if hasMember and HubState.status(view, p.index).state == "waiting" then
			return p.index
		end
	end
	return nil
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
	local x = (Root.frame.width - PANEL_W) / 2
	local panel, content = Components.panel({
		size = UDim2.fromOffset(PANEL_W, PANEL_H),
		position = UDim2.fromOffset(x, band + 80),
		title = if d then d.name else dungeonId,
	})
	panel.Parent = frame
	local close = Components.closeButton(api.close)
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.fromOffset(x + PANEL_W - 12, band + 80 + 12)
	close.Parent = frame

	local view = Session.view
	local unlocked = view and view.unlockedDungeons and view.unlockedDungeons[dungeonId] == true
	-- フロアの数（仮の印：フロアの数だけ丸）
	local floors: Frame = new("Frame", {
		Name = "Floors",
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		[CHILDREN] = {
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
		},
		Parent = content,
	})
	for _ = 1, (d and d.floors or 0) do
		new("Frame", {
			Size = UDim2.fromOffset(20, 20),
			BackgroundColor3 = C.ch50,
			[CHILDREN] = { Components.corner(10), Components.stroke(C.ch16, 2) },
			Parent = floors,
		})
	end
	local partyIndex = if view and unlocked then pickParty(view) else nil
	local go = Components.button({
		kind = if partyIndex then "gold" else "disabled",
		width = 200,
		icon = "▶",
		glyph = "A",
		onClick = function()
			if partyIndex then
				local r = Session.send({ type = "Dispatch", partyIndex = partyIndex, dungeonId = dungeonId })
				if r and r.ok then
					HubState.selected = partyIndex
					HubState.following = true
					HubState.lastDungeon[partyIndex] = dungeonId
					api.close()
				end
			end
		end,
	})
	go.AnchorPoint = Vector2.new(1, 1)
	go.Position = UDim2.fromScale(1, 1)
	go.Parent = content
	if partyIndex then
		-- 出発するパーティの番号（馬車と同じ札）
		local tag = Components.text({
			text = tostring(partyIndex),
			size = 30,
			color = C.inkLight,
			font = Tokens.font.display,
		})
		local chip: Frame = new("Frame", {
			Name = "Party",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -10),
			Size = UDim2.fromOffset(66, 50),
			BackgroundColor3 = C.ch28,
			[CHILDREN] = { Components.corner(10), Components.stroke(C.ch05, 2) },
			Parent = content,
		})
		tag.AutomaticSize = Enum.AutomaticSize.None
		tag.Size = UDim2.fromScale(1, 1)
		tag.Parent = chip
	end
	return { frame = frame }
end

Nav.register("DungeonPanel", build)

return {}
