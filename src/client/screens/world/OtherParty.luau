--!strict
-- S-14 他のプレイヤーのパーティの詳細（D-108・D-121・D-151、11章（システム）§6.2）。マップの他人の馬車を触ると開く。見るだけ。
--   - 羊皮紙の面（パーティの面と同じ位置・暗幕50%：D-225 ③）。× は面の右上の角。
--   - 上の段：プレイヤーのアバターの顔・表示名・ギルドLv。重なった馬車（「＋N」）なら、顔の札で切り替える。
--   - 中の段：向かっているダンジョン（番号と名前）と状態（行き▶・中●・帰り◀）と、帰るまでの残り時間。
--   - 下の段：メンバー（顔・名前・職業・Lv）。中身は Inspect（読み取り専用のコマンド）でサーバーに聞く。
--   - 相手が退出した・帰ったなど NOT_FOUND なら閉じる。プレイヤー名とアバターは Roblox の API で取る（サーバーからは送らない）。

local Players = game:GetService("Players")

local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Portrait = require("../../ui/Portrait")
local Nav = require("../../ui/Nav")
local OtherCarts = require("../../world/OtherCarts")
local Root = require("../../ui/Root")
local Session = require("../../Session")
local Tokens = require("../../ui/Tokens")
local master = require("../../Master")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local PANEL_W, PANEL_H = 720, 470
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII" }
local STATE_GLYPH = { moving = "@cart_moving", exploring = "@cart_exploring", returning = "@cart_returning" }

local names: { [number]: string } = {}

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local p = Players:GetPlayerByUserId(userId)
	if p then
		names[userId] = p.DisplayName
		return p.DisplayName
	end
	local ok, n = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	names[userId] = if ok then n else "?"
	return names[userId]
end

local thumbs: { [string]: string } = {}

-- アバターの顔を画像に入れる（取れるまで待たない。取れたら入れる）
local function setThumb(target: ImageLabel | ImageButton, userId: number, size: Enum.ThumbnailSize)
	local key = `{userId}:{size.Name}`
	if thumbs[key] then
		target.Image = thumbs[key]
		return
	end
	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, size)
		end)
		thumbs[key] = if ok then url else ""
		if target.Parent then
			target.Image = thumbs[key]
		end
	end)
