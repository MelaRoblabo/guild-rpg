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
         ※ 日替わりの特性 atkPctPhysical / atkPctMagic は、攻撃区分が合う者の攻撃力に × (1 + value)。
           個体補正の上限（personalBonusCap）の外で掛ける（§16、D-156, D-173）
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
日替わりの特性 chestMult：探索で得た宝箱の数に × value（§16、D-156）
  端数は確率で切り上げる：宝箱1個あたり (value − 1) の確率で +1（例 1.5倍なら1個あたり50%で+1）   -- D-173
  専用ギフトのパーティ効果で宝箱が増えるときも同じ（§21、D-174）
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
  専用ギフトのパーティ効果（移動）：パーティ内で重ねない（道案内と同じ。§21、D-174）
再生秒 = 戦闘ターン数合計 × replaySecondsPerTurn + イベント数 × replaySecondsPerEvent
所要秒 = 片道秒 × 2 + 再生秒                       -- 撤退時も同じ式（再生は撤退したフロアまで）
留守番の所要秒 = 所要秒 × offlineTimeMult            -- §13、D-161
```

## 8. 経験値とレベル（D-041, D-043〜D-045）

```
勝利時の経験値 = 戦闘報酬の経験値を勝利時点の生存者で等分（端数切り捨て）            -- D-041
  個人倍率 = (1 + rebirthExpBonusPerCount × 転生回数) × (1 + min(経験値補正, expBonusCap))
  経験値補正 = 大食らい 0.25 ＋ 装備の経験値補正の合計                                     -- D-082
  休息ボーナス：帰還時に残りがあれば、さらに × restBonusExpMult（修練の護符と重ねて効く。expBonusCap の外）   -- §14、D-161, D-173
  日替わりの特性 expMult：出発時に当たっていれば × value（休息ボーナスと掛け合わせる。expBonusCap の外）       -- §16、D-156, D-173
  個人倍率（全体）= (1 + rebirthExpBonusPerCount × 転生回数) × (1 + min(経験値補正, expBonusCap)) × 休息ボーナス × 日替わり
  装備の経験値補正 = expPct × equipRarityMult[rarity] × (1 + equipGradeCoef × grade)       -- アイテムレベルでは伸びない
必要経験値(Lv→Lv+1) = floor(100 × Lv^1.5 × expCycleMult[転生回数+1])   -- D-071
レベルアップ時の成長(各項目) = max(0, 職業の基準値 + rng:int(−growthVariance, +growthVariance))   -- D-043
  成長は baseStats に加算。転職後は新しい職業の基準値を使う                            -- D-045
レベル上限に達したら経験値は貯めない
```

## 8b. トレーニング（D-076, D-077）

```
1回の費用   = floor(trainGoldCoef × Lv ^ trainGoldExponent)          -- Lv は行う時点のレベル
1回の経験値 = trainingFacility[トレーニング場のレベル].expPerSession -- 倍率（転生・ギフト・装備・休息ボーナス：D-173）は掛けない
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

## 12. マップイベントの時間帯・旅の商人（D-152, D-187, D-189）

