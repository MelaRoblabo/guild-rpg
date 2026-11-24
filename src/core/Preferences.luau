--!strict
-- 設定（S-61、D-117・D-145・D-237 ③。05章 SetSettings）
--   音量・開封演出・点滅を減らす・帰還のトースト・カットイン・他プレイヤーの馬車をサーバーに保存する（設定と一緒：D-117）。
--   保存がなければ StarterSet.preferences の初期値。
--   Preferences.get  今の設定（保存と初期値を合わせたもの）
--   Preferences.set  コマンドの値で書き換える（エラーコードか nil）

local Preferences = {}

Preferences.VOLUMES = { "musicVolume", "soundVolume" }
Preferences.SWITCHES = { "chestAnimation", "lessFlashing", "returnToast", "cutIns", "otherCarts" }

function Preferences.get(state: any, master: any): any
	local d = master.raw.StarterSet.preferences
	local s = (state.settings and state.settings.prefs) or {}
	local out = {}
	for _, k in Preferences.VOLUMES do
		out[k] = if type(s[k]) == "number" then s[k] else d[k]
	end
	for _, k in Preferences.SWITCHES do
		out[k] = if type(s[k]) == "boolean" then s[k] else d[k]
	end
	return out
end

-- 送られた項目だけを変える（省いた項目は今のまま）
function Preferences.set(state: any, cmd: any, master: any): string?
	for _, k in Preferences.VOLUMES do
		local v = cmd[k]
		if v ~= nil and (type(v) ~= "number" or v ~= math.floor(v) or v < 0 or v > master.K.volumeSteps) then
			return "INVALID_VOLUME"
		end
	end
	local cur = Preferences.get(state, master)
	for _, k in Preferences.VOLUMES do
		if cmd[k] ~= nil then
			cur[k] = cmd[k]
		end
	end
	for _, k in Preferences.SWITCHES do
		if cmd[k] ~= nil then
			cur[k] = cmd[k] == true
		end
	end
	state.settings = state.settings or {}
	state.settings.prefs = cur
	return nil
end

return Preferences
