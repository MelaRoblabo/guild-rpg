--!strict
-- テキストの書式 → コマンド（09章 §1、11章 §5）
-- テキスト版（tools/cli）と Roblox のデバッグ画面（src/client）で共通に使う。状態を変えるコマンドだけを扱い、
-- 表示用の書式（status・roster など）は呼び出し側が持つ。Roblox API は使わない。

local CommandText = {}

-- train の「max」で送る回数（Protocol の上限と同じ。上限レベルかゴールド切れで止まる）
CommandText.TRAIN_MAX = 100000

CommandText.HELP = [[
  party <n> <隊列1-4> <adv_uid|->   パーティに配置／外す
  equip <adv_uid> <eq_uid>   装備する
  unequip <adv_uid> <weapon|armor|sub>  外す
  go <n> <dng_id>            派遣
  repeat <n> <dng_id|off>    自動再派遣の設定
  open <山> [個数]           その宝箱の山をまとめて開ける（山はダンジョンIDか special:<種類>。省略時 最大100個）
  sellweak [eq_uid...]       開封結果のうち今の装備より弱いものを一括売却（テキスト版は省略で直前の開封結果）
  sell <eq_uid...>           装備を売る
  sell item <itm_id> [個数]   アイテムを売る
  lock <uid> / unlock <uid>  保護の切り替え
  hire                       雇用を始める（雇用費を支払い候補を表示）
  pick <番号>                面接する候補を選ぶ（ステータスを抽選）
  reroll                     ステータスを引き直す（無料回数→チケット）。今回の結果が「前回」になり、それより前は消える
  choose <prev|cur>          採用する結果を選んで雇用する
  cancel                     雇用をやめる（雇用費は戻らない）
  rename <adv_uid> <名前>    名前を変える
  dismiss <adv_uid>          解雇する
  rebirth <adv_uid>          転生を始める（見た目は確定の後に選ぶ）
  rb-reroll                  転生スロットを引き直す（今回が「前回」になり、それより前は消える）
  rb-choose <prev|cur>       転生スロットの結果を確定する（新しい見た目を引く）
  rb-look <prev|cur>         転生の見た目を選ぶ（prev＝見た目維持ポーションで前の姿、cur＝新しい姿）
  jobchange <adv_uid> <job_id>   転職ポーションで転職する
  looks <adv_uid>            見た目変更ポーションを使う
  looks-choose <prev|cur>    見た目を選ぶ（prev＝今の姿、cur＝新しい姿）
  expand <exp_id>            拡張を買う（トレーニング場もここ）
  train <adv_uid> [回数|max] トレーニング（ゴールドで経験値。既定1回）
  autosell <on|off> [最大レアリティ] [keep|all]  自動売却（keep＝修飾語つきは残す）
  claim                      受け取り箱の中身をまとめて受け取る（受け取れないものは残る）
  qclaim <daily|weekly> <id> 達成したクエストの報酬を受け取る（D-286）
  qbonus <daily|weekly>      クエストを全部達成したボーナスを受け取る（D-286）
  haul <party>               帰還の獲得の吹き出しを消す（D-287）
  friend [人数]              フレンドボタン（友達の数はサーバーが数える。テキスト版は引数で与える。既定1：D-157）
  eventgo <n> [時間帯]       今のマップイベント（レアダンジョン・レイドボス）へパーティを出す（時間帯は省略で今の時間帯）
  buy <番号> [時間帯]        旅の商人の品を買う（時間帯は省略で今の時間帯）]]

function CommandText.tokens(line: string): { string }
	local t = {}
	for w in string.gmatch(line, "%S+") do
		table.insert(t, w)
	end
	return t
end

local function which(word: string?): string?
	if word == "prev" then
		return "previous"
	elseif word == "cur" then
		return "current"
	end
	return word
end

