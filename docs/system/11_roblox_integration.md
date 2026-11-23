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
- プレイヤーごとにサーバー内のセッションを持つ：`{ state, loadedAt, lastSavedAt, seq, lastView, commandTimes, busy, referralBusy?, referralRetryAt? }`（`referralRetryAt` は紹介の届け物を次に書く時刻。箱がいっぱいなら `math.huge`＝次のログインまで書かない：§3.7、D-197）。
- **時間経過**：コマンドの前に必ず `Game.advance` を呼ぶ（01章）。加えて、オンラインの全プレイヤーに `advanceIntervalSeconds`（仮：1秒）ごとに `Game.advance` を呼び、帰還・自動再派遣が起きたら状態を通知する（§4）。
- **コマンドの ctx**：コマンドの処理では `PlayerSessions:ctxFor(session, true)` を使い、同じサーバーにいる友達の数を `ctx.friendCount` に入れる（§2.1。core の `ClaimFriendReward` が読む）。
- **新規プレイヤーの seed**：`Game.newState(master, seed, now)` の `seed` は、サーバーが Roblox の `Random` で1回だけ作る（1〜2^31−1）。以後の乱数はすべて core の `Rng`（08章）。`Random` を使うのはここだけ。

### 2.1 同じサーバーにいる友達の数（D-157、M7b-5）

フレンドボタン（`ClaimFriendReward`）の報酬は、同じサーバーにいる友達の数で決まる（06章 §20）。数はサーバーが数え、クライアントからは受け取らない。

- モジュール：`src/server/FriendCounter.luau`。
- 2人の組ごとに、友達かどうかを1回だけ Roblox に問い合わせて覚える（`Player:IsFriendsWithAsync(userId)`。`IsFriendsWith` は非推奨になり置き換わった）。友達の関係は対称なので、組の鍵は「小さい UserId:大きい UserId」。
- 人の出入りで数え直す：入ったら、その人と今いる全員の組を問い合わせる。出たら、その人の組を忘れる（`PlayerRemoving` の間はまだ一覧に残るので除く）。問い合わせは別の処理（`task.spawn`）で行い、参加・退出の処理を待たせない。同じ組を重ねて問い合わせない。
- 問い合わせに失敗した組は覚えず、次の出入りのときにもう一度問い合わせる（それまでは友達でないとして数える）。問い合わせの間にどちらかが出ていたら結果を捨てる。
- `count(userId)` は覚えた結果を数えるだけで、待ちを入れない（コマンドの処理中に呼ぶため）。入った直後は問い合わせが終わるまで 0 人と数えることがある。

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
2. 届け物の箱を読み出す（§3.6）。読めなくてもログインは止めない（届け物は残り、次のログインで受け取る）。
3. 読み込み中に退出した、またはサーバーが終了中なら、記録の中身を変えずにロックだけ解放して終わる（留守番を計算していないので `lastSavedAt` も進めない）。
4. 新規なら `Game.newState`、既存なら `Migration` で最新版に移行する。移行に失敗したら、中身を変えずにロックだけ解放して切断する。
5. **留守番**：`Game.advance(state, { online = false })` を1回だけ呼ぶ（05章 §3、06章 §13・§14、D-161・D-172・D-186）。
   - 留守の始まりは core の `Game.offlineStart(state)`＝`max(lastSavedAt, lastAdvancedAt)`。ログアウト時に出ていた探索は帰還させ、自動再派遣のパーティは留守番の探索（時間×10、最大6時間、全員帰還して終わる）を続ける。6時間より前のログインなら、帰っていない留守番の探索はログインの時点までに進んだフロアの分だけ持ち帰る。休息ボーナスを貯める。
   - advance のあと `lastAdvancedAt = ログイン時刻` になるので、以後のオンラインの advance（§2）が留守を数え直すことはない。
   - 続けて、ログインした時刻を core の `Notify.recordLogin(state, ログイン時刻, master)` で記録する（1日の中の位置。直近7回まで。ゲーム外の通知の「いつも遊ぶ時刻」：§8.3、D-196）。ログイン1回につき1回だけ。
