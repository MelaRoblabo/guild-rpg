--!strict
-- 帰還のトースト（11章 §5・D-116・D-128・D-214・D-236 ④・D-281）。メイン画面の帯のすぐ下、左の一覧の右に暗い木のカプセル（右上のボタンに重ねない）。
--   - オンライン中の帰還（ExpeditionReturned、留守番でないもの）で出す。少しの間に帰ったパーティは1つにまとめる（D-128）。
--   - ログインでは、まとめ（S-01）を閉じたあと、留守の間に帰ったパーティごとに1つずつ出す（playLogin：D-281）。
--     触るか時間がたつと次のパーティへ。全部出し終えたらカットインへ（hub/LoginSequence）。
--   - 中身：馬車（帰る向き）＋パーティの番号（まとめは重ねる）＋宝箱の数（0 からカウントアップ：D-269 ⑤）＋
--     XP の札（日替わり＝太陽と倍率：06章 §16。留守番の探索は経験値なし：D-280。休息ボーナスは廃止：D-280）。
--     右の端の Go＝同じ所へもう一度（待機のパーティだけ）。
--   - レベルが上がった人がいれば「Lv▲ 人数」の札を足し、その人をパーティの面で一度光らせる（D-246 ④）。
--   - トーストを触るとそのパーティを選ぶ（D-116）。画面を重ねている間（開封・面接・転生など）と、設定でオフのときは出さない。

