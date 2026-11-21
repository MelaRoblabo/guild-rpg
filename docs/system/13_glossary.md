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
| 宝箱／宝箱ランク | chest / rank | 保管は数だけ（chests[dungeonId][rank]、D-084） |
| レアリティ | rarity | 1〜（リリース時6＝ミシック。D-085） |
| 基本アイテム | equipmentBase | |
| 装備個体 | equipmentItem | uid を持つ |
| 修飾語 | modifier | |
| グレード | grade | 0〜3 |
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
| まとめて開く | OpenChests / chestBatchOpen | ダンジョンの宝箱を最大100個まとめて開ける（D-089） |
| 開封演出 | effect / chestEffectMinRarity / chestEffectRate | 発生ライン以上のレアリティの宝箱で入る演出。演出率10〜15%（D-089, D-090） |
| 派遣費 | dispatchFee | 上級ダンジョンの出発時の費用（D-079） |
| 転生費用 | rebirthCost | D-080 |
| 経験値補正 | expRate / expPct | ギフト＋装備（修練の護符）。上限 expBonusCap（D-082） |
| 仮想時計 | virtualClock | ツール側のみ |

**使わない用語**：前衛・後衛・戦闘力・パーティ最大HP・前衛系・編成ボーナス・ダンジョン相性・ダンジョン補正・鍵付き宝箱・見た目図鑑。
