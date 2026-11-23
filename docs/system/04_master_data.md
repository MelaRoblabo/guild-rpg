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
| `DailyTraits.luau` | 日替わりの特性（D-156） | `dt_` |
| `Quests.luau` | クエストのお題（D-153） | `qst_` |
| `LoginBonus.luau` | ログインボーナスのカレンダー（D-155） | — |
| `PlaytimeRewards.luau` | プレイ時間の段階（D-154） | — |
| `SpecialChests.luau` | 特別な宝箱の表（D-166） | `spc_` |
| `MapEvents.luau` | マップイベント（種類・場所。D-152） | `mev_` |

## 2. 検証（MasterData.luau）

起動時（CLI・シミュレーター・サーバー）に必ず検証し、1つでも違反があれば**起動しない**。

- `id` の重複がない。参照先の `id` が存在する。
- 確率の表は合計が 1（許容誤差 1e-9）。重み表は全部 0 以上で合計 > 0。
- 演出率（D-090）の 10〜15% の検査は普通のダンジョンの `chestRarityWeights` だけ。特別な宝箱は `SpecialChests` の行ごとの基準で検査する（D-166）。レアダンジョンの山は、相当するダンジョンの表をレアダンジョン用の基準（20〜30%）で検査する（D-171）。12ダンジョンすべてが `chestEffectMinRarity`（10〜15%）と `rareChestEffectMinRarity`（20〜30%）の両方を持ち、両方の範囲に収まることを検査する（D-188）。
- 専用ギフト（`exclusive = true`）は、持ち主のユニークが1人だけ参照している（D-165）。ログインボーナス用のユニーク（`acquire = "login"`）は今週の訪問者の候補に入らない（D-155, D-158）。
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
| `expBase` / `expExponent` / `expCycleMult` | 100 / 1.5 / 周回ごとの倍率（`tools/sim/progression` が自動調整。M7b-6 で自動プレイの暦日数（D-161, D-199）に合わせて全周回 ×1.10） | D-071, D-161 |
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
| `itemEventWeights` | チケット0.02 / 売却用0.98 | Q-011, D-074, D-097 |
| `sellRarityMult` | 1 / 1.5 / 2.5 / 4 / 7 / 12（仮。レアリティの数だけ） | 06章, D-085 |
| `sellGradeCoef` | 0.5（仮） | 06章 |
| `equipRarityMult` | 1.0 / 1.3 / 1.7 / 2.2 / 3.0 / 4.0（仮。レアリティの数だけ） | Q-020, D-085 |
| `equipGradeCoef` / `equipTierMult` | 0.10 / 1.30（仮） | Q-020, D-069 |
| `guildExpPerFloor` / `guildExpClearBonus` / `guildExpFirstClear` | 1 / 5 / 50（仮） | Q-017 |
| `guildLevelMax` | 20（仮） | Q-017 |
| （宝箱の保管上限） | なし（旧 `chestStorageMax` 500 は廃止） | D-084 |
| `chestBatchOpen` | 100（まとめて開く個数） | D-089 |
| `chestEffectRate` | 0.10〜0.15（開封演出が入る割合の基準。普通のダンジョンだけ） | D-090, D-166 |
| `offlineTimeMult` | 10（留守番の探索1回の時間の倍率） | D-161 |
| `offlineMaxSeconds` | 21600（1回の留守で6時間まで。拡張しない） | D-161 |
| `restBonusRate` / `restBonusMaxSeconds` | 0.5（留守の半分）/ 14400（4時間）（D-161。M7b-6 の自動プレイで変えていない） | D-161 |
| `restBonusExpMult` | 2（D-161。M7b-6 の自動プレイで変えていない） | D-161 |
| `dailyTraitBands` | `{ min = 1, max = 4 }`, `{ min = 5, max = 8 }`, `{ min = 9, max = 12 }`（難度＝ダンジョンの tier の帯） | D-156 |
| `calendarSeed` | 20260101（日替わり・今週の訪問者・マップイベント・クエストのお題の共通の乱数の元。値は任意の固定値） | D-156, D-158, D-152, D-153 |
| `questDailyCount` / `questWeeklyCount` | 3 / 4（ウィークリーは 3〜5 のうち仮。M7b-6） | D-153 |
| `questDailyBonus` / `questWeeklyBonus` | 全部達成のボーナス（報酬の形は §9）。デイリー：ゴールド係数60・クエストの宝箱150・チケット12、ウィークリー：ゴールド係数220・クエストの宝箱700・チケット46・見た目変更／維持ポーション各1（M7b-6 で配分 D-160・D-200 に合わせた。ポーションは量を優先：D-201） | D-153 |
| `playtimeDailyCapSeconds` | 7200（1日2時間まで） | D-154 |
| `friendRewardIntervalSeconds` | 600（仮。M7b-6） | D-157 |
| `friendRewardMaxFriends` | 3（報酬が増えるのは3人分まで） | D-157 |
| `friendRewardGoldMult` / `friendRewardBonusPerFriend` | 7 / 0.25（7 は M7b-6 で配分 D-160 のフレンド約5%に合わせた。0.25 は仮）。ゴールド = floor(基準のダンジョンの rewardGoldBase × friendRewardGoldMult × (1 + friendRewardBonusPerFriend × (min(友達の数, friendRewardMaxFriends) − 1)))（06章 §20・§22） | D-157, D-190 |
| `friendRewardDailyCap` | 12（1日に押せる回数。仮。M7b-6） | D-157 |
| `referralWeeklyCap` | 3（招待した側が報酬を受け取れる人数／週。仮。M7b-6） | D-157 |
| `referralRewards` | `invitee`（招待された側）・`inviter`（招待した側）の報酬（形は §9 の rewards）。中身はステータススロットチケット、量はどちらも2（仮。M7b-6） | D-157, D-180, D-192 |
| `referralProgressCondition` | 招待された人の進み具合の条件。両者の報酬はこれに届いたときに渡す。`{ kind = "rebirthsTotal", count = 1 }`（これまでに転生した回数の累計 `stats.rebirths` が count 回以上＝初転生。解雇で戻らない。仮。M7b-6）。判定は core の `Friend.referralProgressReached`（サーバーがこれを見て届け物を書き、招待された側に GrantReferral（invitee）を実行する）。検証：kind は `rebirthsTotal` だけ、count は1以上の整数 | D-157, D-192, D-195 |
| `notifyLoginHistoryCount` | 「いつも遊ぶ時刻」（ゲーム外の通知を送る時刻）に使う直近のログインの回数。7。中央値をとる（06章 §23）。検証：1以上の整数 | D-196 |
| `weeklyVisitorChance` | 0.03（今週の訪問者の別枠の確率。候補1人ごと。仮。M7b-6） | D-158, D-170 |
| `mapEventIntervalSeconds` / `mapEventNoticeSeconds` / `mapEventWindowSeconds` | 300 / 60 / 180 | D-152 |
| `mapEventKindWeights` | `{ { id = "mev_rare_dungeon", weight }, … }`。レアダンジョン 3・レイド 1・商人 6（M7b-6：配分 D-160 のマップイベントとオンラインの価値 D-161 に合わせた） | D-152 |
| `rareDungeonChestMult` | 1.5〜2 の範囲で未決（M7b-6）。M7b-4 は 1.5 の仮 | D-152 |
| `rareDungeonEffectRate` | `{ min = 0.20, max = 0.30 }`（レアダンジョンの山の演出率の基準） | D-171 |
| `raidHpMult` / `raidHpSpread` / `raidDamagePerAtk` | 式は 06章 §12 の仮の式のまま。値は M7b-6 で 3 / `{ min = 0.6, max = 1.4 }` / 1（1パーティでときどき・2パーティでたいてい・3パーティでほぼ倒せる。docs/reports/M7b6_balance.md） | D-152, D-179 |
| `raidTravelSeconds` | レイドへの片道秒（30。M7b-6 で 60 から短くした：オンラインの価値 D-161）。`mapEventWindowSeconds + raidTravelSeconds ≤ mapEventIntervalSeconds` を検証（最後のダメージが次の時間帯より前に入る） | D-152 |
| `merchantItemCount` | `{ min = 3, max = 5 }`。品のレアリティは、そのダンジョンの宝箱の表からコモンを除いて引く（コモンしかない表ならコモン） | D-152, D-189 |
| `merchantDungeonCount` | 2（品を引くダンジョン＝踏破済みのうち深い方からこの数。一番深いダンジョンとその1つ浅いダンジョン。06章 §12）。検証：1以上の整数 | D-202 |
| `merchantPriceMult` / `merchantGradeCoef` / `merchantModifierCoef` | 10 / 0.5 / 0.5（10 は M7b-6 で見直して据え置き：D-198。係数 0.5 は仮のまま） | D-152, D-198 |
| `rewardShareTargets` | §13 の表（まだ置いていない。自動プレイの `Ledger.TARGETS` に写して比べる） | D-160, D-200 |