6. 受け取った届け物を受け取り箱へ入れる（§3.6）。
7. セッションを作り、クライアントに状態を通知する（§4、`reason = "load"`。留守番の結果と届け物の events を含む）。5〜7 の間は待ちを入れない（退出や定期の advance が割り込まないように）。
8. 届け物を受け取り箱へ入れたときは、すぐ保存してから届け物を消す（§3.6）。

### 3.3 保存

| いつ | 内容 |
| --- | --- |
| 定期保存 | `autosaveSeconds`（仮：60秒）ごと。変更がなくても `session.at` を更新する（ロックの生存確認） |
| 退出時（PlayerRemoving） | 保存してロックを解放（`session = nil`）し、セッションを消す |
| サーバー終了時（BindToClose） | 全員を並行して保存・解放し、先に始まっている退出時の保存・読み込みも含めて終わるまで待つ（`closeWaitSeconds`＝25秒まで。Roblox の制限は30秒）。終了中に読み込みが終わったプレイヤーは、ロックを解放して終える |

- **最後に保存した時刻**：セッションの状態を保存するたびに（定期保存・退出時・サーバー終了時・届け物の受け取り後）、書く直前に `state.lastSavedAt = os.time()` を入れる（03章、D-161 の留守の始まり）。読み込み中の退出・移行の失敗でロックだけ解放するときは、読んだ記録をそのまま書き戻し、`lastSavedAt` を進めない。
- 保存は必ず `UpdateAsync` で行い、記録の `session.jobId` が自分であることを確認してから書く。自分でなければ（ロックを失った）書かずに、そのプレイヤーをキックする（二重ログインでの上書き防止）。
- DataStore のエラーは `saveRetryCount`（仮：3回）まで待ち時間を倍にしながら再試行する（1秒・2秒・4秒）。
- 保存の直前に、そのプレイヤーの処理中のコマンドが終わっていること（§4.4 の順番待ち）を確認する。
- 開発中のセーブデータは本番と同じ DataStore に入る（D-100）。公開前の扱いは M9 までに決める。

### 3.4 ロックの判定は純粋な関数にする

`src/server/SessionLock.luau`：`decide(record, myJobId, now, timeout) → "take" | "wait"`、`canSave(record, myJobId) → boolean`。Roblox API を使わないので Lune でテストする（新規・自分・他人の有効なロック・期限切れ・ロック喪失）。

### 3.5 同じ留守を二重に計算しない（M7b-5）

留守番の advance は、ロックを取って読み込んだあと、ログイン1回につき1回だけ呼ぶ（§3.2 の5）。その結果は、次の保存で `lastSavedAt`・`lastAdvancedAt` とともに書かれる。

- **同じプレイヤーの読み込み・保存を、サーバーの中で1つずつ行う**（`PlayerSessions` の `withUser`）。読み込み（ロック待ちを含む）・定期保存・退出時の保存・終了時の保存は、同じプレイヤーの前の処理が終わるまで待つ。待っている間も「処理中」に数え、サーバー終了時に待つ。
  - 理由：同じサーバーへすぐ入り直すと、ロックの `jobId` が自分なのですぐ取れる。退出時の保存が終わる前に読むと、古い記録から留守を計算し直してしまう（オンラインで受け取った探索をもう一度受け取る）。さらに退出時の保存がロックを解放するので、新しいセッションがロックを失う。
- **定期保存**は、一覧を先に写してから1人ずつ保存し、待っている間にセッションが入れ替わっていたら（退出・入り直し）保存しない。ロックを失ったときに消すセッションは、保存した同じセッションのときだけ。

場合ごとの確認：

| 場合 | 結果 |
| --- | --- |
| 別のサーバーがロックを持っていて再試行する | ロックを取るまで留守番を計算しない。取れなければ計算せずにキック |
| 読み込みに失敗して切断する（DataStore のエラー・移行の失敗） | 留守番を計算しない。移行の失敗は記録をそのまま書き戻してロックだけ解放 |
| 読み込み中に退出した・サーバーが終了中 | 留守番を計算しない。記録をそのまま書き戻し、`lastSavedAt` を進めない |
| 別のサーバーへすぐ入り直す | 前のサーバーの退出時の保存（留守番の結果と `lastSavedAt` を含む）がロックを解放するまで、新しいサーバーは読み込まない（§3.2 のロック待ち） |
| 同じサーバーへすぐ入り直す | 退出時の保存が終わるまで読み込みを待つ（`withUser`） |
| 留守番を計算したあと、保存する前にサーバーが落ちた | 留守番の結果は保存されていないので、次のログインで前の保存から計算し直す（二重には受け取らない。落ちる前のオンラインの進み具合は失われ、その時間は留守として数える） |