```
eventSlot(now) = floor(now / mapEventIntervalSeconds)              -- 5分ごとに1つ
出ている間   ：eventSlot × mapEventIntervalSeconds 〜 + mapEventWindowSeconds（出発・購入できる3分間）
予告         ：次の時間帯の始まりの mapEventNoticeSeconds 前から
種類・場所   ：Rng.new(Rng.derive(calendarSeed, eventSlot)) で mapEventKindWeights → 場所の一覧（等確率）の順に抽選   -- 全員共通
中身         ：Rng.new(Rng.derive(state.seed, eventSlot)) で抽選（ボスのHP・商人の品）              -- プレイヤーごと。rngCounter は進めない
商人の品     ：品の数 = rng:int(merchantItemCount.min, max)。品ごとに 候補のダンジョン（踏破済み。まだどこも踏破していなければ古い墓地：D-187）から等確率で1つ
              → そのダンジョンの chestRarityWeights からコモン（rank 1）を除いた表でレアリティ（コモンしかない表ならコモン：D-189）
              → 宝箱の中身と同じ装備の抽選（アイテムレベル＝そのダンジョンの tier。宝箱で出る範囲は超えない）
              候補のダンジョンはその時間帯で最初に買ったときに state.merchant.dungeonIds に写す（3分間のうちに踏破が進んでも品ぞろえを変えない）
商人の価格   ：floor( 売却価格（§10） × merchantPriceMult × (1 + merchantGradeCoef × grade) × (修飾語つきなら 1 + merchantModifierCoef) )   -- 係数は未決（M7b-6）
買える間     ：イベントの出発と同じ3分間（mapEventWindowSeconds）                                 -- D-179
レアダンジョン：強さは踏破済みの一番深いダンジョンと同じ（まだどこも踏破していなければ古い墓地：D-187）。宝箱の数 × rareDungeonChestMult（端数は確率で切り上げ：D-173）
              宝箱を増やす効果が重なったら、どれも元の宝箱に掛けて足し合わせる（日替わり→専用ギフト→レアダンジョンの順に引く：D-187、07章 §3）
              日替わりの特性は当てない（D-187）。1段上＝tier が一番深い踏破ダンジョンより大きいもののうち tier が最も小さいダンジョン
              宝箱の山は special:rare:<相当するダンジョン>（踏破済みの一番深いダンジョンの1段上。天空の玉座を踏破した後は天空の玉座のまま：D-185。
              まだどこも踏破していなければ古い墓地：D-187）。中身・アイテムレベルはそのダンジョンのもの   -- §19、D-171, D-187
レイド       ：その時間帯に出発したパーティのダメージ（出発時に計算）の合計 > HP なら討伐。宝箱は参加したパーティごとに1つ   -- D-179
              参加は1パーティ1回まで（帰ってきても同じ時間帯には出られない）。討伐の後に到着したパーティにも宝箱を1つ   -- D-187
              到着 = 出発 + raidTravelSeconds（ここでダメージを入れる）、帰還 = 到着 + raidTravelSeconds（仮）
              討伐の時点で到着しているパーティの分はそのとき、後から到着したパーティの分は到着のときに受け取り箱へ（special:raid を1つずつ）
              HP とダメージの式は M7b-6 で決める。M7b-4 の仮の式：
                HP     = floor(基準のダンジョン（踏破済みの一番深いダンジョン。未踏破なら古い墓地：D-187）の base.hp × raidHpMult × (raidHpSpread.min + u × (max − min)))
                         u は Rng.derive(state.seed, eventSlot) の一様乱数
                         最初に出発したときに決めて state.raid.hp に保存する
                ダメージ = floor(パーティ全員の攻撃力（出発時の実効値。§3）の合計 × raidDamagePerAtk)
```

サーバー全体で状態を持たない：時刻と固定の種だけから決まるので、どのサーバーでも同じ結果になる。

## 13. 留守番（D-161, D-193）

```
留守の始まり   = max(state.lastSavedAt, state.lastAdvancedAt)                     -- D-193（Game.offlineStart）
                 lastSavedAt：最後に保存した時刻（ふつうはログアウト時刻）。まだ書かれていなければ lastAdvancedAt
                 lastAdvancedAt：最後に時間を進めた時刻（オンラインで進めた分を留守として重ねて数えない）
留守番の終わり = 留守の始まり + offlineMaxSeconds（6時間。拡張しない）
留守番の探索   = 自動再派遣のダンジョンへ、今の探索エンジン（07章）で計算し、所要秒 × offlineTimeMult（10倍＝効率10%）
出す条件       = 自動再派遣が有効、かつ 帰還時刻 ≤ 留守番の終わり                  -- 6時間までに最後の探索を帰還させる
報酬           = 探索ログの報酬をそのまま（時間だけが10倍）。上限レベルの経験値の扱いはオンラインと同じ
```

