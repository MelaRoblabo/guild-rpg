# 06 計算式

すべて `src/core/Formulas.luau` に実装し、他のモジュールはここから使う。定数名は 04章の `Constants`。

## 1. 冒険者の実効値

```
実効ステータス s' = floor( (baseStats.s + 装備のステータス補正.s) × (1 + 個体補正率.s) )
個体補正率 = ギフト補正 + 修飾語補正 の合計。1性能あたり personalBonusCap（+50%）まで      -- D-033, D-070
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
         ※ 日替わりの特性 atkPctPhysical / atkPctMagic は、攻撃区分が合う者の攻撃力に +value（§16、D-156）
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
  技巧合計 = 生存者の 実効dex の合計。罠師の勘の所持者は本人分を3倍で数える（D-070）
罠ダメージ(各生存者) = floor( 最大HP × (ダンジョンの trapDamageRate または Constants.trapDamageRate) )   -- D-067
泉の回復(各生存者) = floor( 最大HP × fountainHealRate )                               -- D-018
宝箱ランク（＝中の装備のレアリティ）= ダンジョンの chestRarityWeights から重み付き抽選   -- D-015, D-085
日替わりの特性 chestMult：探索で得た宝箱の数に × value（§16、D-156。端数の扱いは要確認）
  （表の長さがレアリティの数より短ければ、上位は出ない。最上位はリリース時ミシック＝6）
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
  日替わりの特性 travelMult：片道秒に × value（§16、D-156）
再生秒 = 戦闘ターン数合計 × replaySecondsPerTurn + イベント数 × replaySecondsPerEvent
所要秒 = 片道秒 × 2 + 再生秒                       -- 撤退時も同じ式（再生は撤退したフロアまで）
留守番の所要秒 = 所要秒 × offlineTimeMult            -- §13、D-161
```

## 8. 経験値とレベル（D-041, D-043〜D-045）

```
勝利時の経験値 = 戦闘報酬の経験値を勝利時点の生存者で等分（端数切り捨て）            -- D-041
  個人倍率 = (1 + rebirthExpBonusPerCount × 転生回数) × (1 + min(経験値補正, expBonusCap))
  経験値補正 = 大食らい 0.25 ＋ 装備の経験値補正の合計                                     -- D-082
  休息ボーナス：帰還時に残りがあれば、さらに × restBonusExpMult（修練の護符と重ねて効く。expBonusCap の外）   -- §14、D-161
  日替わりの特性 expMult：出発時に当たっていれば × value                                   -- §16、D-156
  装備の経験値補正 = expPct × equipRarityMult[rarity] × (1 + equipGradeCoef × grade)       -- アイテムレベルでは伸びない
必要経験値(Lv→Lv+1) = floor(100 × Lv^1.5 × expCycleMult[転生回数+1])   -- D-071
レベルアップ時の成長(各項目) = max(0, 職業の基準値 + rng:int(−growthVariance, +growthVariance))   -- D-043
  成長は baseStats に加算。転職後は新しい職業の基準値を使う                            -- D-045
レベル上限に達したら経験値は貯めない
```

## 8b. トレーニング（D-076, D-077）

```
1回の費用   = floor(trainGoldCoef × Lv ^ trainGoldExponent)          -- Lv は行う時点のレベル
1回の経験値 = trainingFacility[トレーニング場のレベル].expPerSession -- 倍率（転生・ギフト・装備）は掛けない
上げられる上限 = min(本人の levelCap, trainingFacility[...].levelCap)
上限に達したら余った経験値は捨てる。ゴールドが1回の費用に足りなくなったら止める
```

必要経験値は周回の倍率（expCycleMult）で増えるので、転生を重ねた冒険者ほど必要な回数が増える。
新しく雇った冒険者の育成を短縮するのが主な使い道。

## 9. 転生（企画書§9, Q-009 仮）

```
引き継ぎ = floor(転生前 baseStats.s / 2)        -- 装備・ギフト補正を含まない素の値
加算分   = floor( floor(転生前の値 × rebirthBonusMaxRate) × u^p )   u は [0,1) の一様乱数     -- D-072
           p = rebirthBonusSkewBase + rebirthBonusSkewPerRebirth × (転生後の回数 − 1)
転生費用 = rebirthCost[転生前の回数 + 1]（RebirthStart で払う）                         -- D-080
転生後   = 引き継ぎ + 加算分。Lv1、levelCap = min(levelCap + levelCapPerRebirth, levelCapMax)
ギフト追加：転生後の rebirthCount が rebirthGiftAddAt に含まれれば、未所持のギフトから1つ抽選
```

