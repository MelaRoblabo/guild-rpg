--!strict
-- Guild UI の部品（D-218〜D-222、Guild UI README の部品の一覧）。
-- 絵の素材がそろうまでは、枠を塗り・縁・角丸で作る（D-227 ②）。アイコンも仮の文字で置き、
-- 素材ができたら画像に差し替える。寸法はすべて基準の単位（1280×720 基準。Root の UIScale で縮む）。

local Create = require("./Create")
local Input = require("./Input")
local Tokens = require("./Tokens")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local Components = {}

-- 仮のアイコン（文字）。素材ができたら画像に差し替える（D-227 ②）
Components.icon = {
	-- Roblox の書体で出る記号だけを使う（↻・↶・✕ などは出ない：M8-1 の Studio で確認）
	close = "✖",
	check = "✓",
	reroll = "⇄",
	undo = "⬅",
	home = "⌂",
	party = "♟",
	ticket = "▭",
	coin = "G",
	plus = "✚",
	star = "★",
	up = "▲",
	down = "▼",
	bell = "♪",
	search = "⊕",
	stamp = "◎",
}

-- 能力の色（アイコンだけに使う：D-222 ⑩）
local STAT_COLOR: { [string]: Color3 } = {
	str = C.statStr,
	mag = C.statMag,
	agi = C.statAgi,
	dex = C.statDex,
	hp = C.statHp,
}

---------------------------------------------------------------------------
-- 小さな道具

function Components.corner(radius: number): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

function Components.stroke(color: Color3, thickness: number, transparency: number?): UIStroke
	return new("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Components.gradient(top: Color3, bottom: Color3): UIGradient
	return new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = 90,
	})
end

function Components.padding(top: number, right: number, bottom: number, left: number): UIPadding
	return new("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right),
		PaddingBottom = UDim.new(0, bottom),
		PaddingLeft = UDim.new(0, left),
	})
end

export type TextProps = {
	text: string,
	size: number?, -- 文字の大きさ（基準 px。最小 21：D-206）
	color: Color3?,
	font: Font?,
	stroke: boolean?, -- 暗い地・絵の上の文字の縁取り（Roblox の UIStroke 2px）
	xAlign: Enum.TextXAlignment?,
	autoSize: boolean?,
}

function Components.text(p: TextProps): TextLabel
	local size = math.max(p.size or Tokens.text.body, Tokens.text.caption)
	local label: TextLabel = new("TextLabel", {
		BackgroundTransparency = 1,
		Text = p.text,
		TextSize = size,
		TextColor3 = p.color or C.inkDark,
		FontFace = p.font or Tokens.font.body,
		TextXAlignment = p.xAlign or Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		AutomaticSize = if p.autoSize ~= false then Enum.AutomaticSize.XY else Enum.AutomaticSize.None,
		Size = UDim2.fromOffset(0, size),
	})
	if p.stroke then
		new("UIStroke", {
			Color = C.textStroke,
			Transparency = Tokens.transparency.textStroke,
			Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			Parent = label,
		})
	end
	return label
end

-- ゲームパッドの印（A/B/X/Y）。ゲームパッドのときだけ見える（D-218 ①）
function Components.padGlyph(letter: string, parent: GuiObject)
	local colors = { A = C.padA, B = C.padB, X = C.padX, Y = C.padY }
	local glyph: Frame = new("Frame", {
		Name = "PadGlyph",
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.new(1, -20, 0, -10),
		BackgroundColor3 = colors[letter] or C.padA,
		Visible = Input.gamepad,
		ZIndex = 20,
		[CHILDREN] = {
			Components.corner(15),
			Components.stroke(C.ch05, 2),
			(function()
				local t = Components.text({ text = letter, size = 21, color = C.inkWhite, font = Tokens.font.number })
				t.AutomaticSize = Enum.AutomaticSize.None
				t.Size = UDim2.fromScale(1, 1)
				t.ZIndex = 21
				return t
			end)(),
		},
		Parent = parent,
	})
	Input.changed:connect(function(gamepad)
		glyph.Visible = gamepad
	end)
end

---------------------------------------------------------------------------
-- 面

-- 四隅の飾り（仮：青銅の鋲。9スライスの角のマス 32×32 の中に収める）
local function ornaments(parent: GuiObject)
	for _, a in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		new("Frame", {
			Name = "Ornament",
			AnchorPoint = a,
			Position = UDim2.new(a.X, if a.X == 0 then 9 else -9, a.Y, if a.Y == 0 then 9 else -9),
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = C.bronze,
			ZIndex = 4,
			[CHILDREN] = { Components.corner(7), Components.stroke(C.ch13, 2) },
			Parent = parent,
		})
	end
