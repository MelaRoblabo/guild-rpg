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
- CLI・自動プレイヤーは仮想時計を持ち、`wait <秒>` で進める。
- Robloxサーバーは `os.time()` を `ctx.now` に渡す（M7）。
- 時間の単位は全体で秒。ミリ秒は使わない。