end

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 3600 then
		return string.format("%d:%02d:%02d", s // 3600, (s // 60) % 60, s % 60)
	end
	return string.format("%d:%02d", s // 60, s % 60)
end

local function hrow(parent: GuiObject, order: number, height: number, bg: Color3?): Frame
	return new("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = bg or C.ch75,
		BackgroundTransparency = if bg then 0 else 1,
		[CHILDREN] = {
			Components.corner(8),
			Components.padding(0, 14, 0, 14),
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 12),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
		Parent = parent,
	})
end

local function build(params: any?, api: Nav.Api): Nav.Built
	local list = (params :: any).list :: { { userId: number, partyIndex: number } }
	local pick = 1
	local band = Root.bandBottom()
	local frame: Frame = new("Frame", {
		Name = "OtherParty",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	local panel, content = Components.panel({
		size = UDim2.fromOffset(PANEL_W, PANEL_H),
		position = UDim2.fromOffset(196, band + 40),
	})
	panel.Name = "Panel"
	panel.Parent = frame
	local close = Components.closeButton(api.close)
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.fromOffset(196 + PANEL_W - 12, band + 40 + 12)
	close.ZIndex = 20
	close.Parent = frame
	local body: Frame = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = content,
	})
	local alive = true
	local detail: any = nil
	local render: () -> ()

	local function fetch()
		local who = list[pick]
		detail = nil
		local r = Session.send({ type = "Inspect", userId = who.userId, partyIndex = who.partyIndex })
		if not alive then
			return
		end
		if r == nil or not r.ok then
			if #list > 1 then
				table.remove(list, pick)
				pick = 1
				fetch()
				return
			end
			api.close()
			return
		end
		detail = r.detail
		render()
	end

	render = function()
		body:ClearAllChildren()
		new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
		local who = list[pick]
		-- 上の段：顔・名前・ギルドLv（重なった馬車なら顔の札で切り替え）
		local top = hrow(body, 1, 84)
		local face: ImageLabel = new("ImageLabel", {
			Name = "Avatar",
			LayoutOrder = 1,
			Size = UDim2.fromOffset(72, 72),
			BackgroundColor3 = C.ch28,
			[CHILDREN] = { Components.corner(36), Components.stroke(C.bronze, 3) },
			Parent = top,
		})
		setThumb(face, who.userId, Enum.ThumbnailSize.Size150x150)
		local name =
			Components.text({ text = nameOf(who.userId), size = 25, color = C.inkDark, font = Tokens.font.display })
		name.Name = "PlayerName"
		name.LayoutOrder = 2
		name.Parent = top
		if detail then
			local lv = Components.chip(Components.icon.home, "Lv " .. detail.guildLevel, C.bronzeHi)
			lv.Name = "GuildLevel"
			lv.LayoutOrder = 3
			lv.Parent = top
		end
		if #list > 1 then
			local tabs: Frame = new("Frame", {
				Name = "Others",
				LayoutOrder = 4,
				Size = UDim2.fromOffset(0, 56),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				[CHILDREN] = {
					new("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 8),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				},
				Parent = top,
			})
			for i, w in list do
				local b: ImageButton = new("ImageButton", {
					Name = "Other" .. i,
					LayoutOrder = i,
					Size = UDim2.fromOffset(52, 52),
					BackgroundColor3 = C.ch28,
					AutoButtonColor = false,
					[CHILDREN] = {
						Components.corner(26),
						Components.stroke(if i == pick then C.selAmber else C.ch16, if i == pick then 4 else 2),
					},
					Parent = tabs,
				})
				setThumb(b, w.userId, Enum.ThumbnailSize.Size48x48)
				b.Activated:Connect(function()
					if i ~= pick then
						pick = i
						render()
						task.spawn(fetch)
					end
				end)
			end
		end
		if detail == nil then
			return
		end
		-- 中の段：行き先と状態・帰るまで
		local d = master.dungeons[detail.dungeonId]
		local where = hrow(body, 2, 70, C.ch68)
		where.Name = "Destination"
		local num: Frame = new("Frame", {
			LayoutOrder = 1,
			Size = UDim2.fromOffset(52, 52),
			BackgroundColor3 = C.ch16,
			[CHILDREN] = { Components.corner(26), Components.stroke(C.bronze, 3) },
			Parent = where,
		})
		local nt = Components.text({
			text = if d then ROMAN[d.tier] or tostring(d.tier) else "?",
			size = 23,
			color = C.inkLight,
			font = Tokens.font.display,
		})
		nt.AnchorPoint = Vector2.new(0.5, 0.5)
		nt.Position = UDim2.fromScale(0.5, 0.5)
		nt.Parent = num
		local dn = Components.text({
			text = if d then d.nameEn else detail.dungeonId,
			size = 23,
			color = C.inkDark,
			font = Tokens.font.display,
		})
		dn.LayoutOrder = 2
		dn.Parent = where
		local now = Session.now()
		local pos = OtherCarts.position(detail, now)
		local left = detail.departAt + detail.totalSeconds - now
		local st = Components.chip(if pos then STATE_GLYPH[pos.state] else "@cart_waiting", clock(left), C.inkLight)
		st.Name = "State"
		st.LayoutOrder = 3
		st.Parent = where
		-- 下の段：メンバー
		local grid: Frame = new("Frame", {
			Name = "Members",
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 1, -84 - 70 - 20),
			BackgroundColor3 = C.ch50,
			[CHILDREN] = {
				Components.corner(8),
				Components.padding(10, 10, 10, 10),
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 10),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
			Parent = body,
		})
		local n = math.max(#detail.members, 1)
		for i, m in detail.members do
			local job = master.jobs[m.jobId]
			local card: Frame = new("Frame", {
				Name = "Member" .. i,
				LayoutOrder = i,
				Size = UDim2.new(1 / n, -10 * (n - 1) / n, 1, 0),
				BackgroundColor3 = C.ch75,
				[CHILDREN] = {
					Components.corner(8),
					Components.padding(12, 8, 12, 8),
					new("UIListLayout", {
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						Padding = UDim.new(0, 8),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				},
				Parent = grid,
			})
			local f: Frame = new("Frame", {
				LayoutOrder = 1,
				Size = UDim2.fromOffset(84, 84),
				BackgroundColor3 = C.ch28,
				[CHILDREN] = { Components.corner(42), Components.stroke(C.ch16, 2) },
				Parent = card,
			})
			local g = Components.text({ text = Components.icon.party, size = 44, color = C.inkLight })
			g.AnchorPoint = Vector2.new(0.5, 0.5)
			g.Position = UDim2.fromScale(0.5, 0.5)
			g.Parent = f
			if Portrait.fill(f, m.appearanceId) then
				g.Visible = false
			end
			local function line(order: number, t: string, size: number, color: Color3, font: Font)
				local l = Components.text({ text = t, size = size, color = color, font = font })
				l.LayoutOrder = order
				l.AutomaticSize = Enum.AutomaticSize.Y
				l.Size = UDim2.fromScale(1, 0)
				l.TextWrapped = true
				l.Parent = card
			end
			line(2, m.name, 23, C.inkDark, Tokens.font.bodyStrong)
			line(3, if job then job.nameEn else m.jobId, 21, C.inkMid, Tokens.font.body)
			line(4, "Lv " .. m.level, 23, C.inkDark, Tokens.font.number)
		end
	end

	render()
	task.spawn(fetch)
	-- 帰るまでの残り時間を進める（札の文字だけ書き換える）
	task.spawn(function()
		while alive do
			task.wait(1)
			local st = body:FindFirstChild("State", true)
			if alive and detail and st then
				local labels = {}
				for _, c in st:GetChildren() do
					if c:IsA("TextLabel") then
						table.insert(labels, c)
					end
				end
				local now = Session.now()
				local pos = OtherCarts.position(detail, now)
				if labels[1] then
					Components.setText(labels[1], if pos then STATE_GLYPH[pos.state] else "@cart_waiting")
				end
				if labels[2] then
					labels[2].Text = clock(detail.departAt + detail.totalSeconds - now)
				end
			end
		end
	end)
	return {
		frame = frame,
		scrim = 0.5, -- パーティの面と同じ（D-225 ③）
		destroy = function()
			alive = false
		end,
	}
end

Nav.register("OtherParty", build)

return {}