end

export type PanelProps = {
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	title: string?, -- 題の札（固有名など）
	dark: boolean?, -- 暗い木の面（一覧・情報）。既定は羊皮紙（D-222 ⑨）
}

-- 面を作る。戻り値：面全体と、中身を入れる枠
function Components.panel(p: PanelProps): (Frame, Frame)
	local outer: Frame = new("Frame", {
		Name = "Panel",
		Size = p.size,
		Position = p.position or UDim2.new(),
		AnchorPoint = p.anchor or Vector2.new(),
		BackgroundColor3 = C.ch16,
		[CHILDREN] = { Components.corner(Tokens.radius.radiusPanel) },
	})
	-- 落とし影
	new("Frame", {
		Name = "Shadow",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 8),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
		ZIndex = 0,
		[CHILDREN] = { Components.corner(Tokens.radius.radiusPanel) },
		Parent = outer,
	})
	local inset = Tokens.spacing.frame
	local fill: Frame = new("Frame", {
		Name = "Fill",
		Position = UDim2.fromOffset(inset, inset),
		Size = UDim2.new(1, -inset * 2, 1, -inset * 2),
		BackgroundColor3 = if p.dark then C.ch10 else C.ch68,
		ZIndex = 2,
		[CHILDREN] = {
			Components.corner(6),
			if p.dark then nil else Components.gradient(C.ch75, C.ch68),
			if p.dark then nil else Components.stroke(C.ch75, 2),
		},
		Parent = outer,
	})
	ornaments(outer)
	local padTop = if p.title then Tokens.spacing.panelPadPlaque else Tokens.spacing.panelPad
	local content: Frame = new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		[CHILDREN] = { Components.padding(padTop, 14, 14, 14) },
		Parent = fill,
	})
	if p.title then
		local plaque: Frame = new("Frame", {
			Name = "TitlePlaque",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(20, 0),
			Size = UDim2.fromOffset(0, Tokens.size.plaqueH),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = if p.dark then C.ch16 else C.ch45,
			ZIndex = 6,
			[CHILDREN] = {
				Components.corner(6),
				Components.stroke(C.bronze, 2),
				Components.padding(0, 30, 0, 30),
				(function()
					local t = Components.text({
						text = p.title :: string,
						size = Tokens.text.title,
						color = C.inkLight,
						font = Tokens.font.display,
						stroke = true,
					})
					t.Size = UDim2.fromOffset(0, Tokens.size.plaqueH)
					t.ZIndex = 7
					return t
				end)(),
			},
			Parent = outer,
		})
		plaque.Name = "TitlePlaque"
	end
	return outer, content
end

---------------------------------------------------------------------------
-- ボタン

export type ButtonKind = "gold" | "blue" | "brown" | "disabled"

export type ButtonProps = {
	kind: ButtonKind,
	width: number,
	height: number?, -- 既定 80（メイン）。サブは 66（D-219・Guild UI）
	icon: string?,
	label: string?, -- 語は Rebirth・Sell・Reroll・Choose・Cancel・Nice だけ（D-218・D-220・D-224）
	cost: string?, -- 費用（ボタンの中のコインと数字）
	glyph: string?, -- ゲームパッドの印
	onClick: (() -> ())?,
}

local KIND = {
	gold = { top = C.ctaGold, bottom = C.ctaGoldLow, rim = C.ctaGoldRim, ink = C.inkDark, lip = C.ctaGoldRim },
	blue = { top = C.ctaBlue, bottom = C.ctaBlueLow, rim = C.ctaBlueRim, ink = C.inkWhite, lip = C.ctaBlueRim },
	brown = { top = C.ch28, bottom = C.ch28, rim = C.bronze, ink = C.inkLight, lip = C.ch13 },
	disabled = { top = C.ch16, bottom = C.ch16, rim = C.ch17, ink = C.inkLight, lip = C.ch16 },
}

