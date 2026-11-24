--!strict
-- Guild UI の色と寸法（D-221・D-222・D-227 ③）。デザインシステム「Guild UI」v3 の tokens.json から写した。
-- 見た目の値で、ゲームの数値ではないので src/data には置かない（D-227）。値を変えるときは Guild UI の tokens.json と一緒に直す。

local Tokens = {}

-- 色（Color3）。透明度つきのもの（scrim・text-stroke・disabled-ink）は alpha を別に持つ
Tokens.color = {
	ch05 = Color3.fromHex("#0e0b08"),
	ch10 = Color3.fromHex("#1e1810"),
	ch13 = Color3.fromHex("#2d2113"),
	ch16 = Color3.fromHex("#382d1b"),
	ch17 = Color3.fromHex("#3d2e1b"),
	ch28 = Color3.fromHex("#5d4a30"),
	ch45 = Color3.fromHex("#846f53"),
	ch50 = Color3.fromHex("#a48861"),
	ch52 = Color3.fromHex("#af905b"),
	ch68 = Color3.fromHex("#d9b886"),
	ch75 = Color3.fromHex("#e5c999"),
	closeFill = Color3.fromHex("#442212"),
	bronze = Color3.fromHex("#b57f4a"),
	bronzeHi = Color3.fromHex("#d6a565"),
	inkDark = Color3.fromHex("#3a2614"),
	inkMid = Color3.fromHex("#6b4d2e"),
	inkLight = Color3.fromHex("#f3e3c0"),
	inkWhite = Color3.fromHex("#ffffff"),
	numHi = Color3.fromHex("#ffd36a"),
	lvOrange = Color3.fromHex("#f0a83a"),
	scrim = Color3.fromRGB(14, 11, 8),
	textStroke = Color3.fromRGB(14, 11, 8),
	ctaGold = Color3.fromHex("#fee879"),
	ctaGoldLow = Color3.fromHex("#ebaf3e"),
	ctaGoldRim = Color3.fromHex("#8a5a14"),
	ctaBlue = Color3.fromHex("#7cdaef"),
	ctaBlueLow = Color3.fromHex("#32a6ca"),
	ctaBlueRim = Color3.fromHex("#1c5f78"),
	selAmber = Color3.fromHex("#deab4a"),
	selOrange = Color3.fromHex("#c2621c"),
	selOrangeLow = Color3.fromHex("#9f4e14"),
	okGreen = Color3.fromHex("#7cb73b"),
	specialPurple = Color3.fromHex("#473088"),
	dangerRed = Color3.fromHex("#b70000"),
	warnDark = Color3.fromHex("#ff7a4a"),
	rewardGlow = Color3.fromHex("#ffe27a"),
	coinGold = Color3.fromHex("#f0c45a"),
	barTrack = Color3.fromHex("#2d1f12"),
	barFill = Color3.fromHex("#e9b44c"),
	barFillLow = Color3.fromHex("#b8781e"),
	padA = Color3.fromHex("#3f9b3f"),
	padB = Color3.fromHex("#c8402f"),
	padX = Color3.fromHex("#2f74c4"),
	padY = Color3.fromHex("#c49a1e"),
	action = Color3.fromHex("#fee879"),
	actionLow = Color3.fromHex("#ebaf3e"),
	actionRim = Color3.fromHex("#8a5a14"),
	actionEdge = Color3.fromHex("#8a5a14"),
	actionInk = Color3.fromHex("#3a2614"),
	focus = Color3.fromHex("#7cdaef"),
	focusLow = Color3.fromHex("#32a6ca"),
	focusRim = Color3.fromHex("#1c5f78"),
	focusInk = Color3.fromHex("#ffffff"),
	selection = Color3.fromHex("#deab4a"),
	secondary = Color3.fromHex("#5d4a30"),
	secondaryRim = Color3.fromHex("#b57f4a"),
	secondaryEdge = Color3.fromHex("#2d2113"),
	secondaryInk = Color3.fromHex("#f3e3c0"),
	disabled = Color3.fromHex("#382d1b"),
	disabledInk = Color3.fromRGB(243, 227, 192),
	up = Color3.fromHex("#3f7d1e"),
	upDark = Color3.fromHex("#7cb73b"),
	warn = Color3.fromHex("#a8340f"),
	notice = Color3.fromHex("#d8362a"),
	reward = Color3.fromHex("#ffe27a"),
	rest = Color3.fromHex("#8fd3ff"),
	statStr = Color3.fromHex("#a8462a"),
	statMag = Color3.fromHex("#5a46b0"),
	statAgi = Color3.fromHex("#2b7a48"),
	statDex = Color3.fromHex("#8a6a10"),
	statHp = Color3.fromHex("#2a6699"),
	statStrDark = Color3.fromHex("#ef8a6a"),
	statMagDark = Color3.fromHex("#a796ff"),
	statAgiDark = Color3.fromHex("#6fdc98"),
	statDexDark = Color3.fromHex("#f0cd66"),
	statHpDark = Color3.fromHex("#6fbcf0"),
	rarCommon = Color3.fromHex("#8a8a80"),
	rarUncommon = Color3.fromHex("#3f9a4a"),
	rarRare = Color3.fromHex("#2f78c4"),
	rarEpic = Color3.fromHex("#8a4fd0"),
	rarLegend = Color3.fromHex("#d98a1c"),
	rarMythic = Color3.fromHex("#d8366a"),
	grade1 = Color3.fromHex("#b57f4a"),
	grade2 = Color3.fromHex("#d6a565"),
	grade3 = Color3.fromHex("#ebaf3e"),
	grade4 = Color3.fromHex("#ffe27a"),
	kept = Color3.fromHex("#846f53"),
	bg000 = Color3.fromHex("#0e0b08"),
	bg100 = Color3.fromHex("#1e1810"),
	bg200 = Color3.fromHex("#2d2113"),
	bg300 = Color3.fromHex("#d9b886"),
	bg400 = Color3.fromHex("#a48861"),
	line = Color3.fromHex("#382d1b"),
	lineStrong = Color3.fromHex("#b57f4a"),
	ink = Color3.fromHex("#3a2614"),
	inkMuted = Color3.fromHex("#6b4d2e"),
	inkFaint = Color3.fromHex("#6b4d2e"),
}