## 4. ダンジョン（D-068, D-069）

- 12ダンジョン。`src/data/Dungeons.luau` は **`tools/sim/calibrate.luau` が `tools/sim/DungeonTemplates.luau` から生成する**（手で編集しない）。
- 調整の考え方：各ダンジョンに「想定段階」（`tools/sim/Stages.luau`。転生回数・レベル・装備）を割り当て、その段階のバランス編成で
  踏破率約60%（古い墓地は約97%）、所要秒が目標（50秒 → 150秒）になるよう、強さ・距離・罠レベル・経験値を自動で決める。
- 数値を変えたいときは、テンプレートの目標値か段階の想定を変えて `lune run tools/sim/calibrate` を再実行する。
- 宝箱のレアリティの出現率 `chestRarityWeights`（D-085）もテンプレートに書き、calibrate がそのまま写す（%、[1]=コモン…）。2本の演出ライン `chestEffectMinRarity`・`rareChestEffectMinRarity` も同じ（D-188）。
- 報酬のゴールドの基準額 `rewardGoldBase`（整数。全ダンジョン必須）もテンプレートに書き、calibrate がそのまま写す（D-198。以前は `Constants.rewardGoldBase` の辞書。Constants に残すと検証で止める）。報酬のゴールド = floor(踏破した一番深いダンジョンの rewardGoldBase × 報酬ごとの係数)（06章 §22、D-190, D-187）。仮（M7b-6）：各ダンジョンの `battleReward.gold` に比例させ古い墓地 100 〜 天空の玉座 5960。