## 10. ギルド・売却（08章、06章、Q-017 仮）

```
ギルド経験値(帰還ごと) = 攻略フロア数 × guildExpPerFloor + (踏破なら guildExpClearBonus) + (初回踏破なら guildExpFirstClear)
（派遣費の式は D-163 で削除。D-079 は廃止）
演出あり = 宝箱のレアリティ ≥ 宝箱の山の chestEffectMinRarity（特別な宝箱は SpecialChests の effectMinRarity）   -- D-089, D-166
  普通のダンジョンの演出率（chestEffectMinRarity 以上が出る割合）は chestEffectRate（10〜15%）の範囲   -- D-090（検査は普通のダンジョンだけ）
  特別な宝箱の演出率は行ごとの effectRateMin〜effectRateMax の範囲                              -- §19、D-166
まとめ開き：指定した宝箱の山から min(count, chestBatchOpen, 残り) 個を、ランクごとの残り数で重み付けして1つずつ引く   -- D-089, D-166
宝箱は倉庫とは別に「宝箱の山×ランクの数」で保管する。上限なし   -- D-084, D-166
売却価格 = floor( 基本売却価格 × sellRarityMult[rarity] × (1 + sellGradeCoef × grade) × equipTierMult^(アイテムレベル − 1) )   -- D-069
```

## 11. 日・週の番号（D-168）

`src/core/Calendar.luau` に1つだけ置き、日・週で区切る処理（クエスト・プレイ時間・ログインボーナス・日替わり・今週の訪問者）はすべてここから使う。`os.time`・`os.date` は使わない（08章）。

```
dayIndex(now)  = floor(now / 86400)                  -- 日の区切り＝UTC 0時（日本の朝9時）
weekIndex(now) = floor((dayIndex(now) + 3) / 7)      -- 週の始まり＝月曜（1970-01-01 は木曜なので +3 で月曜に合わせる）
次の日の区切りの時刻 = (dayIndex(now) + 1) × 86400   -- 画面の残り時間・「明日の日替わり」の表示用
```

## 12. マップイベントの時間帯・旅の商人（D-152）

```
eventSlot(now) = floor(now / mapEventIntervalSeconds)              -- 5分ごとに1つ
出ている間   ：eventSlot × mapEventIntervalSeconds 〜 + mapEventWindowSeconds（出発・購入できる3分間）
予告         ：次の時間帯の始まりの mapEventNoticeSeconds 前から
種類・場所   ：Rng.new(Rng.derive(calendarSeed, eventSlot)) で mapEventKindWeights と場所の一覧から抽選   -- 全員共通
中身         ：Rng.new(Rng.derive(state.seed, eventSlot)) で抽選（ボスのHP・商人の品）              -- プレイヤーごと。rngCounter は進めない
商人の価格   ：floor( 売却価格（§10） × merchantPriceMult × (1 + merchantGradeCoef × grade) × (修飾語つきなら 1 + merchantModifierCoef) )   -- 係数は未決（M7b-6）
レアダンジョン：強さは踏破済みの一番深いダンジョンと同じ。宝箱の数 × rareDungeonChestMult。宝箱は特別な宝箱 special:rare（§19）
レイド       ：その時間帯に出発したパーティのダメージ（出発時に計算）の合計 > raidHp なら討伐   -- HP とダメージの計算の仕方は未決
```

サーバー全体で状態を持たない：時刻と固定の種だけから決まるので、どのサーバーでも同じ結果になる。

## 13. 留守番（D-161）

```
留守の始まり   = state.lastSavedAt（最後に保存した時刻＝ログアウト時刻）
留守番の終わり = lastSavedAt + offlineMaxSeconds（6時間。拡張しない）
留守番の探索   = 自動再派遣のダンジョンへ、今の探索エンジン（07章）で計算し、所要秒 × offlineTimeMult（10倍＝効率10%）
出す条件       = 自動再派遣が有効、かつ 帰還時刻 ≤ 留守番の終わり                  -- 6時間までに最後の探索を帰還させる
報酬           = 探索ログの報酬をそのまま（時間だけが10倍）。上限レベルの経験値の扱いはオンラインと同じ
```

- 留守番の探索には `offline = true` の印を付け、クエストに数えない・休息ボーナスを使わない。
- 日替わりの特性は出発した日（出発時刻の dayIndex）の特性を当てる（§16）。
- ログイン時の計算量の目安：5パーティで約70回分。

