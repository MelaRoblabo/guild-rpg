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
| `minDamageRate` | 0.10（最低1） | D-007 |
| `critCoef` / `critCap` / `critMult` | 200 / 0.30 / 1.5 | D-010 |
| `maxTurns` | 30 | D-009 |
| `monsterScalePerBattle` | 0.20 | D-003 |
| `eventWeights` | 宝箱0.40 / アイテム0.15 / 罠0.20 / 泉0.10 / なし0.15 | D-014 |
| `chestRankOffsets` | +0:0.60 / +1:0.25 / +2:0.10 / +3:0.05 | D-015 |
| `fountainHealRate` | 0.25 | D-018 |
| `trapK` / `trapDamageRate` / `trapLevelCoefStep` | 10 / 0.15 / 0.25（仮） | D-017, Q-004 |
| `healThreshold` / `healCoef` | 0.70 / 0.30（仮） | D-034, Q-004 |
| `luckyChancePerHolder` / `luckyChanceCap` | 0.15 / 0.40（仮） | Q-004 |
| `travelSecondsPerDistance` / `travelAgiDivisor` | 10 / 50（仮） | Q-004 |
| `replaySecondsPerTurn` / `replaySecondsPerEvent` | 1 / 2 | D-026 |
| `personalBonusCap` | 0.30 | D-033 |
| （道案内・大食らいの効果量はギフトのデータに持つ） | — | 04章 §5 |
| `growthVariance` | 1（±1、最低0） | D-043 |
| `expCurve` | 必要経験値＝floor(100 × Lv^1.5)（仮） | 07章 |
| `levelCapInitial` / `levelCapPerRebirth` / `levelCapMax` | 30 / 10 / 100（仮） | 07章 |
| `rebirthExpBonusPerCount` | 0.5（仮） | 07章 |
| `rebirthGiftAddAt` / `giftMax` | {2, 4, 6} / 4 | D-024 |
| `rebirthBonusRange` | 腕力・魔力・俊敏・技巧 0〜20、HP 0〜50（仮） | Q-009 |
| `rebirthFreeRerolls` | 3（初回を含まない、仮） | Q-009 |
| `hireCost` | 300G（仮） | Q-006 |
| `hireStatRange` | 4項目 5〜20、HP 30〜60。ギルドLvごとに上限+1（HP+3）（仮） | Q-006 |
| `hireFreeRerolls` | 3（初回を含まない、仮） | Q-006 |
| `specialVisitorChance` | 0.005（仮） | 02章 |
| `appearanceGenderWeights` | m 0.5 / f 0.5 | D-050 |
| `appearanceLooksWeights` | 美形0.15 / 普通0.50 / ブサイク0.20 / 亜人0.15 | D-050 |
| `gradeWeights` | +0:0.74 / +1:0.20 / +2:0.05 / +3:0.01（仮） | 06章 |
| `modifierChance` | 0.40（仮） | 06章 |
| `potionChanceRarePlus` | 0.05、内訳 転職0.40 / 見た目変更0.30 / 見た目維持0.30（仮） | Q-011 |
| `itemEventWeights` | チケット0.60 / 売却用0.40（仮） | Q-011 |
| `sellRarityMult` | 1 / 1.5 / 2.5 / 4 / 7（仮） | 06章 |
| `sellGradeCoef` | 0.5（仮） | 06章 |
| `equipRarityMult` | 1.0 / 1.3 / 1.7 / 2.2 / 3.0（仮） | Q-020 |
| `equipGradeCoef` | 0.10（仮） | Q-020 |
| `guildExpPerFloor` / `guildExpClearBonus` / `guildExpFirstClear` | 1 / 5 / 50（仮） | Q-017 |
| `guildLevelMax` | 20（仮） | Q-017 |
| `chestStorageMax` | 200（仮） | Q-020 |

## 4. ダンジョンの初期値（仮、M1で調整）

| ID | 名前 | フロア | 距離 | 基準 HP/攻/物防/魔防 | 攻撃種別（物理:魔法） | 種族 | 罠Lv | 最低宝箱 | 戦闘1回の経験値/G |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| dng_graveyard | 古い墓地 | 7 | 3 | 60/14/4/4 | 70:30 | アンデッド80% | 1 | 1（コモン） | 10/15 |
| dng_ruins | 罠の遺跡 | 9 | 5 | 90/18/6/5 | 80:20 | 獣・魔物 | 3 | 1 | 14/20 |
| dng_tower | 封印の塔 | 11 | 7 | 120/22/6/14 | 30:70 | 魔物・精霊 | 2 | 2（アンコモン） | 18/26 |
| dng_castle | 騎士の古城 | 13 | 9 | 170/26/16/8 | 90:10 | 騎士・魔物 | 2 | 2 | 24/34 |

- 戦闘の経験値・ゴールドもモンスター強さ倍率で増やす（06章）。
- 解放：古い墓地は最初から。以降は前のダンジョンの初回踏破で解放（Q-017）。
- 転職ポーションの対象職業：古い墓地＝僧侶・司祭、罠の遺跡＝盗賊・忍者、封印の塔＝魔法使い・賢者、騎士の古城＝戦士・ナイト。

## 5. 職業（Jobs.luau）

ゲーム仕様書03章の成長表どおり。各行：`id, name, line（warrior/scout/mage/support）, attackType（physical/magic）, isRare, growth{str,mag,agi,dex,hp}, equipKinds{...}, heals（boolean）, outfitClass（phy/mag）`。

## 6. 初期状態（StarterSet.luau、Q-020 仮）

- 所持金 500G、パーティ枠1、候補枠3、所属枠8、倉庫100。
- 冒険者4人（戦士・盗賊・魔法使い・僧侶 各1、Lv1、基礎ステータスは固定値）を初期パーティの隊列1〜4に配置。各自コモンの武器・防具を装備。
- 「最初の宝箱を1分以内」（01章）を満たすよう、古い墓地の初回は確実に宝箱1個以上（踏破確定宝箱）を得られる強さにする。
