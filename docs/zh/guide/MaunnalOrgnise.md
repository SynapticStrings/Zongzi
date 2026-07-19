# 手动整理笔记

由 DeepSeek v4 + Hermes Agent 输出，后续会人工编辑修正更新。

最终目标是如 *The Reasoned Schemer* 一样的问答形式的文档。

## Phase 0 —— 是什么

> Q0. 这个库想解决什么问题？它给谁用的？

A. zongzi 是一个应用于 SVS 应用的内核/接口，其针对调教过程中音符变化后（拖拽等）调教参数静默失效的情况而被设计，旨在将失效行为暴露给用户让其定夺。

> Q1. 除了这个仓库还有什么？

A. 可以看 <https://github.com/GES233/zongzi_feasibiliity>

## Phase 1：数据层 —— 存了什么

涉及的模块：

- `Zongzi.Score.{Note, Key}` 不包括时间系统（`Zongzi.Score.{Tick, TimeSig, TimeSigMap, Tempo, TempoMap, Record, RecordMap}`）
- `Zongzi.Timeline`

> Q1. Timeline 存的是什么？一个 note 有哪些字段？

A. 

先回答第一个问题，`Timeline` 的数据结构是将轨道上音符之间的邻接关系显式建模所设立，其需求是在注入拖拽音符到新位置的这类情况以及需要用到邻近音符之间的关系。

note 主要用于记录音符……

---

*以下部分尚未跟进*

> Q2. seq_id 是什么，谁分配它？

> Q3. Timeline 是双向链表还是别的数据结构？怎么遍历？

> Q4. 如果我改一个 note 的歌词，Timeline 本身会变吗？

产出：手写一张 A4 纸的图——一个三音符 Timeline，标出每个 note 的 seq_id、start_tick、duration、彼此的 prev/next 关系。

## Phase 2：介入数据 —— 用户怎么盖掉模型生成

涉及的模块：

- `Zongzi.Intervention`

要回答的问题：

0. 为什么叫 Intervention ？什么才算做 Interv ？
1. Intervention 绑在哪个 note 上？（anchor 三元组是什么）
2. payload 里存什么？
3. snapshot 是什么时候拍的？为什么要拍？
4. scope 是什么作用的？
5. strategy 字段是干嘛的？

产出：在上一步的 A4 图上，画一个 Intervention 挂到中间那个 note 上。标出 anchor = 哪三个 seq_id，snapshot = 什么内容，scope = 什么范围。

## Phase 3：编辑之后怎么同步（Anchor + Rebase）

文件：zongzi/lib/zongzi/anchor.ex

这是最难的一步，但也是整个库的灵魂。慢读。

要回答的问题：

1. rebase_all 输入什么输出什么？
2. "结构层冲突"是指什么？（preserve / rebase / relocate / split / conflict 各是什么场景）
3. split note 时，挂在原 note 上的 Intervention 怎么处理？
4. delete note 时，Intervention 怎么可能 relocate？

产出：从 Phase 1 的三音符 Timeline 出发，画三个 case 的 before/after：
- split 中间音符 → 两个子 intervention
- delete 中间音符 → intervention relocate 到邻居
- 改歌词不拆音符 → intervention preserve

## Phase 4：引擎怎么消费（Windowing + Engine）

文件：zongzi/lib/zongzi/windowing.ex、zongzi/lib/zongzi/engine.ex

要回答的问题：

1. Windowing 把 Timeline 切成什么给 Engine？为什么要切？
2. Engine behaviour 要求实现哪几个函数？输入输出各是什么形状？
3. preutterance / spill 是什么概念？spill 会导致什么冲突？

产出：画出 Phase 1 的 Timeline 被 Windowing 切成一个 Segment，标注 spill 的范围。然后用伪代码写一个 Engine.check(segments, interventions) 的调用——不要求代码正确，只要求你能写出每个参数"应该长什么样"。

## Phase 5：Declaration（语义层决议）

文件：zongzi_feasibility/lib/zongzi_feasibility/declaration/pitch.ex

要回答的问题：

1. Declaration behaviour 要求实现哪几个回调？（scope / snapshot / resolve）
2. resolve 什么时候返回 {:ok, applied}，什么时候返回 {:conflict, :snapshot_stale}？
3. snapshot 的归一化做了什么？为什么需要归一化？
4. "snapshot 失配"在 BRAPA 口音切换场景下对应什么？

产出：写一个具体的 BRAPA 例子：用户在音符上设了 Pitch Intervention，然后声库作者更新了 rendering engine。用 resolve 的输入输出描述这个 rebase 过程——不需要代码，用表格：

| 步骤          | snapshot       | 新投影         | 结果     |
|---------------|----------------|----------------|----------|
| 挂载时        | [42, 440.0, 1] | —              | —        |
| 更新后 rebase | [42, 440.0, 1] | [42, 445.0, 1] | conflict |

## Phase 6：Caller 怎么串起来（编排层）

文件：zongzi_feasibility/lib/zongzi_feasibility/caller.ex

要回答的问题：

1. Caller 持有哪几样东西？
2. edit 函数的完整回路是什么？（写 op → apply → Anchor.rebase → refresh scope → window → report）
3. check_round 和 render_round 的区别？
4. tick↔frame 换算为什么在 Caller 做而不是在 Engine 做？

产出：画一张流程图，从"用户改歌词"开始，到最后拿到 report，中间 Caller 调了哪些 zongzi 模块，每一步的数据形状。

## Phase 7：Golden Scenarios（冒烟测试即文档）

文件：zongzi_feasibility/lib/zongzi_feasibility/scenarios/g_pre_01.ex、g_int_01.ex、g_int_02.ex

按这个顺序读，每个场景问：

1. setup 造了什么数据？
2. edits 做了哪个操作？
3. expect 断言了什么？如果断言失败，意味着什么保护被破坏了？

产出：用自己的话重写这三个 scenario 的标题和期望，不加代码，只讲故事。比如：

> G-PRE-01：两个音符紧挨着，B 改歌词后 preutterance 前移，因为没有 Intervention 挂在 A 尾部，一切自动通过。
>
> G-INT-02：用户在 B 音符挂了 pitch 编辑，然后改了 B 的音高。snapshot 失配 → conflict，不静默 apply。
