# 04 マスターデータ

ゲームの数値・確率・コンテンツはすべてここに置く。コードに数値を書かない（CLAUDE.md）。項目の一覧はゲーム仕様書12章。

## 1. 形式

- `src/data/<Name>.luau` が Luau のテーブルを `return` する。RobloxでもLuneでもそのまま読める。
- 1ファイル1種類。行は配列、各行は一意の `id`（snake_case、接頭辞付き）を持つ。
- 公開後は `id` を変えない（セーブデータが参照するため）。

| ファイル | 内容 | 接頭辞 |
| --- | --- | --- |
| `Constants.luau` | 定数（下表） | — |
| `Rarities.luau` | レアリティ | `rar_` |
| `Jobs.luau` | 職業 | `job_` |
| `Gifts.luau` | ギフト | `gift_` |
| `Modifiers.luau` | 修飾語 | `mod_` |
| `EquipmentBases.luau` | 基本アイテム | `eq_` |
| `Items.luau` | アイテム | `itm_` |
| `Dungeons.luau` | ダンジョン | `dng_` |
| `Monsters.luau` | モンスター | `mon_` |
| `LootTables.luau` | 抽選テーブル | `lt_` |
| `Appearances.luau` | 見た目（240種） | `chr_` |
| `Names.luau` | 名前リスト | — |
| `Uniques.luau` | ユニークキャラ | `uni_` |
| `GuildLevels.luau` | ギルドレベル | — |
| `Expansions.luau` | 拡張 | `exp_` |
| `StarterSet.luau` | 初期状態（Q-020） | — |

## 2. 検証（MasterData.luau）

起動時（CLI・シミュレーター・サーバー）に必ず検証し、1つでも違反があれば**起動しない**。

- `id` の重複がない。参照先の `id` が存在する。
- 確率の表は合計が 1（許容誤差 1e-9）。重み表は全部 0 以上で合計 > 0。
- 必須項目が揃っている。数値の範囲（確率は 0〜1、レアリティは 1〜5 など）。
- 見た目は 16 カテゴリ × 15 種が揃っている（コンテンツが揃うまでは警告に留めるフラグを持つ）。

## 3. 定数（Constants.luau）の初期値

「仮」はM6で調整する。

| キー | 値 | 根拠 |
| --- | --- | --- |
| `hitWeights` | {0.45, 0.25, 0.20, 0.10} | D-005 |
| `critCoef` / `critCap` / `critMult` | 200 / 0.30 / 1.5 | D-010 |
| `maxTurns` | 30 | D-009 |
| `monsterScalePerBattle` | 0.20 | D-003 |
| `eventWeights` | 宝箱0.40 / アイテム0.15 / 罠0.20 / 泉0.10 / なし0.15 | D-014 |
| （宝箱のレアリティ） | ダンジョンごとの `chestRarityWeights`（§4） | D-085 |
| `fountainHealRate` | 0.25 | D-018 |
| `trapK` / `trapDamageRate` | 40 / 0.20（ダンジョンごとに上書き可） | D-017, D-067 |
| `healThreshold` / `healCoef` | 0.70 / 0.30（仮） | D-034, Q-004 |
| `luckyChancePerHolder` / `luckyChanceCap` | 0.30 / 0.60 | D-070 |
| `travelSecondsPerDistance` / `travelSpeedMin` / `travelSpeedMax` | 10 / 0.6 / 1.4 | D-069 |
| `replaySecondsPerTurn` / `replaySecondsPerEvent` | 1 / 2 | D-026 |
| `personalBonusCap` | 0.50 | D-070 |
| （道案内・大食らいの効果量はギフトのデータに持つ） | — | 04章 §5 |
| `growthVariance` | 1（±1、最低0） | D-043 |
| `expBase` / `expExponent` / `expCycleMult` | 100 / 1.5 / 周回ごとの倍率（`tools/sim/progression` が自動調整） | D-071 |
| `levelCapInitial` / `levelCapPerRebirth` / `levelCapMax` | 20 / 10 / 100 | D-071 |
| `rebirthExpBonusPerCount` | 0.5（仮） | 07章 |
| `rebirthGiftAddAt` / `giftMax` | {2, 4, 6} / 4 | D-024 |
| `rebirthBonusMaxRate` / `rebirthBonusSkewBase` / `rebirthBonusSkewPerRebirth` | 0.30 / 1.0 / 0.5 | D-072 |
| `rebirthFreeRerolls` | 3（初回を含まない、仮） | Q-009 |
| `rebirthCost` | 2千 / 5千 / 2万 / 8万 / 30万 / 100万 / 300万 / 800万G（転生1〜8回目、仮） | D-080 |
| `expBonusCap` | 1.00（経験値補正の合計の上限、仮） | D-082 |
| `trainGoldCoef` / `trainGoldExponent` | 10 / 2（1回 = 10 × Lv²、仮） | D-076 |
| `trainingFacility` | Lv1〜5：上限 Lv10/20/30/40/50、1回の経験値 430/820/1200/1630/2060（仮） | D-077 |
| `hireCost` | 300G（仮） | Q-006 |
| `hireStatRange` | 4項目 1〜40、HP 20〜80。ギルドの成長に関係なく一定（仮） | Q-006, D-081, D-086 |
| `hireFreeRerolls` | 3（初回を含まない、仮） | Q-006 |
| `specialVisitorChance` | 0.005（仮） | 02章 |
| `appearanceGenderWeights` | m 0.5 / f 0.5 | D-050 |
| `appearanceLooksWeights` | 美形0.15 / 普通0.50 / ブサイク0.20 / 亜人0.15 | D-050 |
| `gradeWeights` | +0:0.74 / +1:0.20 / +2:0.05 / +3:0.01（仮） | 06章 |
| `modifierChance` | 0.40（仮） | 06章 |
| `potionChanceRarePlus` | 0.05、内訳 転職0.40 / 見た目変更0.30 / 見た目維持0.30（仮） | Q-011 |
| `itemEventWeights` | チケット0.60 / 売却用0.40（仮） | Q-011 |
| `sellRarityMult` | 1 / 1.5 / 2.5 / 4 / 7 / 12（仮。レアリティの数だけ） | 06章, D-085 |
| `sellGradeCoef` | 0.5（仮） | 06章 |
| `equipRarityMult` | 1.0 / 1.3 / 1.7 / 2.2 / 3.0 / 4.0（仮。レアリティの数だけ） | Q-020, D-085 |
| `equipGradeCoef` / `equipTierMult` | 0.10 / 1.30（仮） | Q-020, D-069 |
| `guildExpPerFloor` / `guildExpClearBonus` / `guildExpFirstClear` | 1 / 5 / 50（仮） | Q-017 |
| `guildLevelMax` | 20（仮） | Q-017 |
| （宝箱の保管上限） | なし（旧 `chestStorageMax` 500 は廃止） | D-084 |
| `chestBatchOpen` | 100（まとめて開く個数） | D-089 |

