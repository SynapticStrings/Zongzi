# Glossary

用于后续翻译。与 Playbook §3 保持同步。

| en | zh | ja | 备注 |
| --- | --- | --- | --- |
| Caller | Caller | Caller（呼び出し側） | 不译，首现给注 |
| SeqID | 序号 ID | シーケンスID | 标识符保留英文 |
| Timeline | 时间线 | タイムライン | |
| tombstone (merge/delete) | 墓碑（合并/删除） | トゥームストーン | 两类必须分开译注 |
| intervention | 干预 | インターベンション | 结构体保留英文 |
| anchor / triplet | 锚 / 三元组 | アンカー / トリプレット | |
| focus / leg / host / orphan | 焦点 / 腿 / 宿主 / 孤儿 | フォーカス / レッグ / ホスト / オーファン | |
| neighborhood / hops | 邻域 / 跳数 | | |
| rebase | 变基 | リベース | |
| survive | 生还 | | rebase 结果集 `survived` |
| conflict | 冲突 | | structural conflict（rebase）vs semantic conflict（resolve），必须注明 |
| resolve | 判定 | リゾルブ | 语义判定；与 Elixir resolve 区分语境 |
| decision (preserve/relocate/split/conflict) | 决策 | 決定 | 枚举值不译 |
| Declaration / Strategy | 声明 / 策略 | デクラレーション / ストラテジー | |
| mount | 挂载 | マウント | create/mount/drop 三动词成组 |
| scope | 作用域 | スコープ | 带单位语义 |
| payload / snapshot / projection | 载荷 / 快照 / 投影 | ペイロード / スナップショット / プロジェクション | |
| params | 参数 | パラメータ | 与 intervention 的对立要译注 |
| Windowing | 分窗（名词）/ 窗口化（动词） | ウィンドウイング | |
| Segment | 片段 | セグメント | 瞬态，无持久 id |
| check / render | 检查 / 渲染 | チェック / レンダー | 轻/重两档 |
| edit batch | 编辑批次 | | |
| referenced seqs | 被参照的 SeqID | | Strategy.referenced_seqs/1 |
| tick / tpqn | 刻 / 每四分音符刻数 | ティック | |
| beat | 拍 | | |
| tempo map | 速度表 | | TempoMap |
| time signature | 拍号 | | |
| grid | 网格 | | 量化吸附 |
| engine | 引擎 | | |
| whole-track | 全轨 | | WholeTrack 策略 |
| parameterized curve | 参数化曲线 | | |
| control point | 控制点 | | |
| rasterize | 光栅化 | | 采样仅指 tick→值的过程时用 sample |
| adapter | 适配器 | | |
| phoneme timing | 音素时序 | | channel 名 `:phoneme_timing` |
| preutterance / overlap | 先行发声 / 重叠 | 先行発声 / オーバーラップ | |
| lyric | 歌词 | | |
| annotation | 备注 | | |
| metadata | 元数据 | | |
| active | 活跃 | | Query.status 的四态之一 |
| missing | 缺失 | | |
| preserve | 保留 | | decision 标签之一 |
| relocate | 重定位 | | decision 标签之一 |
| split / merge | 拆分 / 合并 | | |
| drag | 拖动 | | |
| sentinel | 哨兵值 | | `:dynamic_tick` |
| gc | 墓碑回收 | GC | Timeline.gc |
| behaviour / callback | 行为 / 回调 | | |
| domain object / value object | 域对象 / 值对象 | | Util.Model / Util.Object |
