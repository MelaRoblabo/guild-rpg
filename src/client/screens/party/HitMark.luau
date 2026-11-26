--!strict
-- 隊列ごとの被弾率の印（D-284。率は D-005 の hitWeights をマスターデータから取る）。
--   文字や数字は出さず、的の形で見せる：よく狙われる隊列ほど的が大きく、輪が明るく、中心の赤が濃い。
--   大きさは面積が率に比例する（直径は率の平方根）。一番狙われる隊列の的を最大にする。
--   空いている隊列には的を出さない（D-005：入っている人だけで按分する。Combat.pickTarget と同じ重み）。
--   的は押せないので彩度を持たせない。奥行きは明るさの段で、差し色の赤は中心の小さな点だけ（D-222）。

local TweenService = game:GetService("TweenService")

local Components = require("../../ui/Components")
local Create = require("../../ui/Create")
local Tokens = require("../../ui/Tokens")

local C = Tokens.color
local new = Create.new
local CHILDREN = Create.Children

local HitMark = {}

-- 見た目の寸法（基準の画面の px。ゲームの数値ではない）
HitMark.MAX = 44 -- 一番狙われる隊列の的の直径
local GROW = 0.3 -- 大きさが変わるときの長さ（秒）

-- 埋まっている隊列だけで按分した被弾の割合（slot → 0〜1）。空いている隊列は入れない
function HitMark.shares(slots: { string }, weights: { number }, empty: string): { [number]: number }
	local total = 0
	for i, uid in slots do
		if uid ~= empty then
			total += weights[i] or 0
		end
	end
	local out: { [number]: number } = {}
	if total <= 0 then
		return out
	end
	for i, uid in slots do
		if uid ~= empty then
			out[i] = (weights[i] or 0) / total
		end
	end
	return out
end

-- 割合の中の一番大きい値
function HitMark.top(shares: { [number]: number }): number
	local top = 0
	for _, s in shares do
		top = math.max(top, s)
	end
	return top
end

-- 直径（面積が割合に比例。一番狙われる隊列が MAX）
function HitMark.diameter(share: number, top: number): number
	if top <= 0 then
		return 0
	end
	return math.floor(HitMark.MAX * math.sqrt(share / top) + 0.5)
end

-- 的を作る。t＝一番狙われる隊列に対する強さ（0〜1）。from を渡すとその直径から今の直径へ育つ
function HitMark.make(d: number, t: number, from: number?): Frame
	local ring = math.max(2, math.floor(d * 0.08 + 0.5))
	local mark: Frame = new("Frame", {
		Name = "HitMark",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(from or d, from or d),
		BackgroundColor3 = C.ch13, -- 暗い凹み
		Active = false,
		ZIndex = 4,
		[CHILDREN] = {
			Components.corner(999),
			Components.stroke(C.ch28:Lerp(C.ch68, t), 2),
			-- 輪：強いほど明るい
			new("Frame", {
				Name = "Ring",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.64, 0.64),
				BackgroundTransparency = 1,
				ZIndex = 4,
				[CHILDREN] = {
					Components.corner(999),
					Components.stroke(C.ch45:Lerp(C.inkLight, t), ring),
				},
			}),
			-- 中心の点：強いほど赤が濃い（差し色は小さく。危険の色 warn の暗い地用 warnDark。通知の赤 notice とは分ける）
			new("Frame", {
				Name = "Bull",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.28, 0.28),
				BackgroundColor3 = C.ch28:Lerp(C.warnDark, t),
				ZIndex = 5,
				[CHILDREN] = { Components.corner(999) },
			}),
		},
	})
	if from ~= nil and from ~= d then
		TweenService:Create(
			mark,
			TweenInfo.new(GROW, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(d, d) }
		):Play()
	end
	return mark
end

return HitMark
