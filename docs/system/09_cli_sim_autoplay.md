# 09 テキスト版・シミュレーター・自動プレイ

すべて Lune で動く。`src/core` を呼ぶだけで、ルールは持たない。

## 1. テキスト版（tools/cli）— M2〜

人間とAIエージェントがゲームを遊ぶための入口。

```bash
lune run tools/cli -- --save out/save.json status            # 1回の実行で1コマンド
lune run tools/cli -- --save out/save.json --json go 1 dng_graveyard   # 結果をJSONで返す（AIエージェント用）
lune run tools/cli -- --save out/save.json < tools/cli/scenarios/one_hour.txt   # 標準入力から複数行
```

- 仮想時計はセーブファイルに保存される。`wait <秒>` で進めるまで時間は進まない。`days <日数>` で日単位に進める（日・週の区切りは 06章 §11、D-168）。
- ログイン・ログアウトを `logout` / `login` で表す（D-161）。`logout` で最後に保存した時刻（`lastSavedAt`）を書き、ログアウト中に進めた時間は `login` のときに留守番（`ctx.online = false` の advance）として計算する。
- `help` でコマンド一覧。

| CLIコマンド | 対応する core コマンド／処理 |
| --- | --- |
| `status` | 所持金・ギルドLv・パーティ・探索中の状況・未開封宝箱 |
| `roster` / `show <uid>` | 冒険者一覧／詳細（実効値・装備・ギフト・成長の型） |
| `warehouse` / `items` | 倉庫／アイテム所持数 |
| `party <n> <slot> <uid\|->` | SetPartySlot |
| `equip <uid> <eq_uid>` / `unequip <uid> <slot>` | Equip / Unequip |
| `dungeons` / `hint <dng>` | ダンジョン一覧／攻略ヒント |
| `go <n> <dng>` / `repeat <n> <dng\|off>` | Dispatch / SetAutoRepeat（派遣費は廃止：D-163） |
| `watch <n>` | 探索の再生（現在位置まで、ログを文章で表示） |
| `wait <秒>` | 仮想時計を進めて advance |
| `days <日数>` | 仮想時計を日単位で進める（ツール用。D-168） |
| `logout` / `login` | ログアウト（lastSavedAt を書く）／ログイン（留守番と休息ボーナスの計算：D-161） |
| `open <山> [個数]` | OpenChests（まとめ開き：D-089。山は dungeonId か `special:<種類>`：D-166） |
| `sellweak [eq_uid...]` | BulkSell（直前の開封結果から「今の装備より弱い」を一括売却：D-167。uid を書けばその装備が対象。直前の開封結果はテキスト版のセーブに覚える） |
| `inbox` / `claim` | 受け取り箱の中身／ClaimInbox（D-164） |
| `quests` | 今日・今週のクエストと進み具合（D-153） |
| `calendar` | ログインボーナスのカレンダー・今日のプレイ時間・休息ボーナスの残り（D-154, D-155, D-161） |
| `daily` | 今日・明日の日替わりの特性（D-156） |
| `event` / `eventgo <n>` | 今のマップイベントと予告／DispatchEvent（D-152） |
| `merchant` / `buy <番号>` | 旅の商人の品／BuyFromMerchant（D-152） |
| `friend [人数]` | ClaimFriendReward（同じサーバーの友達の数を引数で与える：D-157） |
| `visitor` | 今週の訪問者と出現率（D-158） |
| `sell <eq_uid>...` / `lock <uid>` | Sell / SetLock |
| `hire` / `candidates` / `pick <n>` / `reroll` / `choose prev\|cur` / `cancel` | Hire 系（M3） |
| `rename <uid> <名前>` / `dismiss <uid>` | Rename / Dismiss（M3） |
| `rebirth <uid> [keep]` / `jobchange <uid> <job>` / `looks <uid>` | M4 |
| `expansions` / `expand <exp_id>` / `autosell <on\|off> [レアリティ] [keep\|all]` | M5 |
| `train <uid> [回数\|max]` / `trainquote <uid> <Lv>` | Train（D-076）／見積もり |
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
lune run tools/autoplay -- --days 30 --profile core --seed 1     # 1日の流れで暦日数を進める（D-161）
```

- **1日の流れ（D-161、M7b-6）**：ログイン・ログアウトをくり返し、暦日数で進み方を測る。1日のオンラインの時間は型ごとに次のとおり（`--profile light|core|heavy`）。
  | 型 | 1日のオンライン | 目標（最大の育成まで） |
  | --- | --- | --- |
  | ライト | 約0.6時間 | 約70日 |
  | コア | 約2.5時間 | 約30日 |
  | ヘビー | 約6時間 | 約15日 |
  - ログアウト中は留守番（6時間まで）と休息ボーナスを core の advance で計算する。ログイン時刻の置き方（1日のどこで遊ぶか）は未決（M7b-6）。
  - 新しい入手先（クエスト・ログインボーナス・プレイ時間・フレンド・マップイベント・商人）と使い道を入れ、入手先の配分（04章 §13、D-160）と照らし合わせる。
  - 周回時間（D-071、`expCycleMult`）はこの暦日数に合わせて調整し直す。オンラインの価値（1時間あたりオフラインの10倍以上）が守られているかも測る（D-161）。
- ポリシーは `tools/autoplay/policies/*.luau`。「次に何をするか」を状態から決める関数。
  - 例：`greedy`（行ける最も深いダンジョンへ、良い装備は即装備、不要品は売却、貯まったら拡張）、`cautious`（踏破率80%以上のダンジョンのみ）、`collector`（面接で引き直しを使い切る）。
- 指標（企画書§14 と D-049 に対応）：
  - 最初の宝箱を開けるまでの時間
  - 1時間あたりの宝箱数・ゴールド（パーティ数別）
  - 各拡張・各ダンジョン解放・初転生までの時間
  - ダンジョンごとに最適な隊列・職業構成・防具が変わるか
  - 報酬量・通貨量の急増がないか（時間あたり収入の推移）。派遣費の廃止（D-163）で後半にゴールドが積み上がらないか
  - 最大の育成までの暦日数（型ごと）、入手先ごとの報酬の割合（D-160, D-161）
- レポートは `out/autoplay/<日時>/report.md`。

## 4. AIエージェントによるテストプレイ — M6

- AIエージェントに `--json` モードのテキスト版を遊ばせる。
- 指示：目的（例：「2時間でできるだけ強いギルドを作る」）、制約（使える仮想時間）、記録すること（判断の理由、迷った点、退屈だった点、嬉しかった瞬間）。
- 出力：`out/playtest/<日時>/` にプレイログとレポート。自動プレイヤーの数値と合わせて、M6でのバランス調整の材料にする。
