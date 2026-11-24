--!strict
-- 画面の拡大縮小と置き場所の計算（D-210・D-219・D-221、Guild UI roblox.md）。
-- Roblox API を使わない純粋な関数だけを置く（tests/ から Lune でテストする：11章 §1）。
--
-- 考え方：
--   - 基準の画面は 1280×720。端末の安全な広さ（切り欠き・ホームバーを除いた広さ）に収まるよう、
--     縦横の比率の小さい方で全体を縮める（UIScale）。
--   - 押せる大きさの最小 66px（基準）が 36pt を下回らないよう、縮める比率に下限を置く（D-210）。
--   - 横長の端末では、基準の高さ 720 をそのまま使い、余った横幅は「画面の幅」に回す（部品は辺に止め、
--     余りは背景に回す。面を引き伸ばさない：D-221 ④）。縦長寄りの端末は逆に余った高さを回す。
--   - Roblox の上の帯（TopbarInset）は基準の上から tokens.base.topBand（106）を目安に空ける。
--     実際の帯が高い端末では、その高さ（基準に直した値）を使う（D-219）。

local Layout = {}

export type Insets = { top: number, bottom: number, left: number, right: number }

export type Frame = {
	scale: number, -- UIScale に入れる値
	width: number, -- 基準の単位での画面の幅（1280 以上になることがある）
	height: number, -- 基準の単位での画面の高さ（720 以上になることがある）
	offsetX: number, -- 安全な広さの左上（実際のピクセル）
	offsetY: number,
	topBand: number, -- 基準の単位での Roblox の帯の高さ（ここより下に押せるものを置く）
	clamped: boolean, -- 下限で止めた（はみ出しがある）
}

local BASE_W = 1280
local BASE_H = 720
local TAP_MIN_BASE = 66 -- tap-min（基準の px）
local TAP_MIN_PT = 36 -- 押せる大きさの最小（pt。D-210）

-- 押せる大きさを 36pt 以上に保つための、縮める比率の下限
function Layout.minScale(): number
	return TAP_MIN_PT / TAP_MIN_BASE
end

-- viewW・viewH：画面の大きさ（Roblox の GUI の単位）。safe：端末の欠け（切り欠き・ホームバー）。
-- topbarHeight：Roblox の上の帯の高さ（GUI の単位。TopbarInset.Height）。bandBase：基準の帯の高さ（106）。
function Layout.compute(viewW: number, viewH: number, safe: Insets, topbarHeight: number, bandBase: number): Frame
	local safeW = math.max(1, viewW - safe.left - safe.right)
	local safeH = math.max(1, viewH - safe.top - safe.bottom)
	local fit = math.min(safeW / BASE_W, safeH / BASE_H)
	local minScale = Layout.minScale()
	local scale = math.max(fit, minScale)
	local band = math.max(bandBase, topbarHeight / scale)
	return {
		scale = scale,
		width = safeW / scale,
		height = safeH / scale,
		offsetX = safe.left,
		offsetY = safe.top,
		topBand = band,
		clamped = fit < minScale,
	}
end

-- 基準の px を実際のピクセル（pt）に直す（確かめ用）
function Layout.toPoints(frame: Frame, basePx: number): number
	return basePx * frame.scale
end

return Layout