- サーバーが落ちたとき、最後の定期保存から落ちるまでのオンラインの進み具合は失われ、その時間は次のログインで留守として計算される（二重にはならない）。これを仕様として受け入れる（D-193）。
- 留守番の探索には `offline = true` の印を付け、クエストに数えない・休息ボーナスを使わない。
- 6時間より前にログインしたら、帰っていない留守番の探索はログインの時点で帰還させる。留守中は倉庫がいっぱいでも止めない（D-172）。
- 途中ログインで持ち帰るもの（D-186）：

```
経過秒 = ログイン時刻 − 出発時刻
終わったフロア = floors の先頭から、startOffset + duration ≤ 経過秒 のフロア（留守番は時間を伸ばした後の値）
全フロアが終わっていれば（帰りの移動中）  → ログの報酬をそのまま（踏破なら踏破の報酬も）
そうでなければ                          → 終わったフロアの経験値・ゴールド・宝箱・アイテムの合計。撤退と同じ扱い
                                           （result = retreat、ギルド経験値 = 終わったフロア数 × guildExpPerFloor、踏破の報酬・初回踏破なし）
日替わりの特性・専用ギフト・レアダンジョンの倍率で増えた宝箱は、元の宝箱を持ち帰るときだけ持ち帰る（3つが重なっても同じ：D-187）
```
- 日替わりの特性は出発した日（出発時刻の dayIndex）の特性を当てる（§16）。
- ログイン時の計算量の目安：5パーティで約70回分。

## 14. 休息ボーナス（D-161, D-173, D-193）

```
たまる量 = floor((ログイン時刻 − 留守の始まり) × restBonusRate)          -- 留守にした時間の半分。留守の始まりは §13（max(lastSavedAt, lastAdvancedAt)：D-193）
restBonusSeconds = min(restBonusSeconds + たまる量, restBonusMaxSeconds)   -- 上限4時間
消費     = オンラインの advance で、経過秒だけ restBonusSeconds を減らす（0 未満にしない。探索しているかは問わない）
効き方   = オンライン中に帰還した探索（offline でない）の経験値に、帰還時に残りが 0 より大きければ × restBonusExpMult
重ね方   = 修練の護符（装備の経験値補正、D-082）・日替わりの expMult と掛け合わせる。expBonusCap（+100%）の外で掛ける
           (1 + min(経験値補正, expBonusCap)) × restBonusExpMult × (日替わりの expMult)
トレーニングの経験値には掛けない（§8b）
```

倍率・たまる速さは未決（M7b-6）。

## 15. クエストの量（D-153）

```
量 = Quests の amountPerParty × 解放済みのパーティ数（expansions.partySlots。入れ替えたときの値で固定）   -- 引き直しなし
入れ替え = dayIndex / weekIndex が変わった最初のオンラインの advance で、候補から daily は questDailyCount、weekly は questWeeklyCount 個を抽選
抽選の乱数 = Rng.new(Rng.derive(Rng.derive(Rng.derive(calendarSeed, 日または週の番号), state.seed), 期間の番号))
             期間の番号：daily = 1、weekly = 2。rngCounter は進めない（同じ日・同じプレイヤーなら何度計算しても同じ）
抽選の仕方 = 候補（Quests のその期間の行、データの順）から等確率で1つずつ、重複なしで引く
数え方     = オンライン中のコマンド・オンラインの advance の結果で数える（留守番の探索・留守中の帰還は数えない：D-161）
             探索の回数：Dispatch・オンラインの自動再派遣・DispatchEvent の出発ごとに1（D-179）
             宝箱を開けた数：OpenChests で開けた個数　雇用：HireChoose ごとに1
             トレーニング：Train で行った回数（1コマンドの sessions のうち実際に行った回数：D-191）
             踏破：オンラインの advance で帰還した探索（offline でない）の result = clear ごとに1。レアダンジョンの踏破も数え、レイドは数えない（D-191）
             転生：RebirthChoose ごとに1
達成       = progress が target に届いたら done、その行の rewards を受け取り箱へ（progress は target を超えない）
             その期間のお題が全部 done になったら、questDailyBonus / questWeeklyBonus を受け取り箱へ（bonusDone）
```

