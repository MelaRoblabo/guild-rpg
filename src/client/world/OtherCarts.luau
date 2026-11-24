--!strict
-- 他のプレイヤーの馬車の位置とまとめ方（D-026・D-108・D-127・D-213 ⑮、11章（システム）§6.1）。純粋な関数（Lune でテストする）。
--   position：公開情報（departAt・travelSeconds・totalSeconds）と今の時刻から、
--     行き（moving、along 0→1）・ダンジョンの中（exploring、along 1）・帰り（returning、along 1→0）。帰ったら nil。
--   cluster：近くに重なる馬車を1つにまとめる（「＋3」：D-127）。並びの最初の馬車の位置に置く。

local OtherCarts = {}

export type Pos = { state: "moving" | "exploring" | "returning", along: number }

function OtherCarts.position(p: any, now: number): Pos?
	local t = now - p.departAt
	local travel = math.max(p.travelSeconds, 1)
	if t >= p.totalSeconds then
		return nil
	end
	if t < travel then
		return { state = "moving", along = math.max(t, 0) / travel }
	end
	local backFrom = p.totalSeconds - travel
	if t < backFrom then
		return { state = "exploring", along = 1 }
	end
	return { state = "returning", along = 1 - (t - backFrom) / travel }
end

export type Point = { x: number, y: number, key: any }
export type Group = { x: number, y: number, keys: { any } }

-- points の順に見て、すでにあるまとまりの中心から radius 以内なら同じまとまりへ入れる
function OtherCarts.cluster(points: { Point }, radius: number): { Group }
	local groups: { Group } = {}
	for _, p in points do
		local joined = false
		for _, g in groups do
			local dx, dy = p.x - g.x, p.y - g.y
			if dx * dx + dy * dy <= radius * radius then
				table.insert(g.keys, p.key)
				joined = true
				break
			end
		end
		if not joined then
			table.insert(groups, { x = p.x, y = p.y, keys = { p.key } })
		end
	end
	return groups
end

return OtherCarts