-- 透明度（Roblox の Transparency。1 − alpha）
Tokens.transparency = {
	scrim = 0.25,
	textStroke = 0.40,
	disabledInk = 0.50,
}

-- spacing（基準の画面 1280×720 の px）
Tokens.spacing = {
	space1 = 4,
	space2 = 8,
	space3 = 12,
	rowGap = 10,
	space4 = 16,
	panelPad = 24,
	panelPadPlaque = 34,
	space6 = 24,
	space10 = 40,
	safeLeft = 96,
	frame = 10,
	bevel = 2,
	trim = 2,
	rim = 3,
	lip = 5,
	lipSecondary = 4,
	lineMin = 2,
}

-- radius（基準の画面 1280×720 の px）
Tokens.radius = {
	radiusBar = 6,
	radiusSm = 8,
	radiusMd = 12,
	radiusPanel = 12,
	radiusLg = 16,
	radiusBtn = 18,
	radiusXl = 20,
}

-- size（基準の画面 1280×720 の px）
Tokens.size = {
	tapMin = 66,
	textMin = 21,
	btnPrimaryH = 80,
	btnSecondaryH = 66,
	backSize = 66,
	closeSize = 66,
	headerH = 66,
	plaqueH = 52,
	ribbonH = 36,
	wellH = 56,
	barH = 26,
	barHLg = 32,
	chipH = 52,
	ornament = 28,
	iconBtn = 30,
	sliceCorner = 32,
}

-- 文字の大きさ（基準の画面の px。最小 21：D-206）
Tokens.text = {
	caption = 21,
	label = 23,
	body = 25,
	button = 25,
	title = 30,
	display = 40,
}

-- 書体（D-221：見出し・ボタンの語は Merriweather、それ以外は Nunito。細い太さは使わない）
Tokens.font = {
	display = Font.fromName("Merriweather", Enum.FontWeight.Heavy),
	body = Font.fromName("Nunito", Enum.FontWeight.Bold),
	bodyStrong = Font.fromName("Nunito", Enum.FontWeight.ExtraBold),
	number = Font.fromName("Nunito", Enum.FontWeight.Heavy),
}

-- 基準の画面と Roblox の帯（D-219）
Tokens.base = {
	width = 1280,
	height = 720,
	topBand = 106, -- Roblox の上の帯（58pt ÷ 0.546）。実装では TopbarInset からも求める
}

return Tokens