### 3.6 届け物（D-180）

他のプレイヤー宛ての報酬（紹介で招待した側への報酬など）は、相手のセーブを直接書き換えず、**プレイヤーのセーブとは別の DataStore** に「届け物」として置く。受け取る側が次のログインで読み出し、受け取り箱へ入れたら消す。

| 項目 | 内容 |
| --- | --- |
| DataStore 名 | `Deliveries_v1`（仮。`Config.deliveryStoreName`） |
| キー | `delivery_<届け先の UserId>`（`Config.deliveryKeyPrefix`） |
| 値 | `{ items = { { id, kind, fromUserId, at, data? } } }` |

- `id`：書き込む側が決める識別子（例：紹介なら `referral:<招待された人の UserId>`）。同じ `id` は箱に1つだけ（書き込む側の再試行で二重にしない）。
- `kind`：種類（例：`"referral"`）。報酬の中身は届け物に入れず、受け取る側の core がマスターデータから決める。`data` は種類ごとの補足（任意）。
- 箱に置ける数は `deliveryMaxItems`（仮：100）まで。超えたら書かずに警告する。
- モジュール：`src/server/Deliveries.luau`。
  - `push(toUserId, id, kind, fromUserId, data?) → "ok" | "duplicate" | "full" | "error"`：`UpdateAsync` で足す。届け先がオンラインでも書いてよい（ロックのある記録には触れない）。受け取りは次のログイン。
  - `read(userId) → (ok, items)`：`UpdateAsync` で読み、書かずに中止する（キャッシュの古い値を読まない）。
  - `remove(userId, ids) → ok`：`UpdateAsync` で、受け取ったものだけを `id` で消す。読み出したあとに届いた別の届け物は残る。
- ログイン時（§3.2）：ロックを取ったあとに読み出し、留守番のあとで1つずつ受け取り箱へ入れる。入れたらすぐプレイヤーのセーブを保存し、**保存できたものだけ**届け物から消す（先に消すと、落ちたときに届け物を失う）。保存できなかったものは残り、次のログインでもう一度受け取る。
- 受け取り箱へ入れる処理は core の `Game.grantDelivery`（`GrantReferral`、role = "inviter"）。受け取れなかったもの（週の上限など）は箱に残し、翌週に受け取る（D-192）。前に受け取り済み（同じ id）なら消してよい。
- 書き込むきっかけは §3.7。

### 3.7 紹介の届け物を書くきっかけ（D-157・D-180・D-192・D-195・D-197、M7b-5）

紹介の報酬は、招待した側・された側とも、**招待された人が一定の進み具合に届いたとき**に渡す（D-192。サブアカウントでの不正対策）。モジュール：`src/server/Referral.luau`。

1. **招待した人の記録**：参加したときの `Player:GetJoinData().ReferredByPlayerId`（招待した人の UserId）。**新規のプレイヤー（初めての参加）のときだけ** `state.referral.referredBy` に入れる（03章。サーバーが入れる：D-195）。既存のプレイヤーが招待のリンクから入っても記録しない。正の整数でない・自分自身なら入れない。読み込みの中（留守番の前）で行い、待ちを入れない。
2. **進み具合の判定**：core の `Friend.referralProgressReached(state, master)`（条件はマスターデータの `referralProgressCondition`。これまでに転生した回数の累計 `stats.rebirths` で数え、解雇で戻らない：D-195）。コマンドのあと・時間経過で何か起きたあと・読み込みのあとに `PlayerSessions:checkReferral(session)` で確かめる（待ちを入れない）。`referredBy` があり、まだ「届けた」印がなく、届いていたら、別の処理で次の 3 を行う。
3. **届ける**：
   1. 招待した人の届け物の箱に書く（§3.6 の `push`。`id = "referral:<招待された人の UserId>"`、`kind = "referral"`、`fromUserId = 招待された人`）。招待した人のセーブ（他人のセーブ）には触れない。
   2. `"ok"`・`"duplicate"` なら、そのプレイヤーのコマンドの順番（`busy`）を取ってから、`Friend.markInviterDelivered` で「届けた」印を付け、`GrantReferral`（role = "invitee"、userId = 招待した人）を実行する。結果はクライアントに差分で知らせる（§4.2 の `reason = "server"`）。
   3. `"error"`（書き込みの失敗）なら印を付けず、`referralRetrySeconds`（仮：60秒）たってから次の確認でもう一度書く。
   4. `"full"`（招待した人の届け物の箱がいっぱい）なら印を付けず、そのセッションでは試し直さない（`referralRetryAt = math.huge`）。招待された人の次のログインでもう一度書く（D-197。60秒ごとに試し続けない）。
   - 書いている間に退出したら印を付けない（次のログインでもう一度書く）。
