# 11 Roblox組み込み（M7の方針）

M7開始時に詳細化する。ここでは、M0〜M6の設計がM7を妨げないための前提だけを決める。

## 1. ビルド

```
src/（文字列 require）──darklua process──▶ build/（Roblox の require に変換）──rojo──▶ Roblox
```

- `src/core` と `src/data` は ReplicatedStorage に置く（サーバーとクライアントの両方で使う。クライアントは表示用の計算と再生にのみ使う）。
- `src/server` は ServerScriptService。

## 2. サーバー権限

- 状態の変更はすべてサーバーで `Game.execute` / `Game.advance` を実行する。クライアントはコマンドを送るだけ。
- 乱数・探索ログの確定・購入の付与はサーバーのみ。
- クライアントには状態の差分と探索ログを送り、再生はクライアントで行う。

## 3. 保存

- DataStore をセッションロック付きで使う（ProfileStore 等の採用はM7で決定）。
- 保存するのは `PlayerState` そのもの（03章）。`version` で移行する。

## 4. マルチ表示（D-027）

- 他プレイヤーの表示に必要なのは、各パーティの `dungeonId`・`departAt`・`travelSeconds`・`totalSeconds` だけ。M8で実装。
