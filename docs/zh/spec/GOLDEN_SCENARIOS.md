# 试验场景

Zongzi 及基于其开发的 SVS 编辑器的显著不同，是出发点是**跨引擎的参数处理方案**。  
库的设计源于使用场景的声明；场景即约束。

具体用例随结构层 / 引擎接入补全。下方只钉**场景族**与验收轴，避免空 TBD 误导。

## 模型（与心智对齐）

- 序列真相在 Timeline；intervention 锚 SeqID。
- 结构存活（编辑后）与语义存活（渲染时）分阶段。
- 曲线/timing 类：控制点（或偏移）+ 边界 + 原始值；原始值进 snapshot。
- G2P 类：挂 note / 序列，不假装成曲线。
- Host 编排；zongzi 不假装自己是编辑器。

## Golden Scenarios（骨架）

每条场景落地时应有：前置 Timeline 状态 → 编辑 / 挂载 → 期望 rebase 决策 →（可选）resolve 决策。

| ID | 族 | 意图 | 主要模块 | 状态 |
|---|---|---|---|---|
| G-TL-01 | Timeline 编辑 | insert / split / merge / delete / drag 后 note_order 与墓碑语义 | Timeline | 有单测 |
| G-TL-02 | 墓碑 GC | 无 anchor 引用的 tombstone 可 gc；仍被 anchor 引用的保留 | Timeline.gc | 有单测 |
| G-AN-01 | 2-of-3 | 邻接变一条 → rebase；变两条 → adjacency_lost | NoteTriplet | 有单测 / spike |
| G-AN-02 | merge 墓碑 | focus 被 merge → merged_away | NoteTriplet | 有单测 |
| G-AN-03 | delete 孤儿 | focus 删除 → relocate（方向 / 打分）或 no_host | NoteTriplet / ScoredHost | 有单测 |
| G-AN-04 | 跨窗 forbid | ScoredHost 在 seq_to_window 下拒绝跨窗宿主 | ScoredHost | 有单测（Context 注入） |
| G-INT-01 | 挂载→编辑→rebase→resolve | 完整对抗一轮（mock Declaration） | spike_test | spike |
| G-INT-02 | snapshot 失配 | 投影变了 → conflict / skip，不静默 apply | Declaration 实现 | spike / 引擎侧 |
| G-WIN-01 | Timeline 分窗 | post-rebase：`Strategy.window/1`；默认空≥3拍且 1/2 归属 → `[Segment]` | Windowing | 有单测 |
| G-ENG-01 | 引擎错误 vs conflict | render error 与 intervention conflict 分流 | Engine 契约 | **未落地** |
| G-ENG-02 | segments 统一入口 | `check`/`render` 只吃 `[Segment]`；整轨=单段 | Engine | 契约测有 |

## 补场景时的写法

```text
### G-XX-NN 标题
- Given: ...
- When: ...
- Then (结构): preserve | rebase | relocate | conflict(...)
- Then (语义, 可选): apply | conflict | skip
- 非目标: ...（例如不测 UI 手绘）
```

实现优先补「有单测」行的文档化；**未落地**行不要写假结果。

## 决策索引

见 `docs/zh/spec/decisions/README.md`。