4. **二重にならない理由**：印は次の保存で書かれる。書く前に落ちたら、次のログインでもう一度届け物を書くが、同じ `id` なので、招待した人がまだ受け取っていなければ `"duplicate"`、受け取り済みなら core の `claimedDeliveries` が二重の受け取りを防ぐ。招待された人の報酬は `inviteeRewardDone` で1回だけ。
- 他のプレイヤーの UserId（`referredBy`・`rewardedInvitees`・`claimedDeliveries`）はクライアントに送る要約から除く（D-192。core の `Protocol.view` で行う）。
- 招待された側の報酬（`GrantReferral`、role = "invitee"）で招待した人がいるかは、サーバー専用のコマンドなのでサーバー（`Referral.luau`）が確かめる。core では確かめない（D-195）。

## 4. 通信（D-101、D-103）

`ReplicatedStorage.Remotes` に2つ置く（Rojo の設定 `default.project.json` で宣言する）。

| 名前 | 種類 | 向き | 用途 |
| --- | --- | --- | --- |
| `Command` | RemoteFunction | クライアント → サーバー → 結果を返す | 05章のコマンドを送る |
| `StateChanged` | RemoteEvent | サーバー → クライアント | 起きたことと、状態の要約の差分を送る |
| `WorldChanged` | RemoteEvent | サーバー → クライアント | 同じサーバーの他プレイヤーのパーティの位置（M8、§6。D-121） |

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
- `server` はコマンド・時間経過以外でサーバーが状態を変えたとき（紹介の報酬：§3.7）。形は差分と同じ。
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

- 形の検証は `src/core/Protocol.luau` の `Protocol.validateCommand(command) → (ok, err)` で行う。type ごとに引数の型・範囲を決めた表を持つ（数値は整数か・範囲内か、文字列は長さの上限、配列は要素数の上限）。中身の正しさ（所持金・職業制限など）は従来どおり `Game.execute` が判定する。
- 送りすぎ：1人あたり `commandRateLimit`（仮：1秒に10回）を超えたら `RATE_LIMITED`。
- 1人のコマンドは到着順に1つずつ処理する（保存の待ちなどで処理が重ならないように）。

### 4.5 状態の要約（view）と隠す情報

`Protocol.view(state, master, now)` で作る（純粋な関数。Lune でテストする）。

- 送らないもの：`seed`・`rngCounter`・各探索の `seed`（乱数の予測を防ぐ）、`nextUid`、`stats`（集計用）、`lastAdvancedAt`（時間経過のたびに変わるだけで表示に使わない。送ると差分が毎秒出る）、`loginTimes`（通知の時刻を決めるのにサーバーが使うだけ：D-196）。
- 足すもの：`notifyPromptDue`（通知の許可の画面を今出すか。`"firstReturn"` / `"loginDay2"` / nil。core の `Game.query.notifyPromptDue`。初めての帰還は `stats` にあり送らないので、ここで判定して渡す：D-196）。
- 宝箱（D-087・D-166）：`chests`（ランク別の数）の代わりに、宝箱の山ごとの数 `{ { pileKey, count } }`（特別な宝箱の山を含む。ランクなし）を送る。
- 他のプレイヤーの UserId（D-192）：`referral` から `referredBy`・`rewardedInvitees`・`claimedDeliveries` を除く。event の `ReferralGranted` の `userId` も除く（`Protocol.redactEvents`）。
- 探索ログ：宝箱のランクを取り除き、個数だけ残す（`Protocol.redactLog`）。`floors[].detail.ranks` → `detail.chestCount`、`rewards.chests` → `rewards.chestCount`、`clearChestRanks` → `clearChestCount`。
- events：`ExpeditionReturned` など、宝箱のランクを含むものは同じ規則で取り除く。開封結果（`ChestsOpened`）は開けた後なのでランクを含めてよい（演出の `effect` と派手さの `rank` に使う）。
- それ以外の状態（冒険者・パーティ・装備・アイテム・面接や転生の途中の結果など）はそのまま送る。

