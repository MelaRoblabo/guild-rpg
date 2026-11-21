# M7-0 require 方式の検証（2026-11-21）

darklua で require を変換せずに、Roblox の文字列 require（require-by-string）だけで `src/core`・`src/data` が動くかを確かめた。

## 環境

- Rojo 7.7.1（CLI・Studio プラグイン）、Lune 0.11.1、darklua 0.19.0（今回は使っていない）
- Studio：プレイス「冒険者ギルド」（D-100）。Edit → プレイテスト（サーバー＋クライアント）
- 一時的な Rojo 設定で `src/core` → `ReplicatedStorage.Core`（Folder）、`src/data` → `ReplicatedStorage.Data`（init.luau が ModuleScript、各ファイルがその子）を変換なしで同期した。
- テスト用スクリプトは Studio MCP で一時的に入れ、確認後に削除した。

## 確認したことと結果

| # | 確認したこと | 書き方 | 結果 |
| --- | --- | --- | --- |
| 1 | `src/core` 内の兄弟の require | `require("./Rng")` など（変更なし） | ✅ サーバー・クライアントとも動く |
| 2 | フォルダの入口（init.luau）から子の require | `require("@self/Constants")` | ✅ `Data` が読み込める |
| 3 | 別のサービスからの require | サーバー（ServerScriptService）から `require("@game/ReplicatedStorage/Core/Game")` | ✅ 動く。同じ場所の兄弟は `require("./X")` で動く |
| 4 | クライアントで、開始直後に require | LocalScript（StarterPlayerScripts）の先頭で `@game/ReplicatedStorage/...` | ✅ Studio のプレイテストでは失敗しなかった |

サーバーでは、マスターデータの読み込み → `Game.newState` → `Dispatch` → `advance`（600秒後）→ `OpenChests` まで通った（所持金 578、開封 ok）。

## Lune 側の対応（同じ M7-0 で実施）

- Lune 0.11 では init.luau の `./X` の意味が変わったため、`src/data/init.luau` と `tools/*/init.luau` を `@self/X`（自分のフォルダ内）と `../X`（1つ上）に書き換えた。Roblox の規則と同じになった。
- `process.spawn` → `process.exec`（`tools/check`）。
- `lune run tools/check` 成功（テスト 185 件）。

## わかったこと・注意点

- Roblox は `.luaurc` の別名（alias）を読まないので、Lune と Roblox の両方で動かすコードは `./`・`../`・`@self` だけを使う。`@game/...` は Roblox でしか解決できない。
- そのため、`src/server`・`src/client` から core を呼ぶときは `@game/ReplicatedStorage/Core/...` と書き、これらは Lune では実行しない（Roblox API を使う接着部分だけにする）。Lune でテストしたい純粋な処理は `src/core` に置く。
- 4 は Studio での結果。本番サーバーではクライアントへの複製が遅れる可能性が残るため、クライアントの入口で一度だけ `ReplicatedStorage:WaitForChild("Core")`・`WaitForChild("Data")` を待ってから require する。

## 提案

darklua を外し、Rojo で `src/` を直接同期する（`build/` を経由しない）。

- `default.project.json` の `$path` を `build/*` → `src/*` に変更、`.darklua.json` を削除、`rokit.toml` から darklua を外す。
- CLAUDE.md §3（「Roblox向けには darklua で変換する」）、システム仕様書 01・02・11章を更新する。
- 決定ログに起票する（D-031 の Rojo・GitHub は変わらない）。
