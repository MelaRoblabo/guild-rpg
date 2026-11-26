--!strict
-- S-22 拡張（D-071・D-209・D-218 ④・D-231 ①⑤・D-237 ①）。入口は受付の広間の壁（S-20）と満員の札。
--   - 左＝暗い木の一覧5行：アイコン＋短い語（Party slots など）＋段階の点（●●○：買った段／全段）＋右に状態の札。
--     状態の札：買える＝費用／ギルドLv が足りない＝鍵＋Lv／踏破が要る＝鍵＋ダンジョンの番号／お金が足りない＝費用が警告の色。
--     条件もお金も足りないときは両方を並べる（D-237 ①）。鍵は「まだ解放していない」だけの意味（D-209）。
--   - 右＝羊皮紙の要約：今の値（暗い凹み）と次の段の増え方（▲＋数）。トレーニング場は上げられる Lv と1回の XP の2行。
--   - 右下の金＝買う（ハンマー＋費用。確認なし：D-231 ①）。条件を満たさないときは押せない色。
--     押せない色でも押せて、押すとボタンの上に理由の吹き出しを2秒（Reach Guild Lv 5 first など：D-264 ②）。

local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local ExpandInfo = require("../../guild/ExpandInfo")
local HubState = require("../../hub/HubState")
local Nav = require("../../ui/Nav")
local Root = require("../../ui/Root")
local Screen = require("../Screen")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local Words = require("../../ui/Words")
local WarehouseCommon = require("../warehouse/WarehouseCommon")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local ICON = {
	partySlots = "@party",
	candidateSlots = "📜",
	rosterSize = "@roster",
	warehouseSize = "@warehouse",
	trainingLevel = "@train",
}
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII" }
local SUMMARY_W = 320

