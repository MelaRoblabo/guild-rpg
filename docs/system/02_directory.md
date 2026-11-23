# 02 フォルダ構成

```
guild-rpg/
├─ CLAUDE.md                 AI向け開発ルール（最初に読む）
├─ README.md
├─ rokit.toml                ツールのバージョン固定（rojo / lune / selene / stylua）
├─ default.project.json      Rojo 設定（src/ を変換せずに Roblox に同期。D-102）
├─ selene.toml / stylua.toml
├─ docs/
│  ├─ system/                システム仕様書（本書）
│  └─ decisions/INDEX.md     決定ログのスナップショット（Notionが正）
├─ src/
│  ├─ core/                  ゲームロジック。Roblox API 禁止。状態を持たない関数群
│  │  ├─ Game.luau           窓口：execute / advance / newState
│  │  ├─ Types.luau          状態・マスターデータ・コマンド・イベントの型
│  │  ├─ Rng.luau            乱数（08章）
│  │  ├─ Calendar.luau       日・週の番号を ctx.now から出す（06章 §11、D-168, D-184）
│  │  ├─ Formulas.luau       計算式（06章）。他モジュールは式をここから使う
│  │  ├─ MasterData.luau     マスターデータの読み込みと検証（04章）
│  │  ├─ Combat.luau         戦闘1回分
│  │  ├─ Events.luau         イベントフロア1回分
│  │  ├─ Expedition.luau     探索全体の計算・ログ生成・再生位置の計算
│  │  ├─ Party.luau          パーティ編成
│  │  ├─ Hiring.luau         雇用・面接
│  │  ├─ Growth.luau         経験値・レベルアップ
│  │  ├─ Rebirth.luau        転生
│  │  ├─ JobChange.luau      転職
│  │  ├─ Appearance.luau     見た目・名前の抽選
│  │  ├─ Chest.luau          宝箱の中身抽選・開封
│  │  ├─ Inventory.luau      倉庫・アイテム・装備の付け外し・売却
│  │  ├─ Guild.luau          ギルドレベル・拡張・ダンジョン解放
│  │  └─ Migration.luau      セーブデータの移行
│  ├─ data/                  マスターデータ（Luauテーブル。04章）。M7b で DailyTraits・Quests・LoginBonus・
│  │                         PlaytimeRewards・SpecialChests・MapEvents・Merchant を追加（D-152〜D-166）
│  ├─ server/                Roblox サーバー（M7で作成）
│  └─ client/                Roblox クライアント（M7は簡易画面のみ、UIはM8）
├─ tools/                    Lune で動く開発ツール
│  ├─ cli/                   テキスト版（09章）
│  ├─ sim/                   探索シミュレーター（09章）
│  ├─ autoplay/              自動プレイヤーと方針（09章）
│  ├─ test/                  テストランナー（10章）
│  └─ check/                 format・lint・test をまとめて実行
├─ tests/                    テスト（*.spec.luau）
└─ out/                      シミュレーション結果・レポート（git管理外）
```

## 依存の向き（守ること）

- `tools/*` → `src/core` → `src/data`（参照のみ）
- `src/server` / `src/client` → `src/core`
- `src/core` から `tools`・`server`・`client` を参照しない。
- `src/core` 内の依存：`Game` → 各機能モジュール → `Formulas` / `Rng` / `Types`。機能モジュール同士の循環参照は禁止。
