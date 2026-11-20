# 冒険者ギルドRPG（仮）

Roblox向けの冒険者派遣・収集・育成型ギルド運営RPG。

- 企画概要書・ゲーム仕様書・決定ログ：Notion（「冒険者ギルドRPG」ページ配下）
- システム仕様書：`docs/system/`（入口は `docs/system/00_index.md`）
- AI向け開発ルール：`CLAUDE.md`

## 開発方針

ロジック先行（D-066）。ゲームロジックをRobloxの外（Lune）でテキストだけで遊べる状態にし、AIによるテストプレイとバランス調整を済ませてから、Robloxへの組み込みとUIの当て込みを行う。

## セットアップ（M0で整備）

```bash
rokit install
```

```bash
lune run tools/test
```

```bash
lune run tools/cli
```
