--!strict
-- ボタンに添える語（D-245）。全画面で同じ操作には同じ語を使うため、ここ1か所にまとめる。
--   英語ベース＋Roblox の自動翻訳（D-136）。動詞か名詞の1・2語。
--   語を添えないのは、閉じる×と、物そのもの（マップのダンジョン・馬車・品のカード・冒険者の札など）を触るものだけ。

local Words = {
	-- 出発・パーティ
	go = "Go",
	goAll = "Go All",
	editParty = "Edit Party", -- 編成の面・その入口（D-265 ⑥。Menu・Party をそろえた）
	addToParty = "Add to Party", -- 採用の後・控えの人（D-265）
	makeLeader = "Make Leader", -- パーティのリーダーにする（D-271 ①）
	undo = "Undo", -- 入れ替えと自動装備を戻す（D-266 ③）
	skip = "Skip", -- 開封の演出を飛ばす（D-267 ②）
	repeatOn = "Repeat",
	autoRepeat = "Auto Repeat", -- 自動再派遣のスイッチ（D-269 ②）
	form = "Form",
	destination = "Destination",
	autoEquip = "Auto Equip",
	-- 出発の面の攻略ヒントの行の見出し（ボタンではないが、同じ語をそろえるためここに置く：D-250 ③）
	foes = "Foes",
	traps = "Traps",
	-- 宝箱・受け取り箱
	chests = "Chests",
	open = "Open",
	openAll = "Open All",
	claim = "Claim",
	equip = "Equip",
	unequip = "Unequip",
	next = "Next",
	again = "Again",
	sell = "Sell",
	bulkSell = "Bulk Sell",
	-- ギルド・雇用
	guild = "Guild",
	hire = "Hire",
	expand = "Expand",
	home = "Home",
	-- 冒険者
	adventurers = "Adventurers",
	train = "Train",
	rename = "Rename",
	looks = "Looks",
	jobChange = "Job",
	dismiss = "Dismiss",
	keepLook = "Keep Look",
	ok = "OK",
	lock = "Lock",
	locked = "Locked",
	cancel = "Cancel",
	-- 倉庫・ショップ・その他
	warehouse = "Warehouse",
	buy = "Buy",
	odds = "Odds",
	quests = "Quests",
	settings = "Settings",
	friends = "Friends",
	invite = "Invite",
	allow = "Allow",
	sort = "Sort",
	all = "All",
	full = "Full",
	weapons = "Weapons",
	armor = "Armor",
	accessories = "Accessories",
	items = "Items",
	inbox = "Inbox",
	autoSell = "Auto Sell",
	-- 旅の商人（D-274）
	merchant = "Merchant",
	raidBoss = "Raid Boss", -- レイドボス（D-275。照準の札）
	leave = "Leave", -- 商人のところから帰る
	leavesIn = "Leaves in", -- 商人が去るまで（頭上の時計）
	arrivesIn = "Arrives in", -- パーティが商人に着くまで
	oneWay = "One way", -- 商人までの片道
	shopping = "Shopping", -- パーティが商人のところにいる
	unlock = "Unlock", -- ゴールドでダンジョンを先に解放する（D-279）
	unlocked = "Unlocked", -- 解放できたときのハンコ（D-279・D-269）
}

-- 押せない理由・アラート（1行・12語まで：D-264 ②③）
Words.reason = {
	partyOut = "Can't add to a party on an adventure", -- D-265 ②
	noBetterGear = "No better gear in Warehouse", -- D-266 ④
	allOut = "All parties are out", -- D-269 ④
	noneCanEquip = "No one can equip this now", -- D-265 ⑤（付けられる人がいない・全員が冒険中）
	partyOnTheWay = "Your party is still on the way", -- D-274（商人に着くまで買えない）
	equipOut = "Can't equip during an adventure", -- 冒険中の人には付けられない（宝箱の結果の Equip：D-264）
	editOut = "Can't edit a party on an adventure", -- 冒険中は編成できない（パーティの面の Edit Party：D-265 ②）
	prevLocked = "Unlock the previous dungeon first", -- D-279（前のダンジョンが未解放）
}

-- 画面のタイトル（1〜3語：D-264 ②）
Words.title = {
	editParty = "Edit Party",
}

-- 初回の誘導の指に添える1行（D-264 ④）
Words.hint = {
	dragReserve = "Drag a reserve onto a member",
}

-- 装備の枠・倉庫のタブの語（D-245）と、語が入るタブの幅
Words.slot = { weapon = "Weapons", armor = "Armor", sub = "Accessories", items = "Items" }
Words.slotWidth = { weapon = 160, armor = 140, sub = 190, items = 130 }

-- ログイン時のまとめ（S-01、D-281）：題の札と、組の見出し
Words.title.welcomeBack = "Welcome Back"
Words.gold = "Gold"

-- 拡張（S-22）の押せない理由（D-264 ②。%d＝ギルドLv、%s＝ダンジョン名）
Words.reason.expandNeedLevel = "Reach Guild Lv %d first"
Words.reason.expandNeedClear = "Clear %s first"
Words.reason.expandNeedBoth = "Reach Guild Lv %d and clear %s"
Words.reason.fullyExpanded = "Fully expanded"

-- 雇用の画面（D-283）
Words.back = "Back" -- 採用の後にギルド（受付の広間）へ戻る
Words.growth = "Growth" -- 求人票の職業を押すと出る伸びやすさの見出し（D-046・D-269 ④）
Words.total = "Total" -- 面接の最後の合計（HP を除く4項目：Q-006）
Words.great = "Great" -- Total が hireTotalGreat 以上
Words.amazing = "Amazing" -- Total が hireTotalAmazing 以上
Words.reason.pickPosting = "Pick a posting first" -- 求人票を選ぶ前の Hire
Words.leftCount = "%d left" -- 開封の Next の残りの数（点を並べない）

return Words
