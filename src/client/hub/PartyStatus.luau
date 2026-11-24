--!strict
-- パーティが今何をしているか・ピンチかどうか（D-212・D-214、11章 S-10）。
-- Roblox API を使わない純粋な関数（tests/ から Lune でテストする）。進み具合は core の
-- Expedition.progressAt を引数で受け取る（クライアントは @game、テストは相対パスで渡す）。

local PartyStatus = {}

export type State = "waiting" | "moving" | "exploring" | "returning"

export type Status = {
	state: State,
	dungeonId: string?,
	along: number, -- ギルド（0）→ダンジョン（1）の道のりの位置。帰りは 1 → 0
	floorIndex: number?, -- 探索中のフロア
	floors: number?, -- 探索するフロアの数（ログのフロア数）
	pinch: boolean,
	downCount: number,
	hp: { number }?, -- 今の時点のメンバーの HP（隊列順。ログのメンバー順）
	returnAt: number?,
}

export type Progress = { phase: string, ratio: number, floorIndex: number? }

-- 今の時点のメンバーの HP（終わったフロアのうち最後の hpAfter。まだ戦っていなければ nil＝満タン）
function PartyStatus.hpAt(log: any, now: number): { number }?
	local t = now - log.departAt
	local hp = nil
	for _, f in log.floors or {} do
		if f.startOffset + f.duration <= t then
			hp = f.hpAfter
		else
			break
		end
	end
	return hp
end

-- expedition：そのパーティの探索（なければ nil＝待機）。maxHp：メンバーの最大 HP（隊列順）。
-- pinchHpRatio：パーティの HP の割合がこれより低いとピンチ（マスターデータ。なければ戦闘不能だけで判定）
function PartyStatus.compute(
	expedition: any?,
	now: number,
	progressAt: (log: any, now: number) -> Progress,
	maxHp: { number },
	pinchHpRatio: number?
): Status
	if expedition == nil or expedition.collected then
		return { state = "waiting", along = 0, pinch = false, downCount = 0 }
	end
	local log = expedition.log
	local p = progressAt(log, now)
	local s: Status = {
		state = "waiting",
		dungeonId = expedition.dungeonId,
		along = 0,
		floors = #(log.floors or {}),
		pinch = false,
		downCount = 0,
		returnAt = expedition.returnAt,
	}
	if p.phase == "outbound" then
		s.state, s.along = "moving", p.ratio
	elseif p.phase == "floor" then
		s.state, s.along, s.floorIndex = "exploring", 1, p.floorIndex
	elseif p.phase == "inbound" then
		s.state, s.along = "returning", 1 - p.ratio
	else
		s.state, s.along = "waiting", 0
		return s -- 帰ってきた（受け取りはサーバーが行う）
	end
	local hp = PartyStatus.hpAt(log, now)
	s.hp = hp
	if hp then
		local sum, total = 0, 0
		for i, h in hp do
			local m = maxHp[i] or 0
			if m > 0 and h <= 0 then
				s.downCount += 1
			end
			sum += math.max(h, 0)
			total += m
		end
		local low = pinchHpRatio ~= nil and total > 0 and sum / total < pinchHpRatio
		-- 帰り道はもう戦わないので、ピンチの印は出さない（見る理由がない：D-214 ①）
		s.pinch = s.state ~= "returning" and (s.downCount > 0 or low)
	end
	return s
end

return PartyStatus
