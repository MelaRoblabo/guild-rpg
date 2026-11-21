# 11 Roblox組み込み（M7）

M7（Roblox統合）の設計。根拠は D-099〜D-102。「（仮）」の値は運用しながら調整する。

## 1. ビルド

```
src/（文字列 require のまま）──rojo serve / rojo build──▶ Roblox
```

変換は挟まない（D-102。darklua は使わない。検証は `docs/reports/M7_require_spike.md`）。

| リポジトリ | Roblox 上の場所 | 種類 |
| --- | --- | --- |
| `src/core` | `ReplicatedStorage.Core` | Folder（各ファイルが ModuleScript） |
| `src/data` | `ReplicatedStorage.Data` | ModuleScript（`init.luau`）。各ファイルがその子 |
| `src/server` | `ServerScriptService.Server` | `*.server.luau` が Script、それ以外は ModuleScript |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` | `*.client.luau` が LocalScript 相当、それ以外は ModuleScript |

- `src/core` と `src/data` は ReplicatedStorage に置く（サーバーとクライアントの両方で使う。クライアントは表示用の計算と再生にのみ使う）。

### require の書き方（D-102）

| 書き方 | 意味（Roblox） | 使う場所 |
| --- | --- | --- |
| `require("./X")` | `script.Parent.X`（同じフォルダの兄弟） | どこでも |
| `require("../X")` | `script.Parent.Parent.X` | どこでも |
| `require("@self/X")` | `script.X`（フォルダの入口 `init.luau` から子） | どこでも |
| `require("@game/ReplicatedStorage/Core/X")` | DataModel からの絶対位置 | `src/server`・`src/client` だけ（Lune では解決できない） |

- Roblox は `.luaurc` の別名を読まないので、別名は使わない。
- クライアントは入口で `ReplicatedStorage:WaitForChild("Core")`・`WaitForChild("Data")` を待ってから require する（本番で複製が遅れても失敗しないように）。

### 開発時の同期

1. リポジトリで `rojo serve` を起動する。
2. Studio（プレイス「冒険者ギルド」、D-100）の Rojo プラグインで Connect する。
3. 上の表の場所がリポジトリの内容で作られ、保存のたびに更新される。Rojo が管理しない場所には触れない。
4. プレイテストの前に、Studio 側のスクリプトがリポジトリと同じか確かめる（M7-3 で、OneDrive 内のフォルダでファイルの変更を1回取りこぼしたことがある）。違っていたら、そのファイルを保存し直す（中身を一度変えて戻す）。


### サーバー・クライアントのコードの置き方

- `src/server`・`src/client` のうち、Roblox API も `@game/...` も使わない純粋なモジュール（例：セッションロックの判定）は、`tests/` から相対パスで require して Lune でテストする。
- Roblox API を使う部分（DataStore・Remote・Players など）は薄く保ち、Studio のプレイテストで確認する（Studio MCP を使ってよい）。
- 静的解析：`src/server`・`src/client` は selene の `roblox` 標準（`selene.roblox.toml`）で検査する（`tools/check` から実行。selene 0.32 以降）。`src/core`・`src/data`・`tools`・`tests` は従来どおり `luau` 標準。
- 運用の値（自動保存の間隔など。ゲームの数値ではないもの）は `src/server/Config.luau` に置く。ゲームの数値・確率・コンテンツは従来どおり `src/data`。

## 2. サーバー権限

- 状態の変更はすべてサーバーで `Game.execute` / `Game.advance` を実行する。クライアントはコマンドを送るだけ。
- 乱数・探索ログの確定・購入の付与はサーバーのみ。
- マスターデータはサーバー起動時に1回 `MasterData.load(Data)` する。検証に失敗したら、エラーを出力してプレイヤーを受け付けない（壊れたデータで遊ばせない）。
- `ctx = { now = os.time(), master = master, online = true }`（08章）。
- プレイヤーごとにサーバー内のセッションを持つ：`{ state, loadedAt, lastSavedAt, dirty, commandTimes }`。
- **時間経過**：コマンドの前に必ず `Game.advance` を呼ぶ（01章）。加えて、オンラインの全プレイヤーに `advanceIntervalSeconds`（仮：1秒）ごとに `Game.advance` を呼び、帰還・自動再派遣が起きたら状態を通知する（§4）。
- **新規プレイヤーの seed**：`Game.newState(master, seed, now)` の `seed` は、サーバーが Roblox の `Random` で1回だけ作る（1〜2^31−1）。以後の乱数はすべて core の `Rng`（08章）。`Random` を使うのはここだけ。

## 3. 保存（D-099）

DataStore を直接使い、セッションロックを自前で実装する。

### 3.1 保存する形

| 項目 | 内容 |
| --- | --- |
| DataStore 名 | `PlayerData_v1`（仮）。形式を根本から変えるときだけ番号を上げる（通常の形式変更は `state.version` と Migration で行う） |
| キー | `player_<UserId>` |
| 値 | `{ state = PlayerState, session = { jobId, placeId, at }?, savedAt }` |

- `session` はロック。`jobId` は `game.JobId`、`at` は最後に確認した時刻（Unix秒）。Studio のプレイテストでは `game.JobId` が空になるため、サーバー起動時に作った一意の文字列を代わりに使う。
- 1回の保存の大きさを JSON で測り、`saveSizeWarnBytes`（仮：3,000,000）を超えたら警告を出す（DataStore の上限は 4MB）。

### 3.2 読み込み（参加時）

1. `UpdateAsync` で記録を読み、同じ更新の中でロックを取る。
   - 記録がない → 新規。`session` を自分にして保存。
   - `session` がない、自分のもの、または `session.at` が `lockTimeoutSeconds`（仮：600秒）より古い（落ちたサーバーのロック）→ 自分のロックに書き換える。
   - 他のサーバーが有効なロックを持っている → 書き換えずに中止し、`lockRetrySeconds`（仮：5秒）待って再試行。`lockRetryCount`（仮：6回）で取れなければ、「別のサーバーでデータを使用中です。しばらくしてから入り直してください」でキックする。
2. 新規なら `Game.newState`、既存なら `Migration` で最新版に移行する。
3. `Game.advance(state, { online = false })` を呼び、オフライン中に帰還した探索だけを処理する（05章 §3、企画書§16.8 案A）。
4. セッションを作り、クライアントに状態を通知する（§4、`reason = "load"`）。
5. 読み込み中に退出した場合は、ロックを解放して終わる。

### 3.3 保存

| いつ | 内容 |
| --- | --- |
| 定期保存 | `autosaveSeconds`（仮：60秒）ごと。変更がなくても `session.at` を更新する（ロックの生存確認） |
| 退出時（PlayerRemoving） | 保存してロックを解放（`session = nil`）し、セッションを消す |
| サーバー終了時（BindToClose） | 全員を並行して保存・解放し、終わるまで待つ（Roblox の制限内：最大30秒） |

- 保存は必ず `UpdateAsync` で行い、記録の `session.jobId` が自分であることを確認してから書く。自分でなければ（ロックを失った）書かずに、そのプレイヤーをキックする（二重ログインでの上書き防止）。
- DataStore のエラーは `saveRetryCount`（仮：3回）まで待ち時間を倍にしながら再試行する（1秒・2秒・4秒）。
- 保存の直前に、そのプレイヤーの処理中のコマンドが終わっていること（§4.4 の順番待ち）を確認する。
- 開発中のセーブデータは本番と同じ DataStore に入る（D-100）。公開前の扱いは M9 までに決める。

### 3.4 ロックの判定は純粋な関数にする

`src/server/SessionLock.luau`：`decide(record, myJobId, now, timeout) → "take" | "wait"`、`canSave(record, myJobId) → boolean`。Roblox API を使わないので Lune でテストする（新規・自分・他人の有効なロック・期限切れ・ロック喪失）。

## 4. 通信（D-101、D-103）

`ReplicatedStorage.Remotes` に2つ置く（Rojo の設定 `default.project.json` で宣言する）。

| 名前 | 種類 | 向き | 用途 |
| --- | --- | --- | --- |
| `Command` | RemoteFunction | クライアント → サーバー → 結果を返す | 05章のコマンドを送る |
| `StateChanged` | RemoteEvent | サーバー → クライアント | 起きたことと、状態の要約の差分を送る |

### 4.1 Command

```lua
local result = Remotes.Command:InvokeServer({ type = "Dispatch", partyIndex = 1, dungeonId = "dng_graveyard" })
-- result = { ok = true, events = { ... } } / { ok = false, error = "PARTY_BUSY" }
```

- 受け付けるのは 05章の M2〜M5b のコマンド。`GrantPurchase`（サーバー専用）は受け付けない。
- 加えてサーバーだけで処理する `{ type = "Sync" }`：何も変えずに、状態の要約の**全体**と連番を返す（`{ ok = true, seq, view }`）。クライアントの起動直後と、連番が飛んだときの再同期に使う（§4.3）。
- 状態の変化は戻り値には入れず、§4.2 の通知で送る（`reason = "command"`）。戻り値は `ok`・`error`・`events` だけ。
- サーバー側のエラーコード（core のエラーに加える）：

| コード | 意味 |
| --- | --- |
| `NOT_READY` | まだ読み込み中 |
| `BAD_REQUEST` | 形が正しくない（型・範囲・知らない type） |
| `RATE_LIMITED` | 送りすぎ |
| `SERVER_ERROR` | サーバー内部のエラー（状態は変えない） |

### 4.2 StateChanged

```lua
-- 差分（通常）
{ reason = "command" | "advance", seq = 42, baseSeq = 41, patch = { ... }, events = { ... }, serverTime = number }
-- 全体（参加時だけ）
{ reason = "load", seq = 1, view = { ... }, events = {}, serverTime = number }
```

- `advance` は定期の時間経過で何か起きたときだけ送る（帰還・自動再派遣・停止）。
- **全体を送るのは参加時（`load`）と `Sync` の戻り値だけ。** それ以外は前回送った要約との差分（`patch`）だけを送る（D-103）。差分が空なら `patch` は空の配列（events だけ届ける）。

### 4.3 差分の作り方と受け取り方（D-103）

サーバーはプレイヤーごとに「前回送った要約（`lastView`）」と連番（`seq`）を持つ。

1. 状態が変わったら新しい要約を作り、`Protocol.diff(lastView, newView) → patch` を計算する。
2. `seq` を1つ進め、`{ seq, baseSeq = 前の seq, patch }` を送る。`lastView = newView`。
3. クライアントは `baseSeq` が手元の `seq` と同じなら `Protocol.applyPatch(view, patch)` を適用して `seq` を進める。違えば（取りこぼし・順番違い）差分を捨て、`Sync` で全体を取り直す。

差分の形：

```lua
patch = {
	{ path = { "gold" }, value = 1250 },                         -- 設定（追加・変更）
	{ path = { "equipment", "eq_812" }, value = { ... } },        -- 辞書の要素を追加・変更
	{ path = { "equipment", "eq_77" }, delete = true },           -- 辞書の要素を削除
	{ path = { "parties" }, value = { ... } },                    -- 配列は丸ごと置き換え
}
```

- **辞書**（文字列キーのテーブル。冒険者・装備・アイテム・探索など）は、キーごとに比べて、変わった要素だけを入れる。要素の中も辞書なら、さらに中へ進んで比べる。
- **配列**（1から連番のテーブル。パーティ・隊列・探索ログ・宝箱の数など）は、中身が1か所でも違えば配列を丸ごと置き換える（途中の挿入・削除で番号がずれる問題を避ける）。
- 要約（view）は辞書と配列だけで作り、1つのテーブルに両方を混ぜない。空のテーブルは辞書として扱う（比べる側の片方が配列なら丸ごと置き換え）。値は文字列・数値・真偽値・テーブルのみ（関数・インスタンス・NaN を入れない）。
- `diff`・`applyPatch` は純粋な関数（`src/core/Protocol.luau`）。Lune で「`applyPatch(deepCopy(a), diff(a, b))` が `b` と一致する」ことを、手で作った例とゲームを進めた状態（テキスト版・自動プレイ）の両方でテストする。
- 差分の大きさを測る：72時間分の自動プレイの状態で、要約の全体と、1回の操作・1回の帰還の差分の大きさ（JSON のバイト数）を記録する（M7-5）。

### 4.4 受け付けの検証と順番

### 4.3 受け付けの検証と順番

- 形の検証は `src/core/Protocol.luau` の `Protocol.validateCommand(command) → (ok, err)` で行う。type ごとに引数の型・範囲を決めた表を持つ（数値は整数か・範囲内か、文字列は長さの上限、配列は要素数の上限）。中身の正しさ（所持金・職業制限など）は従来どおり `Game.execute` が判定する。
- 送りすぎ：1人あたり `commandRateLimit`（仮：1秒に10回）を超えたら `RATE_LIMITED`。
- 1人のコマンドは到着順に1つずつ処理する（保存の待ちなどで処理が重ならないように）。

### 4.5 状態の要約（view）と隠す情報

`Protocol.view(state, master, now)` で作る（純粋な関数。Lune でテストする）。

- 送らないもの：`seed`・`rngCounter`・各探索の `seed`（乱数の予測を防ぐ）、`nextUid`、`stats`（集計用）、`lastAdvancedAt`（時間経過のたびに変わるだけで表示に使わない。送ると差分が毎秒出る）。
- 宝箱（D-087）：`chests`（ランク別の数）の代わりに `Game.query.chestsByDungeon` の結果（ダンジョンごとの数）を送る。
- 探索ログ：宝箱のランクを取り除き、個数だけ残す（`Protocol.redactLog`）。`floors[].detail.ranks` → `detail.chestCount`、`rewards.chests` → `rewards.chestCount`、`clearChestRanks` → `clearChestCount`。
- events：`ExpeditionReturned` など、宝箱のランクを含むものは同じ規則で取り除く。開封結果（`ChestsOpened`）は開けた後なのでランクを含めてよい（演出の `effect` と派手さの `rank` に使う）。
- それ以外の状態（冒険者・パーティ・装備・アイテム・面接や転生の途中の結果など）はそのまま送る。

## 5. クライアント（M7 はデバッグ用の簡易画面のみ）

- 入口（`src/client/Main.client.luau`）で `Core`・`Data`・`Remotes` を `WaitForChild` で待ってから require する（§1）。
- 起動時に `Sync` を送って全体と連番を受け取り、以後は `StateChanged` の差分を `Protocol.applyPatch` で手元の要約に適用して表示する。連番が合わなければ `Sync` で取り直す（§4.3）。`Sync` の応答より前に届いた差分は捨てる（`Sync` の連番以下のもの）。
- 画面：状態の一覧（テキスト）と、テキスト版（09章 §1）と同じ書式でコマンドを打つ入力欄、結果のログ。見た目は作らない（UI は M8）。
- テキストの書式をコマンドに変える処理は、テキスト版と共通にする（`tools/cli` から `src/core/CommandText.luau` に切り出し、両方から使う。Lune でテストする）。
- 探索の現在位置などの表示用の計算は `Game.query.*` を使う。表示用の時刻は `workspace:GetServerTimeNow()` の整数部分。

## 6. マルチ表示（D-027）

- 他プレイヤーの表示に必要なのは、各パーティの `dungeonId`・`departAt`・`travelSeconds`・`totalSeconds` だけ。M8で実装。

## 7. 確認方法（M7 の完了条件）

- Lune：`lune run tools/check`（`Protocol`（検証・要約・差分）・`CommandText`・`SessionLock` のテストを含む）。
- 差分：Studio で、操作のたびに届く通知が差分だけであること、連番を意図的に飛ばすと `Sync` で取り直して表示が正しく戻ることを確認する。差分の大きさの記録（§4.3）。
- Studio：Rojo で同期し、プレイテストで M2〜M5b の全コマンドをデバッグ画面から実行できる。退出→再参加で状態が戻る。オフライン中に帰還した探索が参加時に受け取られる。
- 二重ログイン：同じプレイヤーのロックが残っている間は、別サーバーで読み込まない（`SessionLock` のテストと、記録を手で書き換えた確認）。