-- トークン列をコマンドにする。状態を変えるコマンドでなければ nil
function CommandText.fromTokens(tokens: { string }): any?
	local c = tokens[1]
	if c == "party" then
		local uid = tokens[4]
		return {
			type = "SetPartySlot",
			partyIndex = tonumber(tokens[2]),
			slot = tonumber(tokens[3]),
			adventurerUid = if uid == "-" then nil else uid,
		}
	elseif c == "equip" then
		return { type = "Equip", adventurerUid = tokens[2], equipmentUid = tokens[3] }
	elseif c == "unequip" then
		return { type = "Unequip", adventurerUid = tokens[2], slot = tokens[3] }
	elseif c == "go" then
		return { type = "Dispatch", partyIndex = tonumber(tokens[2]), dungeonId = tokens[3] }
	elseif c == "repeat" then
		return {
			type = "SetAutoRepeat",
			partyIndex = tonumber(tokens[2]),
			dungeonId = if tokens[3] == "off" then nil else tokens[3],
		}
	elseif c == "open" then
		return { type = "OpenChests", pileKey = tokens[2], count = tonumber(tokens[3]) }
	elseif c == "sellweak" then
		-- 対象は開封結果に出た装備（D-167）。uid を省いたときは呼び出し側が直前の開封結果で埋める
		return { type = "BulkSell", equipmentUids = table.move(tokens, 2, #tokens, 1, {}) }
	elseif c == "sell" then
		if tokens[2] == "item" then
			return { type = "Sell", itemId = tokens[3], count = tonumber(tokens[4]) or 1 }
		end
		return { type = "Sell", equipmentUids = table.move(tokens, 2, #tokens, 1, {}) }
	elseif c == "lock" or c == "unlock" then
		return { type = "SetLock", uid = tokens[2], locked = c == "lock" }
	elseif c == "hire" then
		return { type = "HireStart" }
	elseif c == "pick" then
		return { type = "HirePick", candidateIndex = tonumber(tokens[2]) }
	elseif c == "reroll" then
		return { type = "HireReroll" }
	elseif c == "choose" then
		return { type = "HireChoose", which = which(tokens[2]) }
	elseif c == "cancel" then
		return { type = "HireCancel" }
	elseif c == "rename" then
		return { type = "Rename", adventurerUid = tokens[2], name = tokens[3] }
	elseif c == "dismiss" then
		return { type = "Dismiss", adventurerUid = tokens[2] }
	elseif c == "rebirth" then
		return { type = "RebirthStart", adventurerUid = tokens[2] }
	elseif c == "rb-reroll" then
		return { type = "RebirthReroll" }
	elseif c == "rb-choose" then
		return { type = "RebirthChoose", which = which(tokens[2]) }
	elseif c == "rb-look" then
		return { type = "RebirthAppearanceChoose", which = which(tokens[2]) } -- D-230
	elseif c == "jobchange" then
		return { type = "ChangeJob", adventurerUid = tokens[2], jobId = tokens[3] }
	elseif c == "looks" then
		return { type = "ChangeAppearance", adventurerUid = tokens[2] }
	elseif c == "looks-choose" then
		return { type = "ChangeAppearanceChoose", which = which(tokens[2]) }
	elseif c == "expand" then
		return { type = "BuyExpansion", expansionId = tokens[2] }
	elseif c == "unlock" then
		return { type = "UnlockDungeon", dungeonId = tokens[2] } -- D-279
	elseif c == "train" then
		local n = if tokens[3] == "max" then CommandText.TRAIN_MAX else tonumber(tokens[3]) or 1
		return { type = "Train", adventurerUid = tokens[2], sessions = n }
	elseif c == "claim" then
		return { type = "ClaimInbox" }
	elseif c == "qclaim" then
		return { type = "ClaimQuest", period = tokens[2], questId = tokens[3] } -- D-286
	elseif c == "qbonus" then
		return { type = "ClaimQuestBonus", period = tokens[2] } -- D-286
	elseif c == "haul" then
		return { type = "AckHaul", partyIndex = tonumber(tokens[2]) } -- D-287
	elseif c == "friend" then
		-- 友達の数はコマンドに入れない（サーバーが数えて ctx.friendCount で渡す。テキスト版は呼び出し側が引数を ctx に入れる）
		return { type = "ClaimFriendReward" }
	elseif c == "eventgo" then
		-- 時間帯を省いたときは呼び出し側が今の時間帯（Game.query.mapEvent）で埋める（D-152）
		return { type = "DispatchEvent", partyIndex = tonumber(tokens[2]), eventSlot = tonumber(tokens[3]) }
	elseif c == "buy" then
		return { type = "BuyFromMerchant", itemIndex = tonumber(tokens[2]), eventSlot = tonumber(tokens[3]) }
	elseif c == "leave" then
		return { type = "LeaveMerchant", partyIndex = tonumber(tokens[2]) } -- D-274
	elseif c == "autosell" then
		return {
			type = "SetAutoSell",
			enabled = tokens[2] == "on",
			maxRarity = tonumber(tokens[3]),
			keepModified = tokens[4] ~= "all",
		}
	end
	return nil
end

function CommandText.parse(line: string): any?
	return CommandText.fromTokens(CommandText.tokens(line))
end

return CommandText
