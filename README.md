# 粽子 (Zongzi)

Zongzi 是：

1. 提供构建 SVS 编辑器的函数式组件与规范
2. 为 BEAM 生态的不同 SVS 处理组件提供统一适配

换言之，就是 SVS 领域的 plug without server 。

## 核心架构（2025-07 重构方向）

### 引擎契约：behaviour，不是 pipeline

zongzi 不跑渲染——只定义引擎必须遵守的 `@callback`。内部实现可以是复杂 DAG、
pipeline 或任意结构，zongzi 不关心。

### 多轮对抗式循环

```
render → interventions 挂/撤销在 Timeline 上 → render → ...
```

一次完整渲染 = N 轮。每轮引擎产出 Artifact，用户在 Timeline 上挂/撤 intervention，
下一轮 render 消费新的干预状态。没有独立的 resolve 或 adapt 步骤——
它们只是 intervention 的增删操作。

### 序列真相：Timeline + SeqID（RGA 简化子集）

借鉴 Sequence CRDT（RGA 系），但剃掉分布式共识部分：

- **SeqID** — 全局唯一、永不重用的位置标识。音符 split/merge/drag 后 SeqID 不变，
  Intervention 锚在 SeqID 上而非 Note.id。
- **note_order** — SeqID 的显式有序链表，是轨道的 ground truth
- **tombstones** — 被 merge 的音符 SeqID 保留在链表中（墓碑），维护邻接稳定性
- **adjacent/2** — 给定 SeqID，返回 `{prev, current, next}` 三元组

### 干预锚定：NoteTriplet + 2-of-3 exact match

Intervention 锚在三个 SeqID 上：`{prev_seq, current_seq, next_seq}`。
当 Timeline 变更后，用 2-of-3 exact match（不是 fuzzy）决定存活：

| 匹配数 | 决策 |
|---|---|
| 3/3 | trivial rebase |
| 2/3 | 自动跟（drag 后 prev+current 或 current+next 还在） |
| 1/3 | conflict |
| tombstone | conflict（被 merge 了） |
| orphan | 推到~~下一个~~临近活跃 SeqID[^active_seq_id] |

[^active_seq_id]: 比方说一个乐句的尾巴还有 pitch 曲线 intervention 的控制点，下一个乐句的开始有 phoneme timing 的 offset，需要各论各的

### Intervention 职责：编辑时保留 + 渲染时范围声明

1. **编辑时** — 音符 split/drag/merge 后，rebase 决定 preserve / conflict / push
2. **渲染时** — 声明本次 render 的作用范围（preutterance 归属、pitch 跨度等）

载荷轻量：控制点 + vector（如 phoneme timing delta）。策略默认简单，
可通过 `strategy: module()` 字段升级为可插拔的复杂处理。

### 当前状态

- `Curve.Adapter` — behaviour（已从 protocol 重构）
- `Key.Inner` — protocol（值级分发，保留）
- `SeqID` — monotonic integer 生成器 + compare
- `Note.seq_id` — auto-generated on new
- `Timeline` — note_order + seq_map + tombstones + adjacent + try_match
- `Intervention` — 待落地（规则已定型）

全部测试：148 pass，0 failures。

## 安装与应用

TBD
