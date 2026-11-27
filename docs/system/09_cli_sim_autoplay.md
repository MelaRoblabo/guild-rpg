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
| `sellweak [eq_uid...]` | BulkSell（直前の開封結果から「今の装備より弱い」を一括売却：D-167。修飾語つきも弱ければ売る：D-207。uid を書けばその装備が対象。直前の開封結果はテキスト版のセーブに覚える） |
| `inbox` / `claim` | 受け取り箱の中身／ClaimInbox（D-164） |
| `quests` | 今日・今週のクエストと進み具合（D-153） |
| `calendar` | ログインボーナスのカレンダー・今日のプレイ時間・休息ボーナスの残り（D-154, D-155, D-161） |
| `daily` | 今日・明日の日替わりの特性（D-156） |
| `event` / `eventgo <n> [時間帯]` | 今のマップイベントと予告／DispatchEvent（D-152。時間帯を省くと今の時間帯） |
| `merchant` / `buy <番号> [時間帯]` | 旅の商人の品／BuyFromMerchant（D-152。時間帯を省くと今の時間帯） |
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
lune run tools/autoplay -- --days 15 --profile heavy --seed 1 --friends 1 --quiet   # 友達がいる想定・要約だけ表示
```

- `--hours N`：ずっとオンラインの想定（帰還したらすぐ操作。自動再派遣は使わない）。1時間ごとの表を出す。
- `--days N`：1日の流れ（下）。`--profile light|core|heavy`（省略時 core）、`--friends N`（`ctx.friendCount`。省略時は `Schedule.friendCount` ＝ 0：友達はいない想定）、`--quiet`（レポートを画面に出さない）。最大の育成に届いたらそこで止める。

- **1日の流れ（D-161、M7b-6）**：ログイン・ログアウトをくり返し、暦日数で進み方を測る。1日のオンラインの時間は型ごとに次のとおり（`--profile light|core|heavy`）。
  | 型 | 1日のオンライン | 目標（最大の育成まで） |
  | --- | --- | --- |
  | ライト | 約0.6時間 | 約70日 |
  | コア | 約2.5時間 | 約30日 |
  | ヘビー | 約6時間 | 約15日 |
  - ログアウト中は留守番（6時間まで。経験値は得ない：D-280）を core の advance（`ctx.online = false`）で計算する。休息ボーナスは D-280 で廃止。ログイン時刻の置き方（1日のどこで遊ぶか）は未決（M7b-6）。
  - 1日のログインの分け方（回数・時刻・分数）は試し方の設定として `tools/autoplay/Schedule.luau` にまとめる（仮。ゲームの数値ではないので src/data に置かない）。今は朝・昼・夜に分け、ライト3回（計36分）・コア4回（計150分）・ヘビー5回（計360分）。時刻は日本時間（ゲームの日の区切りは朝9時：06章 §11）。
  - ログイン：留守の計算 → その日の最初のオンラインの advance（ログインボーナス・クエストの入れ替え）→ 自動再派遣を外す → 方針で操作。オンライン中は帰還のたびに方針で出し直す。帰還のないとき、マップイベントの始まり（商人、または空いているパーティがいてレアダンジョン・レイド）とフレンドボタンを押せる時刻にも起きて、軽く見回る。
  - ログアウト：各パーティに自動再派遣（行き先は最後に選んだ普通のダンジョン）を付け、`lastSavedAt` をログアウトの時刻にする（サーバーの保存の代わり）。
  - 新しい入手先（クエスト・ログインボーナス・プレイ時間・フレンド・マップイベント・商人）と使い道を入れ、入手先の配分（04章 §13、D-160）と照らし合わせる。
    - 方針に入れた行動：受け取り箱を受け取る／開封のあとに一括売却（D-167）／フレンドボタン（友達がいる想定のとき）／マップイベントが出ている時間帯に空いているパーティをレアダンジョン・レイドへ／商人は、誰かの今の装備より良い品を、転生の備えを除いた所持金の一定割合（`Schedule.behavior.merchantBudgetShare`）までで買う。
    - クエスト・ログインボーナス・プレイ時間・今週の訪問者は、ふだんの行動と advance で自然に進むので、特別な行動は入れない。
  - 周回時間（D-071、`expCycleMult`）はこの暦日数に合わせて調整し直す。オンラインの価値（ゴールドと宝箱が、留守番が動く6時間までの分で割って10倍以上：D-292）が守られているかも測る。合否は §5 の成績表で出す。
  - **最大の育成**（D-199）：パーティ枠を最後まで拡張し、パーティに入っている全員が最後の転生（上限レベル `levelCapMax`）で上限レベルに届いた状態。途中の目安（初めての転生・初めて最後の転生に届いた日など）も出す。
  - 測るもの（`tools/autoplay/Days.luau`・`Ledger.luau`）：
    - 最大の育成までの暦日数。
    - 1時間あたりの価値（経験値・探索のゴールド・宝箱）のオンライン／留守番の比。オンラインはオンラインで出した探索（ログアウトの時点で出ていた探索を含む）、留守番は留守番の探索。留守の時間は「留守の全時間」と「留守番が動く6時間までの分」の2つで割る。留守番の経験値は0（D-280）なので、経験値の比は参考（D-292）。
    - 報酬の入手先の配分：ゴールド・宝箱・チケット・指南書・手鏡・ロケット（D-255）を、冒険（留守番の探索を含む：D-200）／クエスト／ログイン／プレイ時間／フレンド／マップイベント／ギルドレベルに分け、D-160 の目標の表と並べる。ゴールドは「直接」（入手先が直接くれた分）と「宝箱込み」（宝箱の中身のゴールドと装備の売却を宝箱の入手先に足す）の2つ。普通のダンジョンの宝箱の山はオンラインと留守番の宝箱が混ざるので、中身は山に入った数の割合で按分する。
    - ゴールドの残高の推移（日ごとの収入・支出・残高。D-163）。
    - レイド（D-179）：出発した時間帯の数・討伐率・1時間帯あたりの参加パーティ数・1パーティのダメージ÷HP の分布・討伐に要ったパーティ数（到着順）。M7b-6 で追加。
    - 旅の商人（D-198）：見た品の数と平均価格・誰かの装備より良い品・そのうち予算内・買った品と額（収入に対する割合）。測るだけで方針の行動は変えない。M7b-6 で追加。
    - 1時間あたりの価値の「宝箱」は、オンラインの側にレイドの宝箱を含めて数える（D-200。レイドはオンラインでだけ出せる派遣で、宝箱は帰還ではなく受け取り箱に届く）。参考にレイドの宝箱を除いた行も出す。
    - 日ごとの要約（Markdown の表と CSV）。
  - レポートは `out/autoplay/<日時>-<型>-<方針>-seed<n>-<日数>d.md` と同じ名前の `.csv`。
- ポリシーは `tools/autoplay/Policy.luau`（方針 greedy・cautious・collector を `--policy` で選ぶ）。「次に何をするか」を状態から決める関数。
  - 例：`greedy`（行ける最も深いダンジョンへ、良い装備は即装備、不要品は売却、貯まったら拡張）、`cautious`（踏破率80%以上のダンジョンのみ）、`collector`（面接で引き直しを使い切る）。
- 指標（企画書§14 と D-049 に対応）：
  - 最初の宝箱を開けるまでの時間
  - 1時間あたりの宝箱数・ゴールド（パーティ数別）
  - 各拡張・各ダンジョン解放・初転生までの時間
  - ダンジョンごとに最適な隊列・職業構成・防具が変わるか
  - 報酬量・通貨量の急増がないか（時間あたり収入の推移）。派遣費の廃止（D-163）で後半にゴールドが積み上がらないか
  - 最大の育成までの暦日数（型ごと）、入手先ごとの報酬の割合（D-160, D-161）
- レポートは `out/autoplay/` に保存する（`--hours` は `<日時>-<方針>-seed<n>-<時間>h.md`）。
- Lune を同時に複数起動すると固まったことがある（M6、Lune 0.8.9）。並べて回すときは様子を見ながら少しずつ。

## 4. AIエージェントによるテストプレイ — M6

- AIエージェントに `--json` モードのテキスト版を遊ばせる。
- 指示：目的（例：「2時間でできるだけ強いギルドを作る」）、制約（使える仮想時間）、記録すること（判断の理由、迷った点、退屈だった点、嬉しかった瞬間）。
- 出力：`out/playtest/<日時>/` にプレイログとレポート。自動プレイヤーの数値と合わせて、M6でのバランス調整の材料にする。

## 5. バランスの成績表（tools/balance）— MB

仕様を変えたら、すぐ同じ目標でバランスを確かめて合わせるための入口。目標は `src/data/BalanceTargets.luau`（04章 §14）だけに置き、このツールはそれを読んで合否を出す。ツールの中に目標の値を書かない。

```bash
lune run tools/balance                                  # 全部（約10分。型 × seed は目標の表のとおり）
lune run tools/balance -- --only sim                    # 探索シミュレーターの目標だけ（数十秒）
lune run tools/balance -- --only autoplay --profiles core --seeds 2
lune run tools/balance -- --targets bal_days_to_max_growth,bal_share_tools
lune run tools/balance -- --set Constants.expCycleMult.5=4.2 --set Dungeons.dng_ruins.unlockGold=500
lune run tools/balance -- --save-baseline               # この結果を基準として保存（D-295）
lune run tools/balance -- --quick                       # 動くかだけ（tools/check が使う）
```

- しくみ：目標の表から、測る型（ライト・コア・ヘビー）と友達の数の組を集め、自動プレイ（§3 の1日の流れ、方針 greedy）を seed の数だけ別のプロセスで並べて回す（`tools/balance/worker.luau`。並べる数は `Settings.parallel`）。待つ間に探索シミュレーター（段階のパーティ `tools/sim/Stages.luau`）を回す。
- 日数：暦日数の目標 × `Settings.daysCapFactor`（1.5）まで回し、届かなければ「未到達」で不合格。
- 判定（04章 §14 の `judge`）：`near`（平均が目標の幅に入る）・`atLeast`・`atMost`・`share`（書いた列ごとに ±ポイント）・`baseline`（合否を置かず、基準から `Settings.baselineWarnRel` 以上ずれたら警告：D-295）。seed の平均で判定し、最小〜最大を並べる（D-291）。
- 指標の計算：自動プレイは `tools/balance/Metrics.luau`、探索シミュレーターは `tools/balance/SimMetrics.luau`。目標の表に新しい `metric` を足したら、ここに計算を足す（足さないとテストが落ちる：`tests/Balance.spec.luau`）。
- 値の上書き（`--set パス=値`）：`src/data` を書き換えずに、読み込んだデータの値だけを変えて試す。配列の中は id で探す（`Dungeons.dng_ruins.unlockGold`）、番号でも指せる（`Constants.expCycleMult.5`）。無いパスはエラー。上書きは自動プレイの各プロセスにも渡す。
- 基準（D-295）：`tools/balance/Baseline.json`。`--save-baseline` で、その回に回した目標の値だけを置き換える（上書き・`--quick` のときは保存しない）。成績表のすべての行に「基準との差」を出す。
- 出力：`out/balance/<日時>.md`（成績表）と `.json`（平均・最小・最大）、`out/balance/<日時>/`（各回の指標）。

### 体験スコアと履歴（MX。D-301）

- 成績表は、バランスの目標と一緒に体験スコア（04章 §15）も出す。型ごとの自動プレイ（友達なし）に出来事の記録（`Days.run` の `opts.trace`）を付け、`tools/balance/Experience.luau` が指標を出し、`Score.luau` が点数にする。
- 出来事の分け方（節目・ごほうび・新しさ）は docs/reports/MX_engagement.md の冒頭。留守の間の出来事は次のログインで見た時刻に数える。
- `--label "名前"` を付けると、点数とバランスの合格／不合格を `tools/balance/History.json` に残す（`--quick` のときは残さない）。成績表の体験スコアの表には、履歴の最後との差が出る。
- 回すたびに `out/balance/history.html` を作り直す。型ごとに分類と総合の折れ線と、回ごとの一覧。
- `--no-experience` で体験スコアを回さない。`--only sim` のときも回さない。

### 揺れの扱い

- 自動プレイの方針は、同じ点数の品や人を選ぶとき uid の順で決める（表の読み出し順に任せない）。core は操作のたびに状態を複製するので、読み出し順は操作の数で変わる。並び順に任せると、仕様に関係のない変更（操作が1つ増えるなど）で結果が大きく変わっていた（2026-11-27 に修正。読み出し順を毎回入れ替えても同じ結果になることを確かめた）。
- それでも seed による差は残る。成績表の `.json` には指標ごとに seed の順の値（`values`）と標準誤差（`se`）を残す。
- 基準との差・履歴の最後との差は、2つの標準誤差を合わせた幅の2倍以内なら「揺れの範囲」（体験スコアでは「≒」）と出し、変化とみなさない。基準の警告（D-295）もこの範囲では出さない。
- 揺れの大きい項目（例：ライトのゴールドの積み上がりは seed で 1.6〜6.0 日分）は、5 seed では合否が入れ替わりうる。seed を増やすときは D-291 を変える。

### 改善のループ（MX-4）

1. 体験スコアの弱い分類を選び、直す案を出す（決定ログに入れる）。
2. 数値だけなら `--set` で試す。仕組みを足すなら実装する。
3. `lune run tools/balance -- --label "案の名前"` で、体験スコアとバランスの成績を同時に見る（体験を上げてバランスを崩していないか）。
4. 区切りで人のテストプレイをして、点数の上下と感想が合っているかを確かめる。合わなければ指標や線（D-301）を直す。

### 仕様を変えるときの手順

1. 決定ログに決定を足す（目標が変わるなら、その値も決定に書く）。
2. 目標が変わるなら `src/data/BalanceTargets.luau` を直す。新しい指標なら `Metrics.luau`／`SimMetrics.luau` に計算を足す。
3. 仕様を実装する（自動プレイの方針に新しい行動が要るなら `tools/autoplay/Policy.luau` も）。
4. `lune run tools/balance` を回し、不合格と警告を見る。
5. 数値を合わせるときは、まず `--set` で試し、良い値を `src/data` に入れる（`data:` コミットに、成績表の前後を書く）。
6. 合ったら `--save-baseline` で基準を保存し、一緒にコミットする。