## 14. 休息ボーナス（D-161）

```
たまる量 = (ログイン時刻 − lastSavedAt) × restBonusRate                   -- 留守にした時間の半分
restBonusSeconds = min(restBonusSeconds + たまる量, restBonusMaxSeconds)   -- 上限4時間
消費     = オンラインの advance で、経過秒だけ restBonusSeconds を減らす（0 未満にしない）
効き方   = オンライン中に帰還した探索（offline でない）の経験値に、残りが 0 より大きければ × restBonusExpMult
重ね方   = 修練の護符（装備の経験値補正、D-082）とは重ねて効く：(1 + min(経験値補正, expBonusCap)) × restBonusExpMult
```

倍率・たまる速さは未決（M7b-6）。

## 15. クエストの量（D-153）

```
量 = Quests の amountPerParty × 解放済みのパーティ数        -- 引き直しなし
入れ替え = dayIndex / weekIndex が変わった最初のオンラインの advance で、候補から daily は questDailyCount、weekly は questWeeklyCount 個を抽選
```

量の式・候補は未決（M7b-6）。

## 16. 日替わりの特性（D-156）

```
rng = Rng.new(Rng.derive(calendarSeed, dayIndex))                       -- 全員共通
帯ごと（dailyTraitBands の順）に：帯の tier のダンジョンから1つ、DailyTraits から1つを抽選
明日の日替わり = dayIndex + 1 で同じ計算
当て方 = 出発時刻の dayIndex で、そのダンジョンに当たっている特性を Expedition.dailyTraitId に保存し、探索の計算に渡す
```

| effect | 効くところ |
| --- | --- |
| `chestMult` | 探索で得た宝箱の数（§5） |
| `expMult` | 経験値（§8） |
| `atkPctPhysical` / `atkPctMagic` | 攻撃区分が合う者の攻撃力（§3） |
| `travelMult` | 片道秒（§7） |

レアリティを上げる特性は置かない（D-156）。

## 17. 一括売却の「弱い」（D-167）

```
装備 x が「弱い」 ⇔ x の枠（武器・防具・補助）で、x を付けられる冒険者が1人以上いて、
                   その全員について 性能値(x) < その冒険者が今その枠に付けている装備の性能値
性能値 = §2 の性能値
```

- 要確認：今その枠が空いている冒険者がいるときの扱い、性能値が複数ある装備（防具の物理防御・魔法防御、ステータス補正つき）の比べ方。

- 保護中・装備中の装備は対象外。対象は開封結果に出た装備。

## 18. 今週の訪問者（D-158）

```
rng = Rng.new(Rng.derive(calendarSeed, weekIndex))           -- 全員共通。週の区切りは月曜（§11）
今週の訪問者 = acquire = "visitor" のユニークから1人を抽選（login のユニークは入れない：D-155）
特別な訪問者の抽選の重み = visitorWeight × (今週の訪問者なら weeklyVisitorMult、ほかは 1)
  対象は持っていないユニークだけ。候補枠の数だけ判定する（枠が多いほど出やすい）
```

倍率・重み・週に何人回すかは未決（M7b-6）。

## 19. 特別な宝箱（D-166, D-142）

```
ランク           = SpecialChests の rarityWeights から重み付き抽選
演出率の検査     = 行ごとに effectMinRarity 以上が出る割合が effectRateMin〜effectRateMax（D-090 の検査は普通のダンジョンだけ）
演出の選び方の順位 = 「その宝箱の表での順位」（D-142 の「そのダンジョンでの順位」を読み替える）
中身のアイテムレベル = 踏破した一番深いダンジョンの tier
```

## 20. プレイ時間・ログインボーナス・フレンドボタン（D-154, D-155, D-157）

```
プレイ時間  ：playtime.seconds = min(seconds + オンラインの経過秒, playtimeDailyCapSeconds)。PlaytimeRewards の minutes × 60 に届いた段階の報酬を受け取り箱へ
ログイン    ：login.lastDayIndex < dayIndex なら1日進める（途切れても戻らない）。day = 7 の次は day = 1・cycle + 1
フレンド    ：ctx.now ≥ friend.nextAt のとき押せる。報酬は人数 min(friendCount, friendRewardMaxFriends) で少し増える。押したら nextAt = ctx.now + friendRewardIntervalSeconds（押さないとたまらない）
```

量は未決（M7b-6）。
