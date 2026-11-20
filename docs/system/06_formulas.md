# 06 計算式

すべて `src/core/Formulas.luau` に実装し、他のモジュールはここから使う。定数名は 04章の `Constants`。

## 1. 冒険者の実効値

```
実効ステータス s' = floor( (baseStats.s + 装備のステータス補正.s) × (1 + 個体補正率.s) )
個体補正率 = ギフト補正 + 修飾語補正 の合計。1性能あたり personalBonusCap（+30%）まで      -- D-033
最大HP = 実効 hp
```

## 2. 装備の性能（Q-020 仮、D-069）

```
性能値 = 基本値 × equipRarityMult[rarity] × (1 + equipGradeCoef × grade) × equipTierMult^(アイテムレベル − 1)   -- 端数切り捨て
アイテムレベル = 入手したダンジョンの tier（1〜12）
```
対象は攻撃力補正・物理防御・魔法防御・ステータス補正。

## 3. 戦闘（D-002〜D-010, D-037, D-047）

```
攻撃力 = (攻撃区分が physical なら 実効str、magic なら 実効mag) + 武器の攻撃力補正     -- D-037, D-047
         ※ 退魔の才・退魔の修飾語は、相手がアンデッドのとき攻撃力に +率 を乗算（個体補正の上限内）
与ダメージ = max( floor(攻撃力² ÷ (攻撃力 + 相手の対応防御)), 1 )                       -- D-068（D-007 を置き換え）
         対応防御：physical → 物理防御、magic → 魔法防御
クリティカル率 = min( 実効dex / (実効dex + critCoef), critCap )                       -- D-010
クリティカル時 与ダメージ = floor(与ダメージ × critMult)
被ダメージ = max( floor(モンスター攻撃力² ÷ (モンスター攻撃力 + 対象の対応防御)), 1 )    -- D-068
         対応防御：モンスターの攻撃種別が physical → 物理防御、magic → 魔法防御        -- D-008
モンスター強さ倍率(n番目の戦闘) = 1 + monsterScalePerBattle × (n − 1)                 -- D-003
モンスターの各パラメータ = floor(ダンジョン基準値 × 倍率)
戦闘報酬（経験値・G） = floor(ダンジョンの戦闘報酬 × 倍率)
行動順 = 実効agi の降順。同値は隊列番号の小さい順                                      -- D-004
被弾対象 = 生存者の hitWeights を正規化して抽選                                       -- D-005
```

## 4. 支援系の回復（D-022, D-034, D-060）

```
回復するか = 生存者のうち (現在HP / 最大HP) < healThreshold の者がいる
対象 = HP割合が最小の生存者（同値は隊列番号の小さい順）
回復量 = floor( 実効mag × healCoef × (1 + 癒しの補正率) )。最大HPを超えない
```

## 5. イベント（D-014〜D-018）

```
罠の回避率 = 技巧合計 / (技巧合計 + 罠Lv × trapK)                                     -- D-017
  技巧合計 = 生存者の 実効dex の合計。罠師の勘の所持者は本人分を2倍で数える
罠ダメージ(各生存者) = floor( 最大HP × (ダンジョンの trapDamageRate または Constants.trapDamageRate) )   -- D-067
泉の回復(各生存者) = floor( 最大HP × fountainHealRate )                               -- D-018
宝箱ランク = min( ダンジョンの最低ランク + chestRankOffsets から抽選, 5 )              -- D-015
```

## 6. 幸運（D-019, Q-004 仮）

```
発動率 = min( 生存している幸運所持者の数 × luckyChancePerHolder, luckyChanceCap )
宝箱を1個確保するたびに1回判定。成功で同じ抽選の宝箱をもう1個（追加分では再判定しない）
```

## 7. 移動と所要時間（D-021, D-026, D-069）

```
片道秒 = ceil( 距離 × travelSecondsPerDistance × clamp(ダンジョンの refAgi ÷ 平均実効agi, travelSpeedMin, travelSpeedMax) × 道案内 )
  道案内：対象地形なら × 0.7（パーティ内で重複しない。D-070）
再生秒 = 戦闘ターン数合計 × replaySecondsPerTurn + イベント数 × replaySecondsPerEvent
所要秒 = 片道秒 × 2 + 再生秒                       -- 撤退時も同じ式（再生は撤退したフロアまで）
```

## 8. 経験値とレベル（D-041, D-043〜D-045）

```
勝利時の経験値 = 戦闘報酬の経験値を勝利時点の生存者で等分（端数切り捨て）            -- D-041
  個人倍率 = (1 + rebirthExpBonusPerCount × 転生回数) × (1 + 大食らい 0.10)
必要経験値(Lv→Lv+1) = floor(100 × Lv^1.5)
レベルアップ時の成長(各項目) = max(0, 職業の基準値 + rng:int(−growthVariance, +growthVariance))   -- D-043
  成長は baseStats に加算。転職後は新しい職業の基準値を使う                            -- D-045
レベル上限に達したら経験値は貯めない
```

## 9. 転生（企画書§9, Q-009 仮）

```
引き継ぎ = floor(転生前 baseStats.s / 2)        -- 装備・ギフト補正を含まない素の値
加算分   = rng:int(rebirthBonusRange.s.min, rebirthBonusRange.s.max)
転生後   = 引き継ぎ + 加算分。Lv1、levelCap = min(levelCap + levelCapPerRebirth, levelCapMax)
ギフト追加：転生後の rebirthCount が rebirthGiftAddAt に含まれれば、未所持のギフトから1つ抽選
```

## 10. ギルド・売却（08章、06章、Q-017 仮）

```
ギルド経験値(帰還ごと) = 攻略フロア数 × guildExpPerFloor + (踏破なら guildExpClearBonus) + (初回踏破なら guildExpFirstClear)
売却価格 = floor( 基本売却価格 × sellRarityMult[rarity] × (1 + sellGradeCoef × grade) × equipTierMult^(アイテムレベル − 1) )   -- D-069
```