## 4. ダンジョン（D-068, D-069）

- 12ダンジョン。`src/data/Dungeons.luau` は **`tools/sim/calibrate.luau` が `tools/sim/DungeonTemplates.luau` から生成する**（手で編集しない）。
- 調整の考え方：各ダンジョンに「想定段階」（`tools/sim/Stages.luau`。転生回数・レベル・装備）を割り当て、その段階のバランス編成で
  踏破率約60%（古い墓地は約97%）、所要秒が目標（50秒 → 150秒）になるよう、強さ・距離・罠レベル・経験値を自動で決める。
- 数値を変えたいときは、テンプレートの目標値か段階の想定を変えて `lune run tools/sim/calibrate` を再実行する。
- 宝箱のレアリティの出現率 `chestRarityWeights`（D-085）もテンプレートに書き、calibrate がそのまま写す（%、[1]=コモン…）。

| ダンジョン | コモン | アンコモン | レア | エピック | レジェンド | ミシック |
| --- | --- | --- | --- | --- | --- | --- |
| 古い墓地 | 80 | 20 | | | | |
| 罠の遺跡 | 70 | 25 | 5 | | | |
| 封印の塔 | 55 | 32 | 11 | 2 | | |
| 騎士の古城 | 42 | 36 | 17 | 5 | | |
| 水没神殿 | 31 | 37 | 23 | 8 | 1 | |
| 霧の大森林 | 21 | 36 | 29 | 12 | 2 | |
| 地下大迷宮 | 13 | 32 | 33 | 17 | 5 | |
| 呪われた修道院 | 7 | 26 | 35 | 23 | 8 | 1 |
| 鋼鉄の要塞 | 3 | 20 | 34 | 29 | 12 | 2 |
| 竜の巣 | 1 | 14 | 31 | 33 | 17 | 4 |
| 魔界の門 | 0 | 9 | 27 | 36 | 22 | 6 |
| 天空の玉座 | 0 | 5 | 22 | 37 | 27 | 9 |

- 開けるときの演出の発生ライン `chestEffectMinRarity`（D-089、仮）：古い墓地・罠の遺跡 アンコモン以上／封印の塔・騎士の古城 レア以上／水没神殿〜地下大迷宮 エピック以上／呪われた修道院〜魔界の門 レジェンド以上／天空の玉座 ミシック。
- 解錠技術 `exp_unlock`（D-088、仮）：初期は難度2（古い墓地・罠の遺跡）まで。難度4（5千G・ギルドLv5）／6（5万G・Lv15）／8（30万G・Lv30）／10（150万G・Lv45）／12（500万G・Lv60）。
- **レアリティを増やすとき（D-085）**：`Rarities.luau` の末尾に行を足し、`equipRarityMult`・`sellRarityMult` を同じ長さに伸ばし、出したいダンジョンの `chestRarityWeights` に値を足し、必要なら `chestEffectMinRarity` を見直す。検証が長さの食い違いをエラーにする。
- 派遣費 `dispatchFee`（D-079）はテンプレートに書き、calibrate がそのまま写す。難度7以降のみ（仮：1千〜3万G）。
- 結果の確認は `lune run tools/sim -- sweep`。報告は `docs/reports/M1b_balance.md`。

## 5. 職業（Jobs.luau）

ゲーム仕様書03章の成長表どおり。各行：`id, name, line（warrior/scout/mage/support）, attackType（physical/magic）, isRare, growth{str,mag,agi,dex,hp}, equipKinds{...}, heals（boolean）, outfitClass（phy/mag）`。

## 6. 初期状態（StarterSet.luau、Q-020 仮）

- 所持金 500G、パーティ枠1、候補枠3、所属枠8、倉庫300（D-071）。
- 冒険者4人（戦士・盗賊・魔法使い・僧侶 各1、Lv1、基礎ステータスは固定値）を初期パーティの隊列1〜4に配置。各自コモンの武器・防具を装備。
- 「最初の宝箱を1分以内」（01章）を満たすよう、古い墓地の初回は確実に宝箱1個以上（踏破確定宝箱）を得られる強さにする。