| ダンジョン | コモン | アンコモン | レア | エピック | レジェンド | ミシック | 演出ライン | 演出率 | レアダンジョンの演出ライン | 演出率 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 古い墓地 | 78 | 12 | 10 | | | | レア | 10% | アンコモン | 22% |
| 罠の遺跡 | 75 | 13 | 12 | | | | レア | 12% | アンコモン | 25% |
| 封印の塔 | 72 | 16 | 10 | 2 | | | レア | 12% | アンコモン | 28% |
| 騎士の古城 | 62 | 16 | 12 | 10 | | | エピック | 10% | レア | 22% |
| 水没神殿 | 50 | 28 | 12 | 9 | 1 | | エピック | 10% | レア | 22% |
| 霧の大森林 | 40 | 32 | 15 | 11 | 2 | | エピック | 13% | レア | 28% |
| 地下大迷宮 | 35 | 36 | 15 | 11 | 3 | | エピック | 14% | レア | 29% |
| 呪われた修道院 | 20 | 33 | 25 | 12 | 9 | 1 | レジェンド | 10% | エピック | 22% |
| 鋼鉄の要塞 | 12 | 30 | 30 | 15 | 11 | 2 | レジェンド | 13% | エピック | 28% |
| 竜の巣 | 9 | 32 | 31 | 14 | 11 | 3 | レジェンド | 14% | エピック | 28% |
| 魔界の門 | 6 | 31 | 34 | 14 | 10 | 5 | レジェンド | 15% | エピック | 29% |
| 天空の玉座 | 1 | 12 | 30 | 32 | 15 | 10 | ミシック | 10% | レジェンド | 25% |

- 表は D-188 で作り直した（M7b-6）。古い墓地・罠の遺跡・騎士の古城・地下大迷宮・竜の巣・魔界の門の6つを変え、古い墓地・罠の遺跡・騎士の古城は普通の演出ラインも1段上げた。古い墓地はコモン・アンコモンの2つだけでは2本の線が引けないため、レアを足した。

- 開封演出（D-089, D-090）：`chestEffectMinRarity` 以上のレアリティで演出が入る。**演出率（そのダンジョンで演出が入る割合）は `chestEffectRate`（10〜15%）に収める**。外れるとマスターデータの検証でエラーになる。
- 上位のレアリティの出やすさ（そのレアリティ以上が出る割合）は、深いダンジョンほど増える（または同じ）。

