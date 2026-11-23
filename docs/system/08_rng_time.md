# 08 乱数と時刻

## 1. 乱数（Rng.luau）

Roblox の `Random` と `math.random` は使わない（Luneと結果が一致せず、シード管理もできないため）。自前の決定的な乱数を使う。

- アルゴリズム：xoshiro128**（32bit）。シードから状態4語を splitmix32 で作る。
- 実装は `bit32` のみで行う。32bit同士の乗算は16bitに分割して計算する（倍精度の丸めで結果がずれるのを防ぐ）。
- テスト：既知のシードに対する先頭10個の出力を固定値として検証する（Roblox上でも同じ値になること）。

```lua
Rng.new(seed: number) -> Rng
rng:nextU32() -> number           -- 0 .. 2^32-1
rng:float() -> number             -- [0, 1)
rng:int(min, max) -> number       -- 両端を含む
rng:chance(p) -> boolean
rng:pickWeighted(entries, weightKey) -> entry
Rng.derive(baseSeed, counter) -> number   -- 状態シードと回数から新しいシードを作る（splitmix32）
```

## 2. 乱数の払い出し

- プレイヤー状態に `seed`（作成時に1回だけ決める）と `rngCounter` を持つ。
- 乱数を使うコマンドは `Rng.new(Rng.derive(state.seed, state.rngCounter))` を作り、使い終わったら `rngCounter += 1`。
- 探索は払い出したシードを `Expedition.seed` に保存し、ログの再計算・検証ができるようにする。
- 面接・転生の結果はセッション（`hireSession` / `rebirthSession`）に保存する。再接続しても結果は変わらない。

## 3. 時刻

- `src/core` は時刻を取得しない。`ctx.now`（Unix秒、整数）を受け取るだけ。
- CLI・自動プレイヤーは仮想時計を持ち、`wait <秒>`・`days <日数>` で進める（09章）。
- Robloxサーバーは `os.time()` を `ctx.now` に渡す（M7）。
- 時間の単位は全体で秒。ミリ秒は使わない。

## 4. 日・週の番号（D-168）

- 日・週で区切る処理（クエスト・プレイ時間・ログインボーナス・日替わり・今週の訪問者）は、`src/core/Calendar.luau` が `ctx.now` から出す日の番号（`dayIndex`）・週の番号（`weekIndex`）だけを使う。`os.time`・`os.date` は使わない。式は 06章 §11。
- 日の区切りは UTC 0時（日本の朝9時）、週の始まりは月曜。全員共通（D-168）。

## 5. 全員共通の乱数（D-156, D-158, D-152, D-184）

- 日替わりの特性・今週の訪問者・マップイベントの種類と場所は、プレイヤーの `seed` ではなく `Constants.calendarSeed` と日・週・時間帯の番号から `Rng.new(Rng.derive(calendarSeed, 番号))` で作る。どのサーバー・どのプレイヤーでも同じ結果になり、サーバー全体の状態を持たない。
- マップイベントの中身（ボスのHP・商人の品）はプレイヤーごとで、`Rng.derive(state.seed, eventSlot)` から作る。どちらも `rngCounter` は進めない（同じ時間帯なら何度計算しても同じ結果）。
