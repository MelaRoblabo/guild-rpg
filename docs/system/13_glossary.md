# 13 用語集（コード上の名前）

ゲーム仕様書14章と同じ。コードの名前はこの表に従う。

| 日本語 | コード | 備考 |
| --- | --- | --- |
| ギルド | guild | |
| 冒険者 | adventurer | |
| ユニークキャラ | unique | |
| 基礎ステータス | baseStats | 素の値 |
| 実効ステータス | effectiveStats | 装備・個体補正込み |
| 腕力／魔力／俊敏／技巧／HP | str / mag / agi / dex / hp | |
| 職業 | job | |
| 系統 | jobLine | warrior / scout / mage / support |
| 攻撃区分 | attackType | physical / magic |
| レア職 | isRare | |
| ギフト | gift | |
| パーティ | party | |
| 隊列 | slot | 1〜4 |
| 被弾率 | hitWeights | |
| 派遣・探索 | expedition | |
| 探索ログ | expeditionLog | |
| 踏破／撤退 | clear / retreat | |
| 戦闘不能 | down | |
| 宝箱／宝箱ランク | chest / rank | 保管は数だけ（chests[pileKey][rank]、D-084, D-166） |
| レアリティ | rarity | 1〜（リリース時6＝ミシック。D-085） |
| 基本アイテム | equipmentBase | |
| 装備個体 | equipmentItem | uid を持つ |
| エンチャント（旧称：修飾語） | modifier | 修飾語の付いた装備は「エンチャント装備」（英語 Enchanted）。一覧ではマスの背景の色で示す（D-303） |
| グレード（プラス） | grade | 0〜3。画面では「+1」などと出すので、プラス（+1 以上の装備）とも呼ぶ（D-303） |
| 個体補正 | personalBonus | 上限 +50%（D-070） |
| 面接 | interview / hireSession | |
| ステータススロット | statSlot | |
| ステータススロットチケット | itm_slot_ticket | |
| 転生 | rebirth | |
| 転職 | jobChange | |
| 見た目 | appearance | |
| 見た目のタイプ | looks | bea / nor / ugl / dem |
| 見た目の職業区分 | outfitClass | phy / mag |
| 攻略ヒント | dungeonHint | |
| 種族タグ | raceTag | undead など |
| ギルドレベル | guildLevel | |
| 拡張 | expansion | |
| トレーニング | training / Train | ゴールドで経験値を得る（D-076） |
| トレーニング場 | trainingLevel / trainingFacility | 拡張の一つ（D-077） |
| まとめて開く | OpenChests / chestBatchOpen | 宝箱の山ごとに最大100個まとめて開ける（D-089, D-166） |
| 開封演出 | effect / chestEffectMinRarity / chestEffectRate | 発生ライン以上のレアリティの宝箱で入る演出。演出率10〜15%は普通のダンジョンだけ（特別な宝箱は種類ごとの基準、D-089, D-090, D-166） |
| 転生費用 | rebirthCost | D-080 |
| 経験値補正 | expRate / expPct | ギフト＋装備（修練の護符）。上限 expBonusCap（D-082） |
| ティッカー | ticker | 次の行動へ導く印（数・！・NEW・光る）（D-123, D-124） |
| デザインシステム | Guild UI | 全画面の色の役割・配置・部品・入力の決まり（D-150） |
| 仮想時計 | virtualClock | ツール側のみ |
| 受け取り箱 | inbox | D-164 |
| 留守番 | offlineRun | D-161 |
| 日替わりの特性 | dailyTrait | D-156 |
| マップイベント | mapEvent | D-152 |
| レアダンジョン | rareDungeon | D-152 |
| レイドボス | raid | D-152 |
| 旅の商人 | merchant | D-152 |
| クエスト | quest | daily / weekly、D-153 |
| プレイ時間報酬 | playtimeReward | D-154 |
| ログインボーナス | loginBonus | D-155 |
| フレンドボタン | friendReward | D-157 |
| 今週の訪問者 | weeklyVisitor | D-158 |
| 専用ギフト | exclusive | Gifts の印、D-165 |
| 宝箱の山 | chestPile / pileKey | 通常は dungeonId、特別は special:xxx、D-166 |
| 特別な宝箱 | specialChest | D-166 |
| 一括売却 | BulkSell | D-167。倉庫の Bulk Sell はレアリティ・エンチャント・プラスの入切で選んだ品を Sell でまとめて売る（D-303） |
| 日・週の番号 | dayIndex / weekIndex | UTC 0時、週は月曜、D-168 |
| 基準のダンジョン | baseDungeon | 踏破した一番深いダンジョン。未踏破なら古い墓地（D-187）。特別な宝箱・レアダンジョン・レイド・商人・報酬のゴールドで使う |
| 報酬のゴールド | rewardGold / rewardGoldBase / goldMult | 基準のダンジョンの rewardGoldBase × 報酬ごとの係数（D-190、06章 §22） |
| 紹介の進み具合 | referralProgressCondition / referralProgressReached | 紹介の報酬を渡す条件（初転生。これまでに転生した回数の累計で数える。D-192, D-195） |
| 留守の始まり | offlineStart | max(lastSavedAt, lastAdvancedAt)（D-193） |

**使わない用語**：前衛・後衛・戦闘力・パーティ最大HP・前衛系・編成ボーナス・ダンジョン相性・ダンジョン補正・鍵付き宝箱・見た目図鑑・派遣費（D-163 で廃止）・休息ボーナス（D-280 で廃止）。