local Game = require("@game/ReplicatedStorage/Core/Game")
local Components = require("../ui/Components")
local Create = require("../ui/Create")
local HubState = require("./HubState")
local LevelUpMarks = require("./LevelUpMarks")
local Motion = require("../ui/Motion")
local Nav = require("../ui/Nav")
local Root = require("../ui/Root")
local Session = require("../Session")
local Tokens = require("../ui/Tokens")
local Words = require("../ui/Words")
local master = require("../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

-- 見せる時間とまとめる間（D-238 ③）
local SHOW_SECONDS = master.K.returnToastSeconds
local GROUP_SECONDS = master.K.returnToastGroupSeconds

local ReturnToast = {}

local pending: { any } = {}
local pendingLevelUps: { [string]: boolean } = {} -- まとめる間にレベルが上がった人（D-246 ④）
local current: Frame? = nil
local token = 0

-- 経験値の倍率（日替わりの expMult）。留守番の探索は経験値を得ないので 1（D-280）
local function xpMult(e: any): number
	local m = 1
	if e.offline then
		return m
	end
	local trait = if e.dailyTraitId then master.dailyTraits[e.dailyTraitId] else nil
	if trait and trait.effect == "expMult" then
		m *= trait.value
	end
	return m
end

-- onEnd：トーストが消えたとき（時間・触る・Go）に1回だけ呼ぶ（ログインの流れで次へ進む：D-281）
local function show(group: { any }, levelUps: number, onEnd: (() -> ())?)
	if current then
		current:Destroy()
		current = nil
	end
	token += 1
	local my = token
	local parties, seen, chests, mult = {}, {}, 0, 1
	for _, e in group do
		if not seen[e.partyIndex] then
			seen[e.partyIndex] = true
			table.insert(parties, e.partyIndex) -- 同じパーティが何度も帰っても番号は1つ（ログインの留守番）
		end
		chests += e.chests or 0
		mult = math.max(mult, xpMult(e))
	end
	local daily = mult > 1
	table.sort(parties)
	local band = Root.bandBottom()
	local toast: Frame = new("Frame", {
		Name = "ReturnToast",
		-- 左の一覧のすぐ右から。右上のボタン（Quests・Settings：D-245 で語が付き広がった）に重ねない
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(200, band + 12),
		Size = UDim2.fromOffset(620, 80),
		BackgroundColor3 = C.ch10,
		ZIndex = 50,
		[CHILDREN] = { Components.corner(40), Components.stroke(C.bronze, 3) },
		Parent = Root.canvas,
	})
	current = toast
	local ended = false
	local function close()
		if toast.Parent then
			toast:Destroy()
		end
		if current == toast then
			current = nil
		end
		if not ended then
			ended = true
			if onEnd then
				onEnd()
			end
		end
	end
	toast.Destroying:Connect(function()
		-- 次のトーストに差し替えられたときも、流れを止めない
		if not ended then
			ended = true
			if onEnd then
				task.defer(onEnd)
			end
		end
	end)
	local tap: TextButton = new("TextButton", {
		Name = "Select",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 7),
		Size = UDim2.new(1, -130, 1, -14),
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
	local function label(order: number, text: string, size: number, color: Color3): TextLabel
		local t = Components.text({ text = text, size = size, color = color, font = Tokens.font.number })
		t.LayoutOrder = order
		t.ZIndex = 52
		t.Parent = tap
		return t
	end
	local nums = {}
	for _, p in parties do
		table.insert(nums, tostring(p))
	end
	label(1, "◀ " .. table.concat(nums, " "), 28, C.inkLight)
	local chestLabel = label(2, "▣ +0", 30, C.numHi)
	-- 宝箱の数は 0 からカウントアップ（D-269 ⑤）
	task.defer(function()
		if chestLabel.Parent then
			Motion.countUp(chestLabel, 0, chests, { prefix = "▣ +", float = false })
		end
	end)
	if daily then
		-- 日替わり＝太陽
		label(3, "☀ XP ×" .. mult, 23, C.inkLight)
	end
	if levelUps > 0 then
		label(4, "Lv▲ " .. levelUps, 23, C.upDark) -- レベルが上がった人数（D-246 ④）
	end
	tap.Activated:Connect(function()
		HubState.selected = parties[1]
		HubState.following = true
		close()
	end)
	-- 右の端：同じ所へもう一度（待機のパーティだけ）
	local go: TextButton = new("TextButton", {
		Name = "Go",
		Text = "▶ " .. Words.go, -- パーティの面の Go と同じ（↺ は Roblox の書体で出ない）。語を添える（D-245）
		TextSize = 21,
		FontFace = Tokens.font.display,
		TextColor3 = C.inkLight,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -7, 0.5, 0),
		Size = UDim2.fromOffset(100, 66),
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
		close()
	end)
	task.delay(SHOW_SECONDS, function()
		if token == my and toast.Parent then
			close()
		end
	end)
end

-- ログイン：留守の間に帰ったパーティごとに1つずつ出し、全部終えたら done（D-281）。
--   groups はパーティごとの帰還の出来事（LoginFlow.summarize の returned）。設定でオフなら出さずに done
function ReturnToast.playLogin(groups: { { any } }, done: () -> ())
	local view = Session.view
	if #groups == 0 or view == nil or not Game.query.preferences(view, master).returnToast then
		done()
		return
	end
	local i = 0
	local function nextOne()
		i += 1
		local g = groups[i]
		if g == nil then
			done()
			return
		end
		show(g, 0, nextOne)
	end
	nextOne()
end

function ReturnToast.mount()
	Session.events:connect(function(reason: string, events: { any })
		if reason == "load" then
			return -- ログインの帰還はまとめの画面で見せる（S-01）
		end
		for _, e in events do
			if e.type == "ExpeditionReturned" and not e.offline then
				table.insert(pending, e)
			elseif e.type == "LevelUp" and e.uid then
				pendingLevelUps[e.uid] = true
				LevelUpMarks.note(e.uid) -- パーティの面で一度光らせる（トーストを出さないときも）
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
			local levelUps = 0
			for _ in pendingLevelUps do
				levelUps += 1
			end
			pendingLevelUps = {}
			local view = Session.view
			if Nav.depth() > 0 or view == nil then
				return
			end
			if not Game.query.preferences(view, master).returnToast then
				return
			end
			show(group, levelUps)
		end)
	end)
end

return ReturnToast