量の式・候補は未決（M7b-6）。advance の中では帰還・自動再派遣を先に処理し、そのあとで日・週の切り替えを行う（05章 §3 の順）。

## 16. 日替わりの特性（D-156, D-173）

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

- レアリティを上げる特性は置かない（D-156）。
- 日ごとの特性なので「ダンジョン補正はない」（D-038・D-047）の例外として認める。攻撃力は個体補正の上限（+50%）、経験値は経験値補正の上限（+100%）の外で掛ける。宝箱の数の端数は確率で切り上げる（D-173）。

## 17. 一括売却の「弱い」（D-167, D-175）

```
装備 x が「弱い」 ⇔ x の枠（武器・防具）で、x を付けられる冒険者が1人以上いて、
                   その全員が今その枠に装備を付けていて、
                   その全員について 比べる値(x) < 今その枠に付けている装備の比べる値
比べる値 = 武器：攻撃力補正（§2 の性能値）／防具：物理防御 + 魔法防御（§2 の性能値の合計）
```

- その枠が空いている冒険者が1人でもいれば「弱い」としない（売らない）。
- 補助（盾・アクセサリー）は目的が分かれるので対象外（D-120 の自動装備と同じ考え）。
- 修飾語つき・保護中・装備中・商人で買ったもの（`fromMerchant`）は売らない。対象は開封結果に出た装備。

## 18. 今週の訪問者（D-158, D-170）

```
rng = Rng.new(Rng.derive(calendarSeed, weekIndex))           -- 全員共通。週の区切りは月曜（§11）
今週の訪問者 = acquire = "visitor" のユニークから1人を抽選（login のユニークは入れない：D-155）

雇用候補1人ごとに：
  ① 今週の訪問者を持っていなければ、weeklyVisitorChance で判定 → 当たればその候補は今週の訪問者
  ② ①が外れた（または①を飛ばした）ら、specialVisitorChance（0.5%）で判定
     → 当たれば、今週の訪問者以外の持っていない visitor のユニークから均等に1人（login のユニークは除く）
候補枠の数だけ判定する（枠が多いほど出やすいのは意図どおり）
同じ雇用の候補に同じユニークは2人出さない（①で当たった後の枠は①を飛ばす。②の候補からも除く）
今週の訪問者の抽選 = Rng.pickWeighted（均等：D-194。ユニークごとの重みはユニークが増えてから決める）。候補の並びは Uniques のデータの順
乱数の消費順（候補1人ごと）= ①の判定（飛ばすときは引かない）→ ②の判定 →（当たれば）②の候補から1人 →（外れたら）一般の候補
```

`weeklyVisitorChance` は 0.03（仮）。値と週に何人回すかは M7b-6 で決める。実装は `src/core/Visitor.luau`、雇用画面のバナーは `Game.query.weeklyVisitor`（今週の訪問者・候補1人あたりの出現率・仲間済みか・次の週の区切り）。

## 19. 特別な宝箱（D-166, D-142）

```
ランク           = SpecialChests の rarityWeights から重み付き抽選
                   （レアダンジョンの山 special:rare:<dng> は、そのダンジョンの chestRarityWeights：D-171）
演出率の検査     = 行ごとに effectMinRarity 以上が出る割合が effectRateMin〜effectRateMax（D-090 の検査は普通のダンジョンだけ）
                   （レアダンジョンの山は、そのダンジョンの rareChestEffectMinRarity 以上が出る割合を rareDungeonEffectRate（20〜30%）で検査：D-171）
演出の選び方の順位 = 「その宝箱の表での順位」（D-142 の「そのダンジョンでの順位」を読み替える）
中身のアイテムレベル = 開けたときに踏破している一番深いダンジョンの tier（山は数だけを保存するため：D-171）
                   中身のそのほか（修飾語の候補・売却用アイテム・ゴールド・転職ポーションの職業）も同じダンジョンの表
                   （まだどこも踏破していなければ古い墓地：D-187）
                   レアダンジョンの山は鍵の相当するダンジョンの表（アイテムレベルもその tier：D-187）
ランクを決める時 = 受け取り箱に届いたとき（InboxEntry.rewards.chests の rank）。報酬の rank を書いた宝箱はそのランク
```

