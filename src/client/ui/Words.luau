--!strict
-- ボタンに添える語（D-245）。全画面で同じ操作には同じ語を使うため、ここ1か所にまとめる。
--   英語ベース＋Roblox の自動翻訳（D-136）。動詞か名詞の1・2語。
--   語を添えないのは、閉じる×と、物そのもの（マップのダンジョン・馬車・品のカード・冒険者の札など）を触るものだけ。

local Words = {
	-- 出発・パーティ
	go = "Go",
	goAll = "Go All",
	menu = "Menu",
	repeatOn = "Repeat",
	form = "Form",
	destination = "Destination",
	autoEquip = "Auto Equip",
	party = "Party",
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
}

-- 装備の枠・倉庫のタブの語（D-245）と、語が入るタブの幅
Words.slot = { weapon = "Weapons", armor = "Armor", sub = "Accessories", items = "Items" }
Words.slotWidth = { weapon = 160, armor = 140, sub = 190, items = 130 }

return Words