## 5. クライアント（M7 はデバッグ用の簡易画面のみ）

- 入口（`src/client/Main.client.luau`）で `Core`・`Data`・`Remotes` を `WaitForChild` で待ってから require する（§1）。
- 起動時に `Sync` を送って全体と連番を受け取り、以後は `StateChanged` の差分を `Protocol.applyPatch` で手元の要約に適用して表示する。連番が合わなければ `Sync` で取り直す（§4.3）。`Sync` の応答より前に届いた差分は捨てる（`Sync` の連番以下のもの）。
- 画面：状態の一覧（テキスト）と、テキスト版（09章 §1）と同じ書式でコマンドを打つ入力欄、結果のログ。見た目は作らない（UI は M8）。
- テキストの書式をコマンドに変える処理は、テキスト版と共通にする（`tools/cli` から `src/core/CommandText.luau` に切り出し、両方から使う。Lune でテストする）。
- 探索の現在位置などの表示用の計算は `Game.query.*` を使う。表示用の時刻は `workspace:GetServerTimeNow()` の整数部分。
- 宝箱の一覧は、特別な宝箱を含むすべての山を「山の鍵×数」で出す（§4.5）。
- `eventgo`・`buy` で時間帯を省いたら、送る前に今の時間帯（`Game.query.mapEvent(今, master).current.eventSlot`）で埋める（テキスト版と同じ）。
- `notify`：通知の許可の画面を出す（§8.4。設定画面に置くものの仮）。
- 要約が変わるたびに（表示の更新のたびに）`NotificationPrompt.onView(view, …)` を呼び、`notifyPromptDue` があれば許可の画面を出す（§8.4、D-196）。

## 6. マルチ表示（D-027、D-108、D-121。M8 で実装）

他プレイヤーのパーティは、マップに馬車だけを出し、タップで詳細を見せる（ゲーム仕様 11章 S-14）。

### 6.1 馬車の位置：`WorldChanged`

- 自分の状態通知（`StateChanged`、連番つきの差分）とは混ぜない。届かなくても自分のゲームには影響しないので、連番は付けず、届いたものをそのまま上書きする。
- 送る中身（プレイヤー1人分の公開情報）：`{ userId, guildLevel, parties = { { index, dungeonId, departAt, travelSeconds, totalSeconds } } }`。パーティは探索中のものだけ。位置はクライアントが出発時刻と時間から求める（D-026）。
- 送るとき：
  - 参加したプレイヤーへ、他の全員分をまとめて1回。
  - 誰かが出発・帰還したとき（オフライン分の帰還を含む）、そのプレイヤー分を全員へ。
  - 退出したとき、そのプレイヤーを消す知らせを全員へ。
- 自分自身の分は送らない（自分の馬車は自分の状態から描く）。

### 6.2 タップしたときの詳細：`Inspect` コマンド

- `Command` で `{ type = "Inspect", userId, partyIndex }` を送ると、そのパーティのメンバーの `name`・`jobId`・`level`・`appearanceId` とギルドLvを返す。状態は変えない（`Game.execute` を通さない読み取り専用）。回数制限（§4.4）の対象にする。
- 相手が同じサーバーにいない、パーティが探索中でない場合は `NOT_FOUND`。
- プレイヤー名とアバターアイコンは、クライアントが Roblox の API（`Players:GetNameFromUserIdAsync`・`Players:GetUserThumbnailAsync`）で取る。サーバーからは送らない。
- 返す中身を作る処理は `src/core` に置き、Lune でテストする（隠す情報を含めない）。

