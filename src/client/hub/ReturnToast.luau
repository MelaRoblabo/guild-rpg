--!strict
-- 帰還のトースト（11章 §5・D-116・D-128・D-162・D-214・D-236 ④）。メイン画面の帯のすぐ下の真ん中に暗い木のカプセル。
--   - オンライン中の帰還（ExpeditionReturned、留守番でないもの）で出す。少しの間に帰ったパーティは1つにまとめる（D-128）。
--   - 中身：馬車（帰る向き）＋パーティの番号（まとめは重ねる）＋宝箱の数＋XP の札（休息ボーナス＝月、日替わり＝太陽。
--     両方なら掛け合わせた倍率：06章 §14・§16）。右の端の Go＝同じ所へもう一度（待機のパーティだけ）。
--   - トーストを触るとそのパーティを選ぶ（D-116）。画面を重ねている間（開封・面接・転生など）と、設定でオフのときは出さない。

local Game = require("@game/ReplicatedStorage/Core/Game")
local Components = require("../ui/Components")
local Create = require("../ui/Create")
local HubState = require("./HubState")
local Nav = require("../ui/Nav")
local Root = require("../ui/Root")
local Session = require("../Session")
local Tokens = require("../ui/Tokens")
local master = require("../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

-- 見せる時間とまとめる間（D-238 ③）
local SHOW_SECONDS = master.K.returnToastSeconds
local GROUP_SECONDS = master.K.returnToastGroupSeconds

local ReturnToast = {}

local pending: { any } = {}
local current: Frame? = nil
local token = 0

local function xpMult(e: any): number
	local m = 1
	if e.restBonus then
		m *= master.K.restBonusExpMult
	end
	local trait = if e.dailyTraitId then master.dailyTraits[e.dailyTraitId] else nil
	if trait and trait.effect == "expMult" then
		m *= trait.value
	end
	return m
end

local function show(group: { any })
	if current then
		current:Destroy()
		current = nil
	end
	token += 1
	local my = token
	local parties, chests, rest, daily, mult = {}, 0, false, false, 1
	for _, e in group do
		table.insert(parties, e.partyIndex)
		chests += e.chests or 0
		rest = rest or e.restBonus == true
		local trait = if e.dailyTraitId then master.dailyTraits[e.dailyTraitId] else nil
		daily = daily or (trait ~= nil and trait.effect == "expMult")
		mult = math.max(mult, xpMult(e))
	end
	table.sort(parties)
	local band = Root.bandBottom()
	local toast: Frame = new("Frame", {
		Name = "ReturnToast",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, band + 12),
		Size = UDim2.fromOffset(600, 80),
		BackgroundColor3 = C.ch10,
		ZIndex = 50,
		[CHILDREN] = { Components.corner(40), Components.stroke(C.bronze, 3) },
		Parent = Root.canvas,
	})
	current = toast
	local tap: TextButton = new("TextButton", {
		Name = "Select",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 7),
		Size = UDim2.new(1, -96, 1, -14),
		ZIndex = 51,
		[CHILDREN] = {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 14),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = toast,
	})
	local function label(order: number, text: string, size: number, color: Color3)
		local t = Components.text({ text = text, size = size, color = color, font = Tokens.font.number })
		t.LayoutOrder = order
		t.ZIndex = 52
		t.Parent = tap
	end
	local nums = {}
	for _, p in parties do
		table.insert(nums, tostring(p))
	end
	label(1, "◀ " .. table.concat(nums, " "), 28, C.inkLight)
	label(2, "▣ +" .. chests, 30, C.numHi)
	if rest or daily then
		label(3, (if rest then "☾" else "") .. (if daily then "☀" else "") .. " XP ×" .. mult, 23, C.inkLight)
	end
	tap.Activated:Connect(function()
		HubState.selected = parties[1]
		HubState.following = true
		toast:Destroy()
		current = nil
	end)
	-- 右の端：同じ所へもう一度（待機のパーティだけ）
	local go: TextButton = new("TextButton", {
		Name = "Go",
		Text = "▶↺",
		TextSize = 25,
		FontFace = Tokens.font.number,
		TextColor3 = C.inkLight,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -7, 0.5, 0),
		Size = UDim2.fromOffset(66, 66),
		BackgroundColor3 = C.secondary,
		ZIndex = 52,
		[CHILDREN] = { Components.corner(33), Components.stroke(C.secondaryRim, 3) },
		Parent = toast,
	})
	go.Activated:Connect(function()
		local view = Session.view
		if view then
			for _, e in group do
				if HubState.status(view, e.partyIndex).state == "waiting" then
					Session.send({ type = "Dispatch", partyIndex = e.partyIndex, dungeonId = e.dungeonId })
				end
			end
		end
		toast:Destroy()
		current = nil
	end)
	task.delay(SHOW_SECONDS, function()
		if token == my and toast.Parent then
			toast:Destroy()
			current = nil
		end
	end)
end

function ReturnToast.mount()
	Session.events:connect(function(reason: string, events: { any })
		if reason == "load" then
			return -- ログインの帰還はまとめの画面で見せる（S-01）
		end
		for _, e in events do
			if e.type == "ExpeditionReturned" and not e.offline then
				table.insert(pending, e)
			end
		end
		if #pending == 0 then
			return
		end
		task.delay(GROUP_SECONDS, function()
			if #pending == 0 then
				return
			end
			local group = pending
			pending = {}
			local view = Session.view
			if Nav.depth() > 0 or view == nil then
				return
			end
			if not Game.query.preferences(view, master).returnToast then
				return
			end
			show(group)
		end)
	end)
end

return ReturnToast
