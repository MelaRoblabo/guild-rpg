# 09 テキスト版・シミュレーター・自動プレイ

すべて Lune で動く。`src/core` を呼ぶだけで、ルールは持たない。

## 1. テキスト版（tools/cli）— M2〜

人間とAIエージェントがゲームを遊ぶための入口。

```bash
lune run tools/cli -- --save out/save.json status            # 1回の実行で1コマンド
lune run tools/cli -- --save out/save.json --json go 1 dng_graveyard   # 結果をJSONで返す（AIエージェント用）
lune run tools/cli -- --save out/save.json < tools/cli/scenarios/one_hour.txt   # 標準入力から複数行
```

- 仮想時計はセーブファイルに保存される。`wait <秒>` で進めるまで時間は進まない。
- `help` でコマンド一覧。

| CLIコマンド | 対応する core コマンド／処理 |
| --- | --- |
| `status` | 所持金・ギルドLv・パーティ・探索中の状況・未開封宝箱 |
| `roster` / `show <uid>` | 冒険者一覧／詳細（実効値・装備・ギフト・成長の型） |
| `warehouse` / `items` | 倉庫／アイテム所持数 |
| `party <n> <slot> <uid\|->` | SetPartySlot |
| `equip <uid> <eq_uid>` / `unequip <uid> <slot>` | Equip / Unequip |
| `dungeons` / `hint <dng>` | ダンジョン一覧／攻略ヒント |
| `go <n> <dng>` / `repeat <n> <dng\|off>` | Dispatch / SetAutoRepeat |
| `watch <n>` | 探索の再生（現在位置まで、ログを文章で表示） |
| `wait <秒>` | 仮想時計を進めて advance |
| `open [all\|<uid>...]` | OpenChests |
| `sell <eq_uid>...` / `lock <uid>` | Sell / SetLock |
| `hire` / `candidates` / `pick <n>` / `reroll` / `choose prev\|cur` / `cancel` | Hire 系（M3） |
| `rename <uid> <名前>` / `dismiss <uid>` | Rename / Dismiss（M3） |
| `rebirth <uid> [keep]` / `jobchange <uid> <job>` / `looks <uid>` | M4 |
| `expansions` / `expand <exp_id>` / `autosell <on\|off> [レアリティ] [keep\|all]` | M5 |
| `log` | 直近のイベントを表示 |

- 状態はコマンドごとに JSON ファイルへ保存する（中断・再開できる）。
- `--json` モードの出力：`{ "ok": true, "events": [...], "view": {...} }`。`view` はその時点の状態の要約（AIが毎回 `status` を叩かなくてよいように）。

## 2. 探索シミュレーター（tools/sim）— M1〜

```bash
lune run tools/sim -- expedition --dungeon dng_graveyard --party presets/starter --runs 10000 --seed 1
lune run tools/sim -- sweep --dungeon all --party presets/* --runs 2000
```

出力（Markdown と JSON を `out/sim/` に保存）：

- 踏破率、撤退フロアの分布、平均所要秒（中央値・90%点）
- 1探索あたりの宝箱数（ランク別）、ゴールド、経験値
- 戦闘の平均ターン数、全滅の原因（戦闘／罠）、隊列ごとの被ダメージと戦闘不能率
- ギフト発動回数

パーティのプリセットは `tools/sim/presets/*.luau`（職業・レベル・装備・ギフトを指定）。

## 3. 自動プレイヤー（tools/autoplay）— M5〜M6

決まった方針（ポリシー）でゲーム全体を長時間遊び、指標を集計する。

```bash
lune run tools/autoplay -- --hours 72 --seed 1
```

- ポリシーは `tools/autoplay/policies/*.luau`。「次に何をするか」を状態から決める関数。
  - 例：`greedy`（行ける最も深いダンジョンへ、良い装備は即装備、不要品は売却、貯まったら拡張）、`cautious`（踏破率80%以上のダンジョンのみ）、`collector`（面接で引き直しを使い切る）。
- 指標（企画書§14 と D-049 に対応）：
  - 最初の宝箱を開けるまでの時間
  - 1時間あたりの宝箱数・ゴールド（パーティ数別）
  - 各拡張・各ダンジョン解放・初転生までの時間
  - ダンジョンごとに最適な隊列・職業構成・防具が変わるか
  - 報酬量・通貨量の急増がないか（時間あたり収入の推移）
- レポートは `out/autoplay/<日時>/report.md`。

## 4. AIエージェントによるテストプレイ — M6

- AIエージェントに `--json` モードのテキスト版を遊ばせる。
- 指示：目的（例：「2時間でできるだけ強いギルドを作る」）、制約（使える仮想時間）、記録すること（判断の理由、迷った点、退屈だった点、嬉しかった瞬間）。
- 出力：`out/playtest/<日時>/` にプレイログとレポート。自動プレイヤーの数値と合わせて、M6でのバランス調整の材料にする。
