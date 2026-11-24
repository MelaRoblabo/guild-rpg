--!strict
-- カットイン（D-118・D-132：ログイン時は最大1回）。まとめの次に出す。
--   - 暗幕80%の上に、斜めの暗い木の帯（-7°）と金の光。真ん中に丸い札、右に中身。
--   - ギルドLvアップ：札＝ギルドの旗、右＝「Lv 48 ▲」と上がった分の報酬（チケット ×12 など）。
--   - ダンジョンの解放：札＝ダンジョンの番号（ローマ数字）、右＝ダンジョンの名前の旗。
--   - どこを触っても次へ。触らなくても少しで次へ進む（止まる回数を減らす：D-218 ④）。設定でカットインがオフなら出さない（D-117）。

local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Nav = require("../../ui/Nav")
local Root = require("../../ui/Root")
local Tokens = require("../../ui/Tokens")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local SHOW_SECONDS = 3 -- 自動で次へ進むまで（仮。値は M8-FX でマスターデータへ）
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII" }
local ITEM_ICON = { itm_slot_ticket = Components.icon.ticket }

local function build(params: any?, _api: Nav.Api): Nav.Built
	local cut = (params :: any).cutIn :: any
	local onNext = (params :: any).onNext :: () -> ()
	local frame: TextButton = new("TextButton", {
		Name = "CutIn",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	local done = false
	local function go()
		if not done then
			done = true
			onNext()
		end
	end
	frame.Activated:Connect(go)
	-- 金の光と斜めの帯
	new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 50),
		Size = UDim2.fromOffset(520, 520),
		BackgroundColor3 = C.rewardGlow,
		BackgroundTransparency = 0.9,
		[CHILDREN] = { Components.corner(260) },
		Parent = frame,
	})
	new("Frame", {
		Name = "Band",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 50),
		Size = UDim2.new(1.3, 0, 0, 220),
		Rotation = -7,
		BackgroundColor3 = C.ch16,
		[CHILDREN] = {
			Components.stroke(C.bronze, 4),
			Components.gradient(C.ch28, C.ch13),
		},
		Parent = frame,
	})
	local center = Root.bandBottom() + (720 - Root.bandBottom()) / 2
	local medal: Frame = new("Frame", {
		Name = "Medal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, center + 40),
		Size = UDim2.fromOffset(200, 200),
		BackgroundColor3 = C.ch16,
		[CHILDREN] = { Components.corner(100), Components.stroke(C.bronze, 6) },
		Parent = frame,
	})
	local function medalText(t: string, size: number, color: Color3, font: Font)
		local l = Components.text({ text = t, size = size, color = color, font = font, stroke = true })
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromScale(0.5, 0.5)
		l.Parent = medal
	end
	local side: Frame = new("Frame", {
		Name = "Side",
		Position = UDim2.new(0.5, 124, 0, center + 40 - 70),
		Size = UDim2.fromOffset(460, 160),
		BackgroundTransparency = 1,
		[CHILDREN] = {
			new("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }),
		},
		Parent = frame,
	})
	local function plaque(order: number, t: string, size: number, color: Color3, font: Font)
		local p: Frame = new("Frame", {
			LayoutOrder = order,
			Size = UDim2.fromOffset(0, size + 32),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.ch10,
			[CHILDREN] = {
				Components.corner(12),
				Components.stroke(C.bronze, 3),
				Components.padding(0, 22, 0, 22),
			},
			Parent = side,
		})
		local l = Components.text({ text = t, size = size, color = color, font = font, stroke = true })
		l.Position = UDim2.fromScale(0, 0.5)
		l.AnchorPoint = Vector2.new(0, 0.5)
		l.Parent = p
		return p
	end
	if cut.kind == "guild" then
		medalText("🏰", 96, C.bronzeHi, Tokens.font.number)
		plaque(1, "Lv " .. cut.level .. " " .. Components.icon.up, 40, C.lvOrange, Tokens.font.display).Name = "Level"
		local ids = {}
		for id in cut.rewards or {} do
			table.insert(ids, id)
		end
		table.sort(ids)
		for i, id in ids do
			local chip = Components.chip(ITEM_ICON[id] or "◈", "×" .. cut.rewards[id], C.inkLight)
			chip.Name = "Reward" .. i
			chip.LayoutOrder = 1 + i
			chip.Parent = side
		end
	else
		local d = master.dungeons[cut.dungeonId]
		medalText(if d then ROMAN[d.tier] or tostring(d.tier) else "?", 40, C.inkLight, Tokens.font.display)
		side.Position = UDim2.new(0.5, 124, 0, center + 40 - 32)
		plaque(1, if d then d.nameEn else cut.dungeonId, 30, C.inkLight, Tokens.font.display).Name = "Dungeon"
	end
	task.delay(SHOW_SECONDS, function()
		if frame.Parent then
			go()
		end
	end)
	return { frame = frame, scrim = 0.2 }
end

Nav.register("CutIn", build)

return {}