- **レアリティを増やすとき（D-085）**：`Rarities.luau` の末尾に行を足し、`equipRarityMult`・`sellRarityMult` を同じ長さに伸ばし、出したいダンジョンの `chestRarityWeights` に値を足し、必要なら `chestEffectMinRarity` を見直す。検証が長さの食い違いをエラーにする。
- 派遣費 `dispatchFee` は廃止（D-163。D-079 を廃止）。テンプレート・calibrate・Dungeons から消す。
- レアダンジョンの山（`special:rare:<dungeonId>`）は、そのダンジョンの `chestRarityWeights` をそのまま使う。演出ラインだけ別に `rareChestEffectMinRarity` をテンプレートに書き、calibrate が写す。この演出ライン以上が出る割合が `rareDungeonEffectRate`（20〜30%）に収まるかを検証する（D-171, D-185）。
- 経験値は「深いダンジョンほど1秒あたりの経験値が前の1.08倍以上」になるよう calibrate が引き上げる（D-097）。
- 結果の確認は `lune run tools/sim -- sweep`。報告は `docs/reports/M1b_balance.md`。

## 5. 職業（Jobs.luau）

ゲーム仕様書03章の成長表どおり。各行：`id, name, line（warrior/scout/mage/support）, attackType（physical/magic）, isRare, growth{str,mag,agi,dex,hp}, equipKinds{...}, heals（boolean）, outfitClass（phy/mag）`。

## 6. 初期状態（StarterSet.luau、Q-020 仮）

- 所持金 500G、パーティ枠1、候補枠3、所属枠8、倉庫300（D-071）。
- 冒険者4人（戦士・盗賊・魔法使い・僧侶 各1、Lv1、基礎ステータスは固定値）を初期パーティの隊列1〜4に配置。各自コモンの武器・防具を装備。
- 自動売却は最初からオン（コモン・アンコモン、修飾語つきは残す。D-167）。初期値は `autoSell = { enabled = true, maxRarity = 2, keepModified = true }` として StarterSet に置く（検証あり。セーブの移行 v5→v6 もこの値を使う）。売却用アイテム（素材）は設定にかかわらず常に自動で売る（D-167）。
- 「最初の宝箱を1分以内」（01章）を満たすよう、古い墓地の初回は確実に宝箱1個以上（踏破確定宝箱）を得られる強さにする。

## 7. 日替わりの特性（DailyTraits.luau、D-156）

各行：`id, effect, value`。良い効果だけを置く（「レアリティが上がる」は置かない。レアダンジョン D-152 だけの特徴）。

| effect | 内容（例） | value |
| --- | --- | --- |
| `chestMult` | 宝箱の数 ×1.5 | 1.5（仮。M7b-6） |
| `expMult` | 経験値 ×2 | 2（仮。M7b-6） |
| `atkPctPhysical` | 物理攻撃職の攻撃力 +20% | 0.20（仮。M7b-6） |
| `atkPctMagic` | 魔法攻撃職の攻撃力 +20% | 0.20（仮。M7b-6） |
| `travelMult` | 移動時間 −30% | 0.70（仮。M7b-6） |

- M7b-3 では上の5行（id `dt_chest`・`dt_exp`・`dt_atk_physical`・`dt_atk_magic`・`dt_travel`）を D-156 の例の値で置く。抽選は5行から等確率。検証：`chestMult`・`expMult` は 1 以上、`travelMult` は 0〜1、どの帯にもダンジョンがあること。

- 候補の行と効果量は未決（M7b-6）。どの日にどのダンジョン・特性が当たるかは 06章 §16。
- 日ごとの特性なので「ダンジョン補正はない」（D-038・D-047）の例外。効果は個体補正・経験値補正の上限の外で掛ける（D-173）。

## 8. ユニーク・ギフトの追加項目（Uniques.luau・Gifts.luau）

