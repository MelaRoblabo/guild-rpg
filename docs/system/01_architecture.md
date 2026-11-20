# 01 全体構成

## 1. 層構造

```
┌──────────────────────────────────────────────────────────┐
│ 入口（Adapter）                                           │
│  tools/cli      テキスト版（人間・AIエージェントが遊ぶ）   │
│  tools/sim      探索シミュレーター（統計）                 │
│  tools/autoplay 自動プレイヤー（長時間の周回と指標集計）   │
│  src/server     Roblox サーバー（M7）                      │
│  src/client     Roblox クライアント・UI（M8）              │
└──────────────┬───────────────────────────────────────────┘
               │ Game.execute(state, command, ctx)
               │ Game.advance(state, ctx)
┌──────────────▼───────────────────────────────────────────┐
│ src/core  ゲームロジック（純粋Luau、Roblox API非依存）     │
│  Game（窓口）→ Hiring / Party / Expedition / Chest /       │
│  Inventory / Growth / Rebirth / JobChange / Appearance /   │
│  Guild / Economy  …  Combat / Events / Formulas / Rng      │
└──────────────┬───────────────────────────────────────────┘
               │ 読み取り専用
┌──────────────▼───────────────────────────────────────────┐
│ src/data  マスターデータ（Luauのテーブル）                 │
└──────────────────────────────────────────────────────────┘
```

- `src/core` は **Roblox でも Lune でも同じコードが動く**。ここにゲームのルールをすべて置く。
- 入口（Adapter）は `core` を呼ぶだけで、ルールを持たない。UIも同様（D-066）。

## 2. 決定論（同じ入力 → 同じ結果）

- `core` の処理は「状態」「コマンド」「現在時刻」「乱数」だけから結果を決める。
- 時刻は `ctx.now`（Unix秒）、乱数は `Rng`（自前実装）を引数で受け取る（`08_rng_time.md`）。
- これにより、テキスト版では仮想時計で時間を早送りでき、シミュレーターは何万回でも再現可能に回せる。Robloxのサーバーでもクライアントでも同じ結果になる。

## 3. 状態の更新モデル

```
ctx = { now = <Unix秒>, master = <マスターデータ>, online = true|false }

Game.advance(state, ctx)            -- 時間経過の処理（帰還・自動再派遣）
local result = Game.execute(state, command, ctx)
  -- result.ok == true  : state が更新され、result.events に起きたことの一覧
  -- result.ok == false : state は一切変わらず、result.error にエラーコード
```

- **すべてのコマンドの前に `Game.advance` を呼ぶ**（入口側の責任）。
- `execute` は検証 → 変更の順で行い、検証に失敗したら状態に触れない（部分更新を残さない）。
- `events` は「何が起きたか」の列（例：`ExpeditionReturned`, `ChestOpened`）。CLIは文章に、UIは演出に変換する。

## 4. 探索の流れ（D-026）

```
dispatch コマンド
  └─ seed を払い出し → Expedition.simulate(party, dungeon, seed, master) で探索ログを全計算
  └─ state.expeditions に { 出発時刻, 帰還時刻, ログ, 報酬 } を保存（以後変わらない）
advance（時刻が帰還時刻を過ぎたら）
  └─ 報酬を受け取る（宝箱は未開封のまま保管、経験値・ゴールド・アイテムを反映）
  └─ 自動再派遣が有効かつオンラインなら、帰還時刻を出発時刻として次の探索を計算（連鎖）
画面・CLI
  └─ ログと出発時刻から「今どのフロアか」を計算して再生するだけ
```

## 5. 将来への配慮

- 装備・冒険者は一意ID（`uid`）を持つ個体として保存する。将来のオークション（所有権の移転）に備える（D-065）。
- セーブデータには `version` を持たせ、形式変更時は移行関数を書く（`03_state_model.md`）。