## 7. 確認方法（M7 の完了条件）

- Lune：`lune run tools/check`（`Protocol`（検証・要約・差分）・`CommandText`・`SessionLock` のテストを含む）。
- 差分：Studio で、操作のたびに届く通知が差分だけであること、連番を意図的に飛ばすと `Sync` で取り直して表示が正しく戻ることを確認する。差分の大きさの記録（§4.3）。
- Studio：Rojo で同期し、プレイテストで M2〜M5b の全コマンドをデバッグ画面から実行できる。退出→再参加で状態が戻る。参加時に留守番（D-161・D-172・D-186）の結果を受け取り、すぐ入り直しても（同じサーバー・別のサーバー）同じ留守を二重に受け取らない（§3.5）。
- 二重ログイン：同じプレイヤーのロックが残っている間は、別サーバーで読み込まない（`SessionLock` のテストと、記録を手で書き換えた確認）。

## 8. ゲーム外の通知（D-159・D-181・D-196、M7b-5）

Roblox のエクスペリエンス通知で、遊んでいないプレイヤーを呼び戻す。**1人1日1通まで**、**その日に一番効く1つ**を、**その人がいつも遊ぶ時刻**に送る。届くのは **13歳以上で通知を許可した人だけ**（Roblox 側が判定する。サーバーから許可・年齢を確かめる API はない）。

### 8.1 送る口

- Open Cloud の `CreateUserNotification`：`POST https://apis.roblox.com/cloud/v2/users/{userId}/notifications`。ゲームのサーバーから `HttpService:RequestAsync` で呼べる（Roblox の「In-game HTTP requests」の対応表に Notifications として載っている）。
- ヘッダーは `Content-Type: application/json` と `x-api-key`。API キーは Creator Hub の Secrets に `notifySecretName`（仮：`OpenCloudApiKey`、`apis.roblox.com` に結び付ける）で登録し、`HttpService:GetSecret` で読む（ヘッダーの値は Secret 型でなければならない）。Studio では「Allow HTTP Requests」を有効にする。
- 中身：`{ source = { universe = "universes/<game.GameId>" }, payload = { message_id, type = "MOMENT", parameters?, join_experience = { launch_data }, analytics_data = { category } } }`。
  - `message_id`：Creator Dashboard で登録した通知の文面（Notification strings）の id。API では登録できないので、コードには `Config.notifyMessageIds`（種類ごと。今は空＝送らない。仮）の口だけ置く。文面は99文字まで（D-159）。英語ベース。
  - `parameters`：文面への差し込みは `count`（宝箱の数・冒険者の数）だけ（`int64_value`）。
  - `launch_data`：`"notify:<種類>"`。通知から入ったときに開く画面へつなぐ（M8）。`category` は種類（効果の集計用）。
- Roblox の送信の呼び出しは `Notifications.luau` の `sendOne` の1か所にまとめる。要確認：API キーに要る権限の名前、エラーの状態コードの一覧（429 は1日の上限・送りすぎとされる）。

### 8.2 何を送るか（`src/server/NotificationPicker.luau`）

退出したときの状態を写し、core の留守番（`Game.advance`、`online = false`）を送る時刻まで進めた見込みから、D-159 の優先順位で最初に当てはまる1つを選ぶ。文面の id が空の種類は飛ばす。

| 順 | 種類 | 当てはまるとき |
| --- | --- | --- |
| ① | `loginUnique` | 送る時刻の日に、次に受け取るのが7日目で、その周のユニークがいる（あと1日でログインボーナスのユニーク） |
| ② | `offlineDone` | 退出時に出ていた探索があり、送る時刻が留守番の終わり（退出 + `offlineMaxSeconds`）以後。`count` は留守番で増える宝箱の数 |
| ③ | `dailyTrait` | 送る時刻の日の日替わりの特性が、自動再派遣にしているダンジョンに当たる（「得意」：D-196 ①） |
| ④ | `rebirthReady` | 留守番のあとで転生できる冒険者がいる。`count` はその人数 |
| ⑤ | `dailyReset` | いつも（デイリー更新） |

### 8.3 いつ送るか（`src/server/Notifications.luau`）