local function build(params: any?, api: Nav.Api): Nav.Built
	local band = Root.bandBottom()
	local frame = Screen.scene("Expand")
	Screen.closeTopRight(frame, api.close)
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local select = (params and (params :: any).kind) or "partySlots"
	local busy = false
	local spent: number? = nil -- 買った直後の減った額（右上の札）
	local render: () -> ()

	render = function()
		body:ClearAllChildren()
		local view = Session.view
		if view == nil then
			return
		end
		local rows = ExpandInfo.rows(view, master)
		-- 買った直後だけ右上にゴールドの札と減った額
		if spent then
			local g = Components.chip(Components.icon.coin, HubState.formatNumber(view.gold))
			g.AnchorPoint = Vector2.new(1, 0)
			g.Position = UDim2.new(1, -120, 0, band + 19)
			g.Parent = body
			local m = Components.text({
				text = "−" .. HubState.formatNumber(spent),
				size = 25,
				color = C.numHi,
				font = Tokens.font.number,
				stroke = true,
			})
			m.AnchorPoint = Vector2.new(1, 0)
			m.Position = UDim2.new(1, -136, 0, band + 76)
			m.Parent = body
		end
		local left, list = Components.panel({
			size = UDim2.new(1, -(40 + 24 + SUMMARY_W + 40), 0, 402),
			position = UDim2.fromOffset(40, band + 98),
			dark = true,
		})
		left.Name = "Expansions"
		left.Parent = body
		new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
		local cur = nil
		for i, r in rows do
			local sel = r.kind == select
			if sel then
				cur = r
			end
			local b: TextButton = new("TextButton", {
				Name = "Row_" .. r.kind,
				LayoutOrder = i,
				Text = "",
				AutoButtonColor = false,
				Size = UDim2.new(1, 0, 0, 66),
				BackgroundColor3 = if sel then C.ch28 else C.ch17,
				[CHILDREN] = {
					Components.corner(8),
					Components.stroke(if sel then C.selAmber else C.ch17, 3),
					Components.padding(0, 10, 0, 12),
					new("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 10),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				},
				Parent = list,
			})
			b.Activated:Connect(function()
				select = r.kind
				render()
			end)
			local function txt(order: number, t: string, size: number, color: Color3)
				local l = Components.text({ text = t, size = size, color = color, font = Tokens.font.number })
				l.LayoutOrder = order
				l.Parent = b
			end
			txt(1, ICON[r.kind] or "?", 28, C.bronzeHi)
			txt(2, ExpandInfo.WORD[r.kind] or r.kind, 21, C.inkLight)
			local dots = string.rep("●", r.bought) .. string.rep("○", r.total - r.bought)
			txt(3, dots, 21, C.bronzeHi)
			-- 状態の札（条件もお金も足りないときは両方：D-237 ①）
			if r.step then
				if r.needLevel then
					local p = WarehouseCommon.pill("@locked", { "@guild", "Lv" .. r.needLevel }, 21)
					p.LayoutOrder = 4
					p.Parent = b
				end
				if r.needClear then
					-- 条件のダンジョン：鍵＋マップと同じ丸の小さな絵（ローマ数字）＋「Clear」（D-269 ②。赤い門の記号では分からなかった）
					local d = master.dungeons[r.needClear]
					local p = WarehouseCommon.pill("@locked", "Clear", 21)
					p.LayoutOrder = 5
					p.Parent = b
					local disc: Frame = new("Frame", {
						Name = "Dungeon",
						LayoutOrder = 3,
						Size = UDim2.fromOffset(30, 30),
						BackgroundColor3 = C.ch16,
						[CHILDREN] = { Components.corner(15), Components.stroke(C.bronze, 2) },
						Parent = p,
					})
					local num = Components.text({
						text = if d then ROMAN[d.tier] or tostring(d.tier) else "?",
						size = 21,
						color = C.inkLight,
						font = Tokens.font.display,
					})
					num.AutomaticSize = Enum.AutomaticSize.None
					num.Size = UDim2.fromScale(1, 1)
					num.Parent = disc
				end
				local cost = WarehouseCommon.pill(
					Components.icon.coin,
					HubState.formatNumber(r.step.gold),
					21,
					if r.shortGold then C.warnDark else nil
				)
				cost.LayoutOrder = 6
				cost.Parent = b
				if r.shortGold then
					for _, c in cost:GetDescendants() do
						if c:IsA("TextLabel") then
							c.TextColor3 = C.warnDark
						end
					end
				end
			else
				local p = WarehouseCommon.pill("", "✓", 21, C.okGreen)
				p.LayoutOrder = 4
				p.Parent = b
			end
		end
		-- 右：要約（今の値と次の段の増え方）
		local right, sum = Components.panel({
			size = UDim2.fromOffset(SUMMARY_W, 388),
			position = UDim2.new(1, -40, 0, band + 98),
			anchor = Vector2.new(1, 0),
		})
		right.Name = "Summary"
		right.Parent = body
		new("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = sum,
		})
		if cur then
			local big = Components.text({
				text = ICON[cur.kind] or "?",
				size = 48,
				color = C.inkDark,
				font = Tokens.font.number,
			})
			big.LayoutOrder = 1
			big.Parent = sum
			local w = Components.text({
				text = ExpandInfo.WORD[cur.kind] or cur.kind,
				size = 23,
				color = C.inkDark,
				font = Tokens.font.display,
			})
			w.LayoutOrder = 2
			w.Parent = sum
			local function valueLine(order: number, now: number, nextV: number?, prefix: string)
				local line: Frame = new("Frame", {
					Name = "Value" .. order,
					LayoutOrder = order,
					Size = UDim2.fromOffset(0, 56),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					[CHILDREN] = {
						new("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0, 10),
						}),
					},
					Parent = sum,
				})
				WarehouseCommon.pill(prefix, tostring(now), 25).Parent = line
				if nextV then
					local up = Components.text({
						text = "▲" .. (nextV - now),
						size = 25,
						color = C.up,
						font = Tokens.font.number,
					})
					up.Parent = line
				end
			end
			if cur.kind == "trainingLevel" then
				local fac = master.K.trainingFacility
				local nowF = fac[cur.current]
				local nextF = if cur.step then fac[cur.step.value] else nil
				valueLine(3, nowF.levelCap, if nextF then nextF.levelCap else nil, "Lv")
				valueLine(4, nowF.expPerSession, if nextF then nextF.expPerSession else nil, "XP")
			else
				valueLine(3, cur.current, if cur.step then cur.step.value else nil, "")
			end
		end
		-- 右下：買う（ハンマー＋費用）
		local actions = Screen.actionRow(body)
		local buy = Components.button({
			kind = if cur and cur.canBuy then "gold" else "disabled",
			width = 320,
			icon = "🔨",
			label = Words.expand,
			cost = if cur and cur.step then HubState.formatNumber(cur.step.gold) else nil,
			name = "Buy",
			glyph = "A",
			-- 灰色でも押せて、何をすれば押せるかを1行・2秒（ギルドLv・踏破・お金：D-264 ②）
			reason = if cur and not cur.canBuy then ExpandInfo.blockReason(cur, master) else nil,
			onClick = function()
				if busy or not (cur and cur.canBuy) then
					return
				end
				busy = true
				local gold = cur.step.gold
				local r = Session.sendAndWait({ type = "BuyExpansion", expansionId = cur.id })
				busy = false
				if r and r.ok then
					spent = gold
					task.delay(2.5, function()
						spent = nil
						if body.Parent then
							render()
						end
					end)
				end
				render()
			end,
		})
		buy.LayoutOrder = 2
		buy.Parent = actions
	end

	render()
	local conn = Session.changed:connect(function()
		if not busy then
			render()
		end
	end)
	return {
		frame = frame,
		scrim = 1,
		destroy = function()
			conn.disconnect()
		end,
	}
end

Nav.register("Expand", build)

return {}
