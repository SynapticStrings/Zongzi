# 试验场景

Zongzi 及基于其开发的 SVS 编辑器的显著不同，是出发点是**跨引擎的参数处理方案**。  
库的设计源于使用场景的声明；场景即约束。

具体用例随结构层 / 引擎接入补全。下方只钉**场景族**与验收轴，避免空 TBD 误导。

## 模型（与心智对齐）

- 序列真相在 Timeline；intervention 锚 SeqID。
- 结构存活（编辑后）与语义存活（渲染时）分阶段。
- 曲线/timing 类：控制点（或偏移）+ 边界 + 原始值；原始值进 snapshot。
- G2P 类：挂 note / 序列，不假装成曲线。
- Caller 编排；zongzi 不假装自己是编辑器。

## Golden Scenarios（骨架）

每条场景落地时应有：前置 Timeline 状态 → 编辑 / 挂载 → 期望 rebase 决策 →（可选）resolve 决策。

| ID | 族 | 意图 | 主要模块 | 状态 |
|---|---|---|---|---|
| G-TL-01 | Timeline 编辑 | insert / split / merge / delete / drag 后 note_order 与墓碑语义 | Timeline | 有单测（zongzi 核） |
| G-TL-02 | 墓碑 GC | 无 anchor 引用的 tombstone 可 gc；仍被 anchor 引用的保留 | Timeline.gc | 有单测（zongzi 核） |
| G-AN-01 | 2-of-3 | 邻接变一条 → rebase；变两条 → adjacency_lost | NoteTriplet | 有单测 / spike（zongzi 核） |
| G-AN-02 | merge 墓碑 | focus 被 merge → merged_away | NoteTriplet | 有单测（zongzi 核） |
| G-AN-03 | delete 孤儿 | focus 删除 → relocate（方向 / 打分）或 no_host | NoteTriplet / ScoredHost | 有单测（zongzi 核） |
| G-AN-04 | 跨窗 forbid | ScoredHost 在 seq_to_window 下拒绝跨窗宿主 | ScoredHost | 有单测（zongzi 核，Context 注入） |
| G-INT-01 | 挂载→编辑→rebase→resolve | 完整对抗一轮（mock Declaration） | ZongziFeasibility | 已落地 |
| G-INT-02 | snapshot 失配 | 投影变了 → conflict / skip，不静默 apply | Declaration 实现 | 已落地 |
| G-PRE-01 | 紧靠·无 interv | A-B 紧靠，均无 intervention。改 B 歌词 → preutterance 前移 | 结构无 conflict；preutterance 自然被连续音符吸收 | 已落地 |
| G-PRE-02 | 紧靠·有 interv | A 尾部有 pitch curve interv，A-B 紧靠。改 B 歌词 → preutterance 挤入 A 尾部 | 结构无 conflict；语义层：A 尾部投影可能被 preutterance 覆盖 → resolution 需引擎上下文判真假 | 已落地 |
| G-PRE-03 | 小 gap·无 interv | A-B 间隙 < preutterance 典型值，均无 interv。改 B 歌词 → preutterance 溢出到 gap 内，不触及 A | 结构无 conflict；语义层：投影变了但 A 无 interv → 无 conflict | 已落地 |
| G-PRE-04 | 小 gap·有 interv | A 尾部有 interv，A-B 间隙 < preutterance。改 B 歌词 → preutterance 溢出，可能与 A 尾部 interv 碰撞 | 结构无 conflict；语义层：需引擎上下文（实际音素边界）判断是否真碰撞，而非静默 conflict | 已落地 |
| G-PRE-05 | 大 gap | A-B 间隙 >> preutterance（如 RestSplit3Beats 切开的两窗）。改 B 歌词 | 结构无 conflict；preutterance 不跨窗边界 | 已落地 |
| G-PRE-06 | 重叠音符 | A 尾与 B 头重叠（A.end_tick > B.start_tick）。改 B 歌词 → preutterance 在重叠区内变化 | 结构可能 affected（取决于 anchor 形状）；语义层：重叠区投影竞争 | 已落地 |
| G-PRE-07 | 三重链 | A-B-C 连续。B 无 interv，A 和 C 各有 interv。改 B 歌词 | B 结构变化导致 A/C 的 anchor triplet 重算；语义层：A 尾 + C 头投影可能同时受影响 | 已落地 |
| G-WIN-01 | Timeline 分窗 | post-rebase：`Windowing.run_stages`；默认空≥3拍且 1/2 归属 → `[Segment]` | Windowing | 有单测（zongzi 核） |
| G-ENG-01 | 引擎错误 vs conflict | render error 与 intervention conflict 分流 | Engine 契约 | 未落地 |
| G-ENG-02 | segments 统一入口 | `check`/`render` 只吃 `[Segment]`；整轨=单段 | Engine | 已落地 |

> **状态约定**：`已落地` 表示在 `zongzi_feasibility` 有完整对抗实现；`有单测（zongzi 核）` 表示仅在 `zongzi` 核内有单测，`zongzi_feasibility` 未覆盖。

## 补场景时的写法

```text
### G-XX-NN 标题
- Given: ...
- When: ...
- Then (结构): preserve | rebase | relocate | conflict(...)
- Then (语义, 可选): apply | conflict | skip
- 非目标: ...（例如不测 UI 手绘）
```

实现优先补「已落地」和「有单测（zongzi 核）」行的文档化；**未落地**行不要写假结果。

## 决策索引

见 `docs/zh/spec/decisions/README.md`。