| ファイル | 項目 | 内容 | 根拠 |
| --- | --- | --- | --- |
| Uniques | `acquire` | `visitor`（雇用の特別な訪問者）・`firstClear:<dungeonId>`（初回踏破）・`login`（ログインボーナス7日目）の3つだけ。ギルドレベル報酬の経路は廃止。`login` のユニークは雇用に出さない | D-055, D-155, D-169 |
| Uniques | `loginOrder` | `login` のユニークを配る順（1周ごとに別のユニーク）。人数は未決（Q-025） | D-155 |
| Uniques | `exclusiveGiftId` | そのユニークの専用ギフト（`exclusive = true` のギフト）。中身は未決なので、本番データにはまだ置かない。`giftIds` と合わせて giftMax まで。加入したとき `giftIds` の最後に足す | D-165 |
| Gifts | `exclusive` | 専用ギフトの印。true なら一般の抽選（雇用の初期ギフト・転生で増えるギフト）に出さない（`master.giftList` から除く）。最大4つの枠（D-024）には数える。`weight` は要らない。一般の冒険者・ユニークの `giftIds` には書かない | D-165 |
| Gifts | `partyEffect` | 専用ギフトに限り、パーティ全体に効く効果を持てる。種類は決定の例の範囲の `{ kind = "travelMult", value }`（片道秒に掛ける。0 < value ≤ 1）と `{ kind = "chestMult", value }`（宝箱の数に掛ける。value ≥ 1）だけ。同じ効果はパーティ内で重ねない（一番効果の大きい1つ。道案内と同じ）。partyEffect を持つ専用ギフトは `effect` を省ける。ゲーム仕様書04章の「補正の発生源は個体のみ」の例外 | D-174 |

- ユニークの強さの基準は「雇用の新人の平均より上、当たりよりは下」（D-165）。`baseStats` はこの基準で決め直す（数値は未決、シミュレーションで確認）。
- 専用ギフトの効果の種類は、中身が決まってから必要な分だけ足す（D-165）。
- ユニークの入手経路は上の3つ（初回踏破・ログインボーナス・雇用の特別な訪問者）。今週の訪問者は雇用の特別な訪問者の中で出やすくするもの（D-169, D-170）。
- 検証：専用ギフトを2人のユニークが参照したらエラー、持ち主のいない専用ギフトは警告。一般の抽選に出るギフトが1つもなければエラー。

## 9. クエストのお題（Quests.luau、D-153）

各行：`id, period（daily / weekly）, kind, amountPerParty, rewards`。

**報酬の形（rewards）**：クエスト・ログインボーナス・プレイ時間・全部達成のボーナスで共通。受け取り箱に入る（D-164）。

```lua
rewards = {
	goldMult = 5,                                  -- 省略可。ゴールドの係数（固定額の gold は置かない：検証）。額 = floor(基準のダンジョンの rewardGoldBase × goldMult)（06章 §22、D-190, D-198）
	items = { itm_slot_ticket = 1 },               -- 省略可。売却用アイテムは置かない（検証）
	chests = { { pileKey = "special:quest", count = 1, rank = nil } },  -- 省略可。表を持つ特別な宝箱の山だけ（検証）
}                                                  -- rank を省くと届いたときに SpecialChests の表で引く。書けばそのランク
```

M7b-4 で置いた候補（すべて仮。M7b-6）：デイリーは5種類（探索10・開封10・雇用1・トレーニング5・踏破5、×パーティ数）、ウィークリーは6種類（探索50・開封50・雇用3・トレーニング25・踏破25・転生1、×パーティ数）。報酬は M7b-6 で配分（D-160）に合わせ、期間ごとにどのお題も同じにした。デイリー1つ：ゴールド係数30・クエストの宝箱60・チケット6。ウィークリー1つ：ゴールド係数120・クエストの宝箱350・チケット18。ポーションはお題ごとには出さない（量を優先：D-201）。

| kind | 数えるもの | period |
| --- | --- | --- |
| `expeditions` | 探索の回数（オンライン中に出発したもの） | daily / weekly |
| `chestsOpened` | 宝箱を開けた数 | daily / weekly |
| `hires` | 雇用 | daily / weekly |
| `trainings` | トレーニングを行った回数（D-191） | daily / weekly |
| `clears` | 踏破（レアダンジョンの踏破も数える。レイドは数えない：D-191） | daily / weekly |
| `rebirths` | 転生 | weekly のみ |

