# 11 Roblox組み込み（M7の方針）

M7開始時に詳細化する。ここでは、M0〜M6の設計がM7を妨げないための前提だけを決める。

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

## 2. サーバー権限

- 状態の変更はすべてサーバーで `Game.execute` / `Game.advance` を実行する。クライアントはコマンドを送るだけ。
- 乱数・探索ログの確定・購入の付与はサーバーのみ。
- クライアントには状態の差分と探索ログを送り、再生はクライアントで行う。

## 3. 保存

- DataStore を直接使い、セッションロック付きの保存を自前で作る（D-099。ProfileStore 等の外部ライブラリは使わない）。詳細は M7-1 で書く。
- 保存するのは `PlayerState` そのもの（03章）。`version` で移行する。

## 4. マルチ表示（D-027）

- 他プレイヤーの表示に必要なのは、各パーティの `dungeonId`・`departAt`・`travelSeconds`・`totalSeconds` だけ。M8で実装。

## 宝箱のレアリティを隠す（D-087）

- 宝箱のランクはサーバーの状態にだけ持つ。クライアントには `Game.query.chestsByDungeon`（ダンジョンごとの数）だけを送る。
- 探索ログ（再生用）をクライアントに送るときは、宝箱イベントのランク（`detail.ranks`、`rewards.chests[].rank`）を取り除く。個数だけ残す。
- 開封結果（`ChestsOpened`）は開けた後なので、ランクを含めて送ってよい。演出の有無（`effect`）と派手さ（`rank`）はここから決める。
