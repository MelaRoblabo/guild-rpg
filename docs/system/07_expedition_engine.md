# 07 探索エンジン

`Expedition.simulate(input, master) -> ExpeditionLog` は探索1回分を最後まで計算する純粋関数。M1の中心。

## 1. 入力

```lua
input = {
	seed: number,
	departAt: number,
	dungeonId: string,
	members: { MemberSnapshot },   -- 隊列1〜4の順。出発時点の実効値を固定したもの
	dailyTraitId: string?,         -- 出発時刻の日に当たっている日替わりの特性（D-156、06章 §16）
	timeMult: number?,             -- 所要秒の倍率。留守番は offlineTimeMult（10）、それ以外は 1（D-161）
}
MemberSnapshot = { uid, jobId, attackType, heals, maxHp, atk, pdef, mdef, agi, dex, giftIds, modifiers }
```

出発時点で実効値を計算して固定する（探索中に装備等は変えられないため）。日替わりの特性も出発時に決めて固定する（探索中に日が変わっても変えない：D-156）。

## 2. 手順

```
rng = Rng.new(seed)
hp[i] = maxHp[i]（全員満タンで出発）
battleIndex = 0
for floor = 1 .. dungeon.floors:
    if floor が奇数:                                   -- D-001
        battleIndex += 1
        monster = 出現リストから抽選（最終フロアはボスリスト）、強さ倍率を適用   -- D-002, D-003
        Combat.run(...)  → ターンごとの行動を log に追記
        勝利: 経験値・ゴールドを記録（経験値は生存者で等分）                 -- D-012, D-041
        全滅 or 30ターン: 撤退 → ループを抜ける                           -- D-009, D-013
    else:
        Events.run(...) → 宝箱／アイテム／罠／泉／なし                     -- D-014〜D-018
        罠で全滅: 撤退 → ループを抜ける
    宝箱を確保したら幸運の判定                                            -- D-019
最終フロアまで攻略したら 踏破：確定宝箱1個（＋幸運判定）                   -- D-019
所要時間を計算（06章 §7）
```

### 戦闘1回（Combat.run）

```
for turn = 1 .. maxTurns:
    生存者を実効agi降順（同値は隊列順）に並べる
    for 各生存者:
        支援系で回復条件を満たす → 回復（06章 §4）
        それ以外 → 攻撃（クリティカル判定 → ダメージ）
        モンスターHP <= 0 → 勝利
    モンスターの攻撃：被弾対象を抽選 → ダメージ
    生存者 0 → 全滅
30ターン経過 → 撤退
```

## 3. 乱数の消費順（固定）

再現性のため、乱数を引く順番を固定する。順番を変えると同じシードでも結果が変わるので、変更する場合はログ形式の `engineVersion` を上げる。

1. フロアごとに：（戦闘）モンスター抽選 → ターン内の各行動のクリティカル判定 → モンスターの被弾対象抽選
2. （イベント）イベント種別 → 種別ごとの抽選（宝箱ランク／アイテム／罠の回避判定）→ 幸運判定
3. 踏破時：確定宝箱ランク → 幸運判定

## 4. 探索ログ（ExpeditionLog）

```lua
ExpeditionLog = {
	engineVersion: number,
	result: "clear" | "retreat",
	reachedFloor: number,           -- 最後に到達したフロア
	travelSeconds: number,          -- 片道
	floors: { FloorLog },
	rewards: {
		exp: { [uid]: number },
		gold: number,
		chests: { { rank: number } },        -- 中身は開封時に抽選（D-015）
		items: { [itemId]: number },
		guildExp: number,
	},
	totalSeconds: number,
}
FloorLog = {
	floor: number, kind: "battle" | "event", startOffset: number, duration: number,
	-- battle
	monsterId: string?, turns: { TurnLog }?, outcome: "win" | "wipe" | "timeout"?,
	-- event
	event: "chest" | "item" | "trap" | "fountain" | "none"?, detail: any?,
	hpAfter: { number },            -- フロア終了時の各メンバーのHP
	giftTriggers: { { uid: string, giftId: string } },   -- 発動したギフト（演出用）
}
```

- `startOffset` は出発からの経過秒（行きの移動を含む）。再生側はこれで「今どのフロアか」を求める。
- 報酬はログ確定時点で決まっているが、**状態への反映は帰還時（advance）**。
- 休息ボーナスの経験値の倍率（D-161）はログに入れず、帰還時（advance）に残りを見て掛ける（06章 §14）。

## 4b. 留守番・日替わり・マップイベント（D-152, D-156, D-161）

- **留守番の探索**：`input.timeMult = offlineTimeMult` で同じ `simulate` を使う。戦闘・イベント・報酬は普通の探索と同じで、`travelSeconds`・各フロアの `startOffset`/`duration`・`totalSeconds` だけを倍率で伸ばす。`Expedition.offline = true` の印を付け、クエストに数えない（D-153, D-161）。
- **途中でログインしたとき**：6時間より前にログインしたら、まだ帰っていない留守番の探索はログインの時点で帰還させる。結果（ログの報酬）は出発時に決まっているので、そのまま受け取る。再生位置（§5）は使わず、全員ギルドで待機にそろえる（D-172）。
- **日替わりの特性**：`dailyTraitId` の効果を出発時の計算に入れる（攻撃力・移動時間は MemberSnapshot・片道秒の計算で、宝箱の数は報酬の計算で。06章 §16）。攻撃力は個体補正の上限の外で掛ける（D-173）。経験値の倍率は休息ボーナスと同じく帰還時に掛ける。留守番も出発した日の特性を当てる。
- **専用ギフトのパーティ効果**：移動・宝箱の数に効く。同じ効果はパーティ内で重ねない（06章 §21、D-174）。
- **レアダンジョン**：踏破済みの一番深いダンジョンのデータで計算し、宝箱の数に `rareDungeonChestMult` を掛け、宝箱の山は `special:rare:<相当するダンジョン>`（1段上のダンジョン。D-152, D-166, D-171）。
- **レイドボス**：パーティのダメージは出発時に計算して `Expedition.raidDamage` に保存し、到着時刻（advance）に合計へ入れる。結果は出発時に決まる（D-152）。ダメージの式は M7b-6 で決める（D-179）。
- 攻撃力・移動時間・経験値・所要秒の倍率は乱数を使わない。宝箱の数を増やす効果（`chestMult`・`rareDungeonChestMult`・専用ギフト）は端数を確率で切り上げる（宝箱1個あたり (倍率 − 1) の確率で +1：D-173）ので乱数の消費順が変わる。入れるときは `engineVersion` を上げ、§3 に順番を書き足す。

## 5. 再生位置の計算（Expedition.progressAt）

```
t = now − departAt
t < travelSeconds                      → 行きの移動中（進捗率）
t < travelSeconds + 再生秒              → floors から startOffset で該当フロアを探す
t < totalSeconds                       → 帰りの移動中
それ以外                                → 帰還済み
```
