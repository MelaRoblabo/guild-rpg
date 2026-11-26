--!strict
-- S-21e 採用（D-220・D-265 ①②）。HIRED のハンコのあと、決まった能力と金の「Add to Party」を出す。
--   - 待機中のパーティがあれば：雇った人のカードが画面の下（控えの列）へ飛び、そのまま編成の面（Edit Party）が開く。
--     控えの列では雇った人が先頭で NEW・脈打つ。
--   - 全員が冒険中なら：「Can't add to a party on an adventure」のアラートを出し、カードはマップのギルドの建物へ
--     飛び込む（建物に NEW の顔）。パーティが帰ったら、馬車 → Edit Party を一度だけ光らせる（HubState.newcomers）。
--   - 閉じる × はメイン画面へ。「もう一度呼ぶ」は出さない（D-226 ③ の Home・Party の2つは D-265 で置き換え）。

local TweenService = game:GetService("TweenService")

local Party = require("@game/ReplicatedStorage/Core/Party")
local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local HireCommon = require("./HireCommon")
local HubState = require("../../hub/HubState")
local Motion = require("../../ui/Motion")
local Nav = require("../../ui/Nav")
local Portrait = require("../../ui/Portrait")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local Words = require("../../ui/Words")

local C = Tokens.color
local I = Components.icon
local new = Create.new
local CHILDREN = Create.Children

-- 控えの列が出る所（編成の面の左下。PartyMenu の Reserve と同じ辺り。基準の単位）
local RESERVE_AT = Vector2.new(260, 650)

-- 飛ばす顔のカード
local function faceCard(appearanceId: string?): Frame
	local card: Frame = new("Frame", {
		Name = "FlyingCard",
		BackgroundColor3 = C.ch13,
		[CHILDREN] = { Components.corner(14), Components.stroke(C.selAmber, 4) },
	})
	Portrait.fill(card, appearanceId)
	return card
end

-- 最初の待機中のパーティ
local function waitingParty(): number?
	local v = Session.view
	for _, p in (v and v.parties) or {} do
		if not Party.isBusy(v, p.index) then
			return p.index
		end
	end
	return nil
end

local function build(params: any?, api: Nav.Api): Nav.Built
	local view = Session.view
	local uid = params and (params :: any).uid
	local adv = view and uid and view.adventurers[uid]
	local frame = HireCommon.scene("HireDone")
	HireCommon.closeTopRight(frame, api.home)
	if not adv then
		return { frame = frame, scrim = 1 }
	end
	local candidate = {
		kind = if adv.uniqueId then "unique" else "general",
		name = adv.name,
		jobId = adv.jobId,
		giftIds = adv.giftIds,
		appearanceId = adv.appearanceId,
	}
	local portrait = HireCommon.portrait(frame, candidate)
	local panel = HireCommon.statPanel(frame, candidate, adv.baseStats, nil)
	panel.frame.Visible = false

	-- 1拍目：ハンコ（共通の動きの部品：D-269 ⑤）
	local stamp = Motion.stamp(portrait, "HIRED", C.warn, 320)

	-- 2拍目：決まった能力と Add to Party
	local actions = HireCommon.actionRow(frame)
	actions.Visible = false
	local sent = false
	local add = Components.button({
		kind = "gold",
		width = 300,
		icon = I.party,
		label = Words.addToParty,
		name = "AddToParty",
		glyph = "A",
		onClick = function()
			if sent then
				return
			end
			sent = true
			local target = waitingParty()
			local card = faceCard(adv.appearanceId)
			if target then
				-- カードが控えの列へ飛び、着いたら編成の面を開く（画面が切り替わらず、つながって見える）
				Motion.fly({
					from = portrait,
					to = RESERVE_AT,
					visual = card,
					size = 220,
					endSize = 80,
					onArrive = function()
						api.home()
						Nav.open("PartyMenu", { partyIndex = target, newcomer = uid })
					end,
				})
			else
				-- 全員が冒険中：アラート → カードはギルドの建物へ（D-265 ②）
				HubState.newcomers[uid] = true
				Motion.alert(Words.reason.partyOut)
				local from = Motion.center(portrait)
				api.home()
				local guild = HubState.guildPoint and HubState.guildPoint()
				Motion.fly({
					from = from,
					to = guild or Vector2.new(640, 360),
					visual = card,
					size = 200,
					endSize = 60,
					delay = 0.6,
				})
			end
		end,
	})
	add.Parent = actions
	task.delay(0.9, function()
		if frame.Parent then
			TweenService:Create(stamp, TweenInfo.new(0.3), { Size = UDim2.fromOffset(110, 110) }):Play()
			stamp.Position = UDim2.new(1, -70, 1, -70)
			panel.frame.Visible = true
			actions.Visible = true
		end
	end)
	return { frame = frame, scrim = 1 }
end

Nav.register("HireDone", build)

return {}
