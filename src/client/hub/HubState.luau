--!strict
-- メイン画面とその上の面（パーティの面・ダンジョンの面）が共有する状態と計算。

local Expedition = require("@game/ReplicatedStorage/Core/Expedition")
local Game = require("@game/ReplicatedStorage/Core/Game")
local PartyStatus = require("./PartyStatus")
local Session = require("../Session")
local master = require("../Master")

local HubState = {}

-- 選んでいるパーティ（カメラが追う：D-212）
HubState.selected = nil :: number?
HubState.following = false

-- 全員が冒険中に雇った人（D-265 ②）。パーティに入れるか、帰還後の誘導で Edit Party を開くまで残す。
-- マップのギルドの建物に NEW の顔を付け、帰ってきたパーティの馬車 → Edit Party を一度だけ光らせる。
-- 保存はしない（この接続の間だけ）
HubState.newcomers = {} :: { [string]: boolean }
HubState.guildPoint = nil :: (() -> Vector2?)? -- 画面の上のギルドの位置（雇った人のカード・宝箱が飛ぶ：3D マップ D-270）

-- まだどのパーティにも入っていない、全員が冒険中に雇った人
function HubState.pendingNewcomers(view: any): { string }
	local out = {}
	for uid in HubState.newcomers do
		local inParty = false
		for _, p in (view and view.parties) or {} do
			if table.find(p.slots, uid) then
				inParty = true
			end
		end
		if view == nil or view.adventurers[uid] == nil or inParty then
			HubState.newcomers[uid] = nil
		else
			table.insert(out, uid)
		end
	end
	table.sort(out)
	return out
end

function HubState.dungeonIndex(id: string?): number?
	if id == nil then
		return nil
	end
	for i, d in master.dungeonList do
		if d.id == id then
			return i
		end
	end
	return nil
end

-- 解放済みで一番浅いダンジョン（行き先のない Go の行き先：D-244 ②）
function HubState.firstUnlocked(view: any): string?
	for _, d in master.dungeonList do
		if view.unlockedDungeons and view.unlockedDungeons[d.id] then
			return d.id
		end
	end
	return nil
end

-- そのパーティの状態（今何をしているか・ピンチ：D-212）
function HubState.status(view: any, partyIndex: number): PartyStatus.Status
	local e = Game.query.expeditionOf(view, partyIndex)
	local maxHp = {}
	local ok, snaps = pcall(Game.query.partySnapshots, view, partyIndex, master)
	if ok and type(snaps) == "table" then
		for i, s in snaps do
			maxHp[i] = s.maxHp or 0
		end
	end
	return PartyStatus.compute(e, Session.now(), Expedition.progressAt, maxHp, master.K.pinchHpRatio)
end

-- 残り時間の表示（分:秒。1時間以上は 時:分:秒）
function HubState.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	if s >= 3600 then
		return string.format("%d:%02d:%02d", s // 3600, (s // 60) % 60, s % 60)
	end
	return string.format("%d:%02d", s // 60, s % 60)
end

-- 3桁ごとのカンマ
function HubState.formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local sign = ""
	if string.sub(s, 1, 1) == "-" then
		sign, s = "-", string.sub(s, 2)
	end
	local out = ""
	while #s > 3 do
		out = "," .. string.sub(s, -3) .. out
		s = string.sub(s, 1, -4)
	end
	return sign .. s .. out
end

return HubState