クエスト・ログインボーナス・プレイ時間の宝箱も特別な宝箱（D-171）。

## 20. プレイ時間・ログインボーナス・フレンドボタン・紹介（D-154, D-155, D-157, D-190, D-192, D-195）

```
プレイ時間  ：playtime.seconds = min(seconds + オンラインの経過秒, playtimeDailyCapSeconds)。PlaytimeRewards の minutes × 60 に届いた段階の報酬を受け取り箱へ
ログイン    ：login.lastDayIndex < dayIndex なら、day の報酬を受け取り箱へ入れてから1日進める（途切れても戻らない）。day = 7 の次は day = 1・cycle + 1
              7日目：master の loginOrder 順のログイン用ユニークの cycle 番目。いない・持っている（受け取り箱に届いている）なら fallback
プレイ時間の足し方：オンラインの advance ごとに 経過秒 = ctx.now − 前回の advance の時刻（ログイン時の留守の計算で前回の時刻は ctx.now になるので、ログイン直後の最初の advance は 0）
              日が変わっていたら seconds・claimedSteps を 0 に戻し、足すのは今日の区切り（Calendar.dayStart）より後の分だけ
フレンド    ：ctx.now ≥ friend.nextAt のとき押せる。報酬は人数 min(friendCount, friendRewardMaxFriends) で少し増える。押したら nextAt = ctx.now + friendRewardIntervalSeconds（押さないとたまらない）
              ゴールド = floor(rewardGoldBase[基準のダンジョン] × friendRewardGoldMult × (1 + friendRewardBonusPerFriend × (min(friendCount, friendRewardMaxFriends) − 1)))   -- §22、D-190
              friendCount はサーバーが数えて ctx.friendCount で渡す（M7b-5）。1 未満なら押せない（NO_FRIEND）
              1日に friendRewardDailyCap 回まで（friend.dayIndex が今日と違えば todayCount を 0 として数える）
紹介        ：報酬はステータススロットチケット（referralRewards）。招待した側・された側とも、招待された人が進み具合の条件に届いたときに渡す（D-192）
              進み具合 = Friend.referralProgressReached(state, master)：referralProgressCondition の kind = "rebirthsTotal" なら
                         これまでに転生した回数の累計 stats.rebirths ≥ count（仮：count = 1＝初転生）                 -- D-195
                         stats.rebirths は RebirthChoose（転生の確定）で +1。解雇しても戻らない（今いる冒険者の rebirthCount では数えない）
              招待された側は1回だけ（届く前は PROGRESS_NOT_REACHED）。招待した側は相手（UserId）1人ごと・週に referralWeeklyCap 人まで
              （referral.weekIndex が今週と違えば weekCount を 0 として数える）。週の上限を超えた届け物は翌週まで届け物の箱に残す。どちらも受け取り箱へ
```

プレイ時間・ログインボーナスのゴールドは rewards の goldMult から §22 の式で出す（固定額は置かない：D-190）。量は未決（M7b-6）。

## 21. 専用ギフトのパーティ効果（D-174）

```
専用ギフト（Gifts.exclusive）に限り、partyEffect を持てる（例：パーティ全員の移動が少し速い・宝箱が少し増える）
同じ効果はパーティ内で重ねない（道案内と同じ扱い：§7、D-070）
効き方：移動は片道秒に掛ける（§7）、宝箱は数に掛けて端数は確率で切り上げ（§5、D-173）
種類  ：travelMult（0 < value ≤ 1）・chestMult（value ≥ 1）の2つだけ（決定の例の範囲）
宝箱  ：掛ける対象は探索で得た元の宝箱（日替わりの特性 chestMult で増えた分には掛けない）。日替わりの分の後ろに足す
移動  ：片道秒 = … × 日替わりの travelMult × 専用ギフトの travelMult（道案内とは別の効果なので両方掛かる）
```