-- 押せるボタン。戻り値は外側の枠（大きさ = 幅 × (高さ + 厚み)）
function Components.button(p: ButtonProps): Frame
	local h = math.max(p.height or Tokens.size.btnPrimaryH, Tokens.size.tapMin)
	local w = math.max(p.width, Tokens.size.tapMin)
	local k = KIND[p.kind]
	local lip = if p.kind == "gold" or p.kind == "blue" then Tokens.spacing.lip else Tokens.spacing.lipSecondary
	local radius = math.min(Tokens.radius.radiusBtn, h / 2)
	local enabled = p.kind ~= "disabled"
	local holder: Frame = new("Frame", {
		Name = "Button",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(w, h + lip),
	})
	if p.kind ~= "disabled" then
		new("Frame", {
			Name = "Lip",
			Position = UDim2.fromOffset(0, lip),
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = k.lip,
			[CHILDREN] = { Components.corner(radius) },
			Parent = holder,
		})
	end
	local face: TextButton = new("TextButton", {
		Name = "Face",
		Text = "",
		AutoButtonColor = false,
		Active = enabled,
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 2,
		[CHILDREN] = {
			Components.corner(radius),
			Components.gradient(k.top, k.bottom),
			Components.stroke(k.rim, Tokens.spacing.rim),
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = holder,
	})
	local ink = k.ink
	local inkTransparency = if enabled then 0 else Tokens.transparency.disabledInk
	local order = 0
	local function add(inst: GuiObject)
		order += 1
		inst.LayoutOrder = order
		inst.ZIndex = 3
		inst.Parent = face
	end
	if p.icon then
		local t = Components.text({ text = p.icon, size = 30, color = ink, font = Tokens.font.number })
		t.TextTransparency = inkTransparency
		add(t)
	end
	if p.label then
		local t = Components.text({
			text = p.label,
			size = Tokens.text.button,
			color = ink,
			font = Tokens.font.display,
			stroke = p.kind == "blue",
		})
		t.TextTransparency = inkTransparency
		add(t)
	end
	if p.cost then
		local pill: Frame = new("Frame", {
			Name = "Cost",
			Size = UDim2.fromOffset(0, 40),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.ch13,
			[CHILDREN] = {
				Components.corner(20),
				Components.padding(0, 12, 0, 8),
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 6),
				}),
				Components.text({
					text = Components.icon.coin,
					size = 21,
					color = C.coinGold,
					font = Tokens.font.number,
				}),
				Components.text({ text = p.cost, size = 23, color = C.inkLight, font = Tokens.font.number }),
			},
		})
		add(pill)
	end
	if enabled then
		face.MouseButton1Down:Connect(function()
			face.Position = UDim2.fromOffset(0, lip - 1)
		end)
		local function up()
			face.Position = UDim2.fromOffset(0, 0)
		end
		face.MouseButton1Up:Connect(up)
		face.MouseLeave:Connect(up)
		if p.onClick then
			face.Activated:Connect(p.onClick)
		end
	end
	if p.glyph then
		Components.padGlyph(p.glyph, face)
	end
	return holder
end

-- 閉じる ×（右上。重ねた面なら面の右上の角、画面いっぱいなら帯のすぐ下：D-222）
function Components.closeButton(onClick: () -> ()): TextButton
	local size = Tokens.size.closeSize
	local b: TextButton = new("TextButton", {
		Name = "Close",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = C.closeFill,
		ZIndex = 30,
		[CHILDREN] = {
			Components.corner(size / 2),
			Components.stroke(C.bronze, 3),
			(function()
				local t = Components.text({
					text = Components.icon.close,
					size = 30,
					color = C.inkLight,
					font = Tokens.font.number,
				})
				t.AutomaticSize = Enum.AutomaticSize.None
				t.Size = UDim2.fromScale(1, 1)
				t.ZIndex = 31
				return t
			end)(),
		},
	})
	b.Activated:Connect(onClick)
	Components.padGlyph("B", b)
	return b
end

---------------------------------------------------------------------------
-- 能力の行（D-220：アイコン＋表記＋棒＋数字。棒は暗い溝に暖色1つ：D-222 ⑩）

export type StatRowProps = {
	stat: string, -- "str" | "mag" | "agi" | "dex" | "hp"
	label: string, -- STR など（D-220 の例外）
	value: number,
	min: number,
	max: number,
	big: boolean?, -- 攻撃に使う能力と HP は太く
	marks: number?, -- 伸びやすさの ▲ の数（上位2つだけ）
	prev: number?, -- 前回の値（引き直しの画面：目盛り＋差）
}

