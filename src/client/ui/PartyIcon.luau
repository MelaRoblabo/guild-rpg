--!strict
-- パーティのアイコン（D-271）：リーダーの顔の丸と、右上の動く状態の印。
--   待機（ギルド）＝Zzz（後ろの「.」が増えたり減ったり）、移動中・帰り道＝歩く人（歩く動き）、探索中＝剣（ぶつかる動き）。
--   左のパーティ一覧・マップの BillboardGui・パーティの面の題・出発の一覧で同じ形を使う。

local RunService = game:GetService("RunService")

local Party = require("@game/ReplicatedStorage/Core/Party")
local Components = require("./Components")
local Create = require("./Create")
local Portrait = require("./Portrait")
local Tokens = require("./Tokens")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local PartyIcon = {}

-- 動かす印（作り直しで消えたものは自然に外れる）
local badges: { [TextLabel]: string } = setmetatable({}, { __mode = "k" }) :: any

-- パーティの名前（「リーダー名's Party」：D-271 ②）
function PartyIcon.name(view: any, partyIndex: number): string
	local uid = view and Party.leader(view, partyIndex)
	local adv = uid and view.adventurers[uid]
	if adv then
		return adv.name .. "'s Party"
	end
	return "Party " .. partyIndex
end

-- 丸いアイコンを作る。size は直径。戻り値の枠に Set で中身を入れる
function PartyIcon.make(size: number): Frame
	local f: Frame = new("Frame", {
		Name = "PartyIcon",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = C.ch13,
		[CHILDREN] = {
			Components.corner(size / 2),
			Components.stroke(C.bronze, math.max(2, math.floor(size / 24))),
		},
	})
	new("Frame", {
		Name = "Face",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		[CHILDREN] = { Components.corner(size / 2) },
		Parent = f,
	})
	local badgeSize = math.max(22, math.floor(size * 0.46))
	new("TextLabel", {
		Name = "State",
		Text = "",
		TextSize = math.max(14, math.floor(badgeSize * 0.62)),
		FontFace = Tokens.font.number,
		TextColor3 = C.inkLight,
		BackgroundColor3 = C.ch10,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -badgeSize * 0.15, 0, badgeSize * 0.15),
		Size = UDim2.fromOffset(badgeSize * 1.5, badgeSize),
		ZIndex = 5,
		[CHILDREN] = { Components.corner(badgeSize / 2), Components.stroke(C.bronze, 2) },
		Parent = f,
	})
	return f
end

-- 中身を入れる：リーダーの顔と状態の印（state は HubState.status の state）
function PartyIcon.set(f: Frame, view: any, partyIndex: number, state: string?)
	local uid = view and Party.leader(view, partyIndex)
	local adv = uid and view.adventurers[uid]
	local face = f:FindFirstChild("Face") :: Frame
	if face:GetAttribute("Uid") ~= (uid or "") then
		face:SetAttribute("Uid", uid or "")
		for _, c in face:GetChildren() do
			if not c:IsA("UICorner") then
				c:Destroy()
			end
		end
		if not (adv and Portrait.fill(face, adv.appearanceId)) then
			local t = Components.text({
				text = tostring(partyIndex),
				size = 21,
				color = C.inkLight,
				font = Tokens.font.display,
			})
			t.AutomaticSize = Enum.AutomaticSize.None
			t.Size = UDim2.fromScale(1, 1)
			t.Parent = face
		end
	end
	local badge = f:FindFirstChild("State") :: TextLabel
	badge.Visible = state ~= nil
	if state then
		badges[badge] = state
	end
end

-- 状態の印の動き
local function animate(badge: TextLabel, state: string, t: number)
	if state == "waiting" then
		-- Zzz の後ろの「.」が 0→3 と増えて戻る
		local n = math.floor(t * 2.5) % 4
		badge.Text = "Zzz" .. string.rep(".", n)
		badge.Rotation = 0
		badge.TextTransparency = 0
	elseif state == "exploring" then
		-- 剣がぶつかる：小刻みに傾いて弾む
		badge.Text = "⚔"
		local k = math.sin(t * 9)
		badge.Rotation = if k > 0 then 18 * k else 6 * k
		badge.TextTransparency = 0
	else
		-- 歩く：左右に体を揺らす
		badge.Text = "🚶"
		badge.Rotation = math.sin(t * 7) * 10
		badge.TextTransparency = 0
	end
end

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for badge, state in badges do
		if badge.Parent == nil then
			badges[badge] = nil
		elseif badge.Visible then
			animate(badge, state, t)
		end
	end
end)

return PartyIcon