ゲーム仕様書04章の「補正の発生源は個体のみ」の例外。効果の種類と量は、専用ギフトの中身が決まってから足す（D-165）。

## 22. 報酬のゴールド（D-190, D-187）

```
基準のダンジョン = 踏破した一番深いダンジョン（tier が最大。同じ tier は並びの先）
                   まだどこも踏破していなければ一番浅いダンジョン（古い墓地：D-187）      -- Chest.baseDungeon
ゴールド         = floor(rewardGoldBase[基準のダンジョン] × 報酬ごとの係数)               -- Formulas.rewardGold
報酬ごとの係数   = プレイ時間・クエスト・ログインボーナス：rewards の goldMult（Quests・PlaytimeRewards・LoginBonus、全部達成のボーナスも同じ形）
                   フレンドボタン：friendRewardGoldMult × (1 + friendRewardBonusPerFriend × (min(friendCount, friendRewardMaxFriends) − 1))（§20）
額を決める時     = 受け取り箱に入れたとき（InboxEntry.rewards.gold に額を保存。後で深く踏破しても変わらない）。フレンドボタンは押したとき
```

- 報酬のゴールドに固定額は置かない（rewards に `gold` を書くと検証で止める）。`rewardGoldBase` はダンジョンごとに1つ（全ダンジョン必須）。
- 値（`rewardGoldBase`・各 `goldMult`・`friendRewardGoldMult`）は仮（M7b-6 の自動プレイで決める。D-154 の「1時間の収入の数%」に合わせる）。仮の `rewardGoldBase` は各ダンジョンの `battleReward.gold` に比例させ、古い墓地を 100 にした。

## 23. ゲーム外の通知：いつも遊ぶ時刻・許可の画面（D-159, D-196）

```
ログインの記録 ：ログイン（サーバーの読み込み）のたびに loginTimes の末尾へ ctx.now − Calendar.dayStart(ctx.now)（UTC 0時からの秒）を足す
                 notifyLoginHistoryCount（7）回を超えたら先頭（一番古いもの）を捨てる                               -- Notify.recordLogin
いつも遊ぶ時刻 ：loginTimes を小さい順に並べた中央値。数が偶数なら真ん中の2つのうち小さいほう（平均はとらない）       -- Notify.usualTimeOfDay
                 記録がなければ、今回ログインした時刻の位置で代わりにする（読み込みで必ず1回足すので、ふつうは起きない）
送る時刻       ：いつも遊ぶ時刻のうち、退出から notifyMinAwaySeconds 以上あとの最初のもの（サーバーの NotificationPicker.sendAt）
「得意」（③）  ：送る時刻の日の日替わりの特性が、自動再派遣にしているダンジョンに当たる                              -- D-196 ①
許可の画面     ：promptDue = "firstReturn"  … stats.firstReturnAt があり（初めての帰還）、settings.notifyPrompt.firstReturn = false
                             "loginDay2"    … firstReturn = true、loginDay2 = false、ログインボーナスの2日目を受け取り済み（login.cycle > 1 または login.day > 2）
                             nil            … それ以外                                                               -- Notify.promptDue
                 出したら MarkNotifyPrompt で記録する。firstReturn を記録したときに2日目をもう受け取っていたら loginDay2 も記録する（続けて2回出さない）
```

- 1日の中の位置は日の区切り（D-168。UTC 0時）から数える。0時をまたいで遊ぶ人（例：23時と1時）の中央値は、円として扱わずに数の並びで出す（Q 候補）。
- 許可したかどうかはサーバーからは分からない。2日目に出すかは、クライアントが Roblox の `CanPromptOptInAsync` で確かめる（許可済み・13歳未満・最近出したなら出さずに記録だけ付ける）。