1. **予約**：退出したとき、送る時刻と種類を決めて MemoryStore の SortedMap（`notifyQueueName`）に置く。鍵 = UserId、並びの鍵 = 送る時刻、値 = `{ userId, kind, count?, sendAt }`。1人1つで、退出のたびに置き換える。寿命は送る時刻 + `notifyQueueExpirationSeconds`（仮：3日。上限45日）。
   - 送る時刻：その人がいつも遊ぶ時刻のうち、退出から `notifyMinAwaySeconds`（仮：6時間）以上あとの最初のもの（`NotificationPicker.sendAt`）。
   - いつも遊ぶ時刻：セーブの `loginTimes`（直近 `notifyLoginHistoryCount`＝7回のログイン時刻の、UTC の1日の中の位置。読み込みのたびに記録：§3.2 の5）の中央値（core の `Notify.usualTimeOfDay`。06章 §23、D-196 ②）。記録がなければ今回ログインした時刻の位置で代わりにする（読み込みで必ず1回足すので、ふつうは起きない）。
2. **取り消し**：参加したとき、予約を消す（遊んでいる人には送らない）。
3. **送信**：どのサーバーも `notifyPollSeconds`（仮：30秒）ごとに、送る時刻が来た予約を `notifyBatch`（仮：20件）まで取り出す。送る前に MemoryStore の HashMap（`notifySentMapName`）の「最後に送った日」（Calendar の日の番号、D-168）を `UpdateAsync` で今日に書き換え、書き換えられた1台だけが送る（1人1日1通。2台が同時に取り出しても1通）。送れなかったときも今日の1通は使ったことにする。取り出した予約は消す。このサーバーで遊んでいる人には送らない。
- 退出1回につき予約は1つなので、続けて何日も来ない人に毎日は送らない。
- 同じプレイヤーがすぐ入り直したとき、退出時の予約が参加時の取り消しより後に書かれることがある（別サーバーで遊んでいる間に送られうる）。まれなので受け入れる（D-196 ⑤）。
- 送る時刻に Roblox のサーバーが1台も動いていなければ送られない。今は受け入れる（D-196 ④。外部の定期実行は M9 で検討）。
- 公開していないプレイス（`game.GameId == 0`）では送らない。`notifyEnabled = false` なら予約も送信もしない。

### 8.4 許可を求める画面（D-159・D-181・D-196）

- `ExperienceNotificationService:CanPromptOptInAsync()`・`PromptOptIn()`・`OptInPromptClosed` は**クライアント専用**なので、クライアントの `src/client/NotificationPrompt.luau` から出す（サーバーを通さない）。`canPrompt()` が false（13歳未満・出したばかりなど）なら出さない。
- 出すとき（D-196 ③）：**初めての帰還**。そこで許可しなかったら**ログインボーナス2日目**にもう一度。
  - サーバーは状態の要約の `notifyPromptDue`（§4.5。core の `Notify.promptDue`）で知らせる：`"firstReturn"`＝初めての帰還（`stats.firstReturnAt`）のあとでまだ出していない、`"loginDay2"`＝firstReturn で出したあと、ログインボーナスの2日目を受け取っていてまだ出していない（06章 §23）。
  - クライアントは `NotificationPrompt.onView` で、出す機会なら `prompt()` を呼び、出したあと（出せなかったときも）`MarkNotifyPrompt`（stage）を送って記録を `settings.notifyPrompt` に保存する（設定と一緒にサーバーへ：D-117）。送れなかったら次の要約の変化でもう一度試す。同じ機会で2回出さないよう、記録が要約に届くまで処理中の機会を覚えておく。
  - 許可したかどうかはサーバーからは分からないので、2日目は `canPrompt()`（許可済み・13歳未満・最近出したなら false）で確かめ、false なら出さずに記録だけ付ける。
  - 初めての帰還のときに2日目をもう受け取っていたら（帰還より前に2日ログインした）、2日目の機会は過ぎたものとして一緒に記録する（続けて2回出さない）。
- 設定画面（S-61、D-181）からも `NotificationPrompt.prompt()` を呼ぶ。M8 の画面はまだないので、今はデバッグ画面の `notify` コマンドから呼ぶ。