- 量は「`amountPerParty` × パーティ数」（例：探索 ×パーティ数×10回）。お題の候補・量の式は仮のまま（M7b-6 では変えていない）。報酬の量は M7b-6 で決めた（上）。
- 報酬はゴールド・宝箱・ポーション・ステータススロットチケット。全部達成のボーナス（宝箱など）は `questDailyBonus` / `questWeeklyBonus` に置く（量は §3。M7b-6）。

## 10. ログインボーナス・プレイ時間（LoginBonus.luau・PlaytimeRewards.luau）

- `LoginBonus`：`{ days = { 1〜6日目の rewards（6行） }, fallback = rewards }`。1〜6日目の報酬（ゴールド・チケット・ポーション・宝箱）。7日目は `loginOrder` 順のユニーク（`cycle` 周目は loginOrder の順で `cycle` 番目）。ログイン用のユニークがいない・そのユニークを持っている（受け取り箱に届いている）・ユニークが一巡した後は `fallback`（レアな宝箱＋チケット。M7b-6 で `special:login` のランク3（レア）50個＋チケット20）。量は M7b-6 で配分（D-160）に合わせた（1〜6日目の合計：ゴールド係数510・宝箱1300・チケット50・ポーション2（5日目の見た目変更・見た目維持 各1。量を優先：D-201））。ゴールドは `goldMult`。（D-155, D-190）
- ログイン用のユニークの中身（誰か・人数）は未決（Q-025）。M7b-4 では仕組みだけを作り、Uniques に `acquire = "login"` の行は置かない（いないので7日目は毎周 fallback）。
- `PlaytimeRewards`：段階 5・10・20・30・45・60・90・120分（行ごとに `minutes, rewards`。minutes は昇順、`minutes × 60 ≤ playtimeDailyCapSeconds` を検証）。報酬はゴールド（1時間の収入の数%。`goldMult` で踏破した一番深いダンジョンに応じて増える：D-190）と宝箱（`special:playtime`）。量は M7b-6 で配分（D-160。D-200 で「プレイ時間」の列はプレイ時間報酬だけになった）に寄せた：`goldMult` は 5・10分 8、20〜60分 10、90・120分 12（1段あたりオンライン1時間の直接のゴールドの約5%。D-154 の「数%」の上の方にとどめた）、宝箱は 10分 30・30分 40・60分 60・120分 80、チケットは 30分 1・60分 1・120分 2。（D-154）

## 11. 特別な宝箱（SpecialChests.luau、D-166）

各行：`id, pileKey, rarityWeights, effectMinRarity, effectRateMin, effectRateMax`。

| id | pileKey | 出どころ | 演出率の基準 |
| --- | --- | --- | --- |
| `spc_rare` | `special:rare:<相当するダンジョン>` | レアダンジョン（D-152）。中身の表は相当するダンジョンの `chestRarityWeights` を使う（行に表を持たない） | `rareDungeonEffectRate`（20〜30%）（D-171） |
| `spc_raid` | `special:raid` | レイドのレアな宝箱（D-152） | 未決（M7b-6） |
| `spc_quest` | `special:quest` | クエストの報酬（D-153） | 未決（M7b-6） |
| `spc_login` | `special:login` | ログインボーナス（D-155） | 未決（M7b-6） |
| `spc_playtime` | `special:playtime` | プレイ時間報酬（D-154） | 未決（M7b-6） |

- 出現率（`rarityWeights`）と演出率は未決（M7b-6）。検証は行ごとに `effectRateMin`〜`effectRateMax` に収まるかを見る（D-090 の検査は普通のダンジョンだけ）。
- M7b-4 で置いた仮の値（M7b-6 で決める）：

| id | rarityWeights（%） | effectMinRarity | 演出率 | 基準 |
| --- | --- | --- | --- | --- |
| `spc_raid` | 0 / 0 / 70 / 22 / 7 / 1 | エピック | 30% | 20〜40% |
| `spc_quest` | 50 / 30 / 15 / 5 | レア | 20% | 15〜25% |
| `spc_login` | 50 / 30 / 15 / 5 | レア | 20% | 15〜25% |
| `spc_playtime` | 70 / 20 / 8 / 2 | レア | 10% | 8〜15% |

