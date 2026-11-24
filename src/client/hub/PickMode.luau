--!strict
-- 行き先を選ぶ形（D-231 ⑦：S-12 の金 → マップで選ぶ → S-15 の面で Go）。
--   PickMode.start(partyIndex) でマップが「行き先を選ぶ」の形になり、ダンジョンを触ると S-15 がパーティからの形で開く。
--   Go するか、選ぶのをやめる（× や別の画面）と PickMode.stop() で戻る。

local Signal = require("../ui/Signal")

local PickMode = {}

PickMode.partyIndex = nil :: number?
PickMode.changed = Signal.new()

function PickMode.start(partyIndex: number)
	PickMode.partyIndex = partyIndex
	PickMode.changed:fire()
end

function PickMode.stop()
	if PickMode.partyIndex ~= nil then
		PickMode.partyIndex = nil
		PickMode.changed:fire()
	end
end

return PickMode
