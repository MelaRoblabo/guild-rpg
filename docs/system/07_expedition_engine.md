# 07 探索エンジン

`Expedition.simulate(input, master) -> ExpeditionLog` は探索1回分を最後まで計算する純粋関数。M1の中心。

## 1. 入力

```lua
input = {
	seed: number,
	departAt: number,
	dungeonId: string,
	members: { MemberSnapshot },   -- 隊列1〜4の順。出発時点の実効値を固定したもの
}
MemberSnapshot = { uid, jobId, attackType, heals, maxHp, atk, pdef, mdef, agi, dex, giftIds, modifiers }
```

出発時点で実効値を計算して固定する（探索中に装備等は変えられないため）。

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

## 5. 再生位置の計算（Expedition.progressAt）

```
t = now − departAt
t < travelSeconds                      → 行きの移動中（進捗率）
t < travelSeconds + 再生秒              → floors から startOffset で該当フロアを探す
t < totalSeconds                       → 帰りの移動中
それ以外                                → 帰還済み
```