function Components.statRow(p: StatRowProps): Frame
	local row: Frame = new("Frame", {
		Name = "Stat_" .. p.stat,
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = C.ch75,
		[CHILDREN] = {
			Components.corner(6),
			Components.padding(0, 12, 0, 12),
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 12),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	})
	local function put(inst: GuiObject, order: number)
		inst.LayoutOrder = order
		inst.Parent = row
	end
	-- アイコン（仮：能力の色の丸）
	put(
		new("Frame", {
			Name = "Icon",
			Size = UDim2.fromOffset(30, 30),
			BackgroundColor3 = STAT_COLOR[p.stat] or C.inkMid,
			[CHILDREN] = { Components.corner(15), Components.stroke(C.inkDark, 2) },
		}),
		1
	)
	local label = Components.text({
		text = p.label,
		size = Tokens.text.body,
		color = C.inkDark,
		font = Tokens.font.number,
		xAlign = Enum.TextXAlignment.Left,
	})
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Size = UDim2.fromOffset(64, 30)
	put(label, 2)
	local marks = Components.text({
		text = string.rep(Components.icon.up, p.marks or 0),
		size = 21,
		color = C.inkMid,
		font = Tokens.font.number,
		xAlign = Enum.TextXAlignment.Left,
	})
	marks.AutomaticSize = Enum.AutomaticSize.None
	marks.Size = UDim2.fromOffset(48, 30)
	put(marks, 3)
	-- 棒
	local barH = if p.big then Tokens.size.barHLg else Tokens.size.barH
	local deltaW = if p.prev then 76 else 0
	local track: Frame = new("Frame", {
		Name = "Bar",
		Size = UDim2.new(1, -(30 + 64 + 48 + 12 * 4 + deltaW), 0, barH),
		BackgroundColor3 = C.barTrack,
		ClipsDescendants = true,
		[CHILDREN] = { Components.corner(Tokens.radius.radiusBar) },
	})
	put(track, 4)
	local range = math.max(1, p.max - p.min)
	local frac = math.clamp((p.value - p.min) / range, 0, 1)
	new("Frame", {
		Name = "Fill",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(frac, -4, 1, -4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		[CHILDREN] = { Components.corner(Tokens.radius.radiusBar), Components.gradient(C.barFill, C.barFillLow) },
		Parent = track,
	})
	if p.prev then
		local pf = math.clamp((p.prev - p.min) / range, 0, 1)
		new("Frame", {
			Name = "PrevTick",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(pf, 0),
			Size = UDim2.new(0, 4, 1, 0),
			BackgroundColor3 = C.inkLight,
			ZIndex = 3,
			Parent = track,
		})
	end
	local num = Components.text({
		text = tostring(p.value),
		size = 23,
		color = C.inkWhite,
		font = Tokens.font.number,
		stroke = true,
	})
	num.AutomaticSize = Enum.AutomaticSize.None
	num.Size = UDim2.fromScale(1, 1)
	num.ZIndex = 4
	num.Parent = track
	if p.prev then
		local d = p.value - p.prev
		local txt = if d > 0 then Components.icon.up .. d elseif d < 0 then Components.icon.down .. -d else ""
		local delta = Components.text({
			text = txt,
			size = Tokens.text.body,
			color = if d >= 0 then C.up else C.warn,
			font = Tokens.font.number,
			xAlign = Enum.TextXAlignment.Left,
		})
		delta.AutomaticSize = Enum.AutomaticSize.None
		delta.Size = UDim2.fromOffset(deltaW - 12, 30)
		put(delta, 5)
	end
	return row
end

---------------------------------------------------------------------------
-- 札・吹き出し

-- 一時的な札（ゴールドなどが増減する瞬間だけ出す：D-218 ⑥）
function Components.chip(icon: string, text: string, iconColor: Color3?): Frame
	return new("Frame", {
		Name = "Chip",
		Size = UDim2.fromOffset(0, Tokens.size.chipH),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.ch10,
		[CHILDREN] = {
			Components.corner(Tokens.size.chipH / 2),
			Components.stroke(C.ch16, 2),
			Components.padding(0, 18, 0, 14),
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Components.text({ text = icon, size = 25, color = iconColor or C.coinGold, font = Tokens.font.number }),
			Components.text({ text = text, size = Tokens.text.body, color = C.inkLight, font = Tokens.font.number }),
		},
	})
end

-- NPC の吹き出し（D-220：NPC の台詞は文字で出してよい）
function Components.speechBubble(text: string, width: number): Frame
	local bubble: Frame = new("Frame", {
		Name = "SpeechBubble",
		Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.ch75,
		[CHILDREN] = {
			Components.corner(Tokens.radius.radiusLg),
			Components.stroke(C.ch16, 2),
			Components.padding(18, 24, 18, 24),
		},
	})
	local t = Components.text({ text = text, size = 28, color = C.inkDark, font = Tokens.font.bodyStrong })
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Size = UDim2.fromScale(1, 0)
	t.TextWrapped = true
	t.Parent = bubble
	return bubble
end

return Components