- `spc_rare` の行は `pileKey = "special:rare"` だけを持ち、表・演出の値を持たない（相当するダンジョンの `chestRarityWeights` と `rareChestEffectMinRarity`、基準は `rareDungeonEffectRate`）。`rareChestEffectMinRarity` は全ダンジョン必須（D-188 で表を作り直し、12ダンジョンすべてで 20〜30% の線が引けるようにした。無いと検証で止める）。core は念のため、持たないダンジョンのレアダンジョンの山を開けない（PILE_NOT_FOUND）。
- クエスト・ログインボーナス・プレイ時間の宝箱は特別な宝箱（D-171）。D-154 の「進み具合に合った」は中身のアイテムレベルのこと。
- 中身のアイテムレベルは「開けたときに踏破している一番深いダンジョン」（06章 §19、D-171）。まだどこも踏破していなければ古い墓地（D-187）。レアダンジョンの山は相当するダンジョンのアイテムレベル（D-187）。

## 12. マップイベント・旅の商人（MapEvents.luau・Merchant.luau、D-152）

- `MapEvents`：`kinds`（`{ id, kind }`。`mev_rare_dungeon`＝rareDungeon・`mev_raid`＝raid・`mev_merchant`＝merchant）と、出る場所の一覧 `places`（`{ id }`。中身は M8 のマップ設計で決める。M7b-4 は `mev_place_1〜4` の仮）。種類の割合は `mapEventKindWeights`（未決（M7b-6））。検証：割合の id は kinds を指す、kind の重複なし、場所は1行以上。
- 旅の商人の決まりは別のファイルを作らず `Constants` に置く：品の数（`merchantItemCount`）、価格（売却額 × `merchantPriceMult`、グレード・修飾語で上がる。06章 §12）。品は装備だけ（チケットなど量を管理している品は売らない）。アイテムレベル・レアリティは踏破済みの範囲まで（品ごとに、踏破した一番深いダンジョンとその1つ浅いダンジョン（`merchantDungeonCount`。踏破が1つならそのダンジョン、未踏破なら古い墓地：D-187, D-202）から1つ選び、そのダンジョンの `chestRarityWeights` からコモンを除いた表（コモンしかなければコモン：D-189）と宝箱の中身の抽選で作る。06章 §12）。

## 13. 報酬の入手先の配分（rewardShareTargets、D-160）

冒険の報酬は減らさず、冒険以外を足して入手先の割合を変える（全体の量は増えてよい：D-200）。各入手先の量（§7〜§12）はこの配分に合うよう自動プレイで調整する（M7b-6。コアの型で合わせる：D-200）。表の値は目標の割合（%）。

| 報酬 | 冒険（留守番を含む） | クエスト | ログイン | プレイ時間 | フレンド | マップイベント | ギルドレベル |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ゴールド | 65 | 10 | 5 | 10 | 5 | 5 | — |
| 宝箱 | 70 | 10 | 5 | 5 | — | 10 | — |
| ステータススロットチケット | 10 | 45 | 15 | 5 | — | — | 25 |
| ポーション | 50 | 20 | 20 | — | — | 10 | あり（比率は目安：D-201） |

- 留守番の探索の報酬（D-161）は「冒険」の列に数え、「プレイ時間」の列はプレイ時間報酬だけ（D-200）。フレンドボタンの報酬はゴールドだけなので、チケットのフレンドの5%はクエストに寄せた（D-200）。
- ポーションは量を優先し、全体の数を M7b-6 の合わせ込みの前の水準に保つ。割合は目安（D-201）。
- 表は自動プレイ（`tools/autoplay/Ledger.luau` の `TARGETS`）に写して比べる。マスターデータの `rewardShareTargets` はまだ置いていない（ゲームの処理では使わないため）。
- M7b-6 の結果（コアの型で合わせた。ライト・ヘビーとの差）は docs/reports/M7b6_balance.md。チケットのギルドレベルの分は `tools/sim/progression` の `--rescale-guild-tickets` で数だけを0.4倍にした。
- ポーションのギルドレベルの分は、ギルドレベルが10の倍数のときの見た目変更・見た目維持ポーション（D-074 のまま残す）。各入手先の比率は M7b-6 の自動プレイで決める（D-178）。
- ユニークキャラの入手は初回踏破・ログインボーナス7日目（D-155）・雇用の特別な訪問者（今週の訪問者は出やすい）の3経路（D-169）。
