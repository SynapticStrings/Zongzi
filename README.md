# 粽子 (Zongzi)

Zongzi 是：

1. 提供构建 SVS 编辑器的函数式组件与规范
2. 为 BEAM 生态的不同 SVS 处理组件提供统一适配

换言之，就是 SVS 领域的 plug without server。

## 核心架构

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

### 序列真相：Timeline + SeqID

借鉴 Sequence CRDT（RGA 系），剃掉分布式共识部分：

- **SeqID** — 永久位置标识。由 Timeline 自持 counter 生成（非全局 unique_integer），
  跨会话序列化安全。音符 split/merge/drag 后 SeqID 不变，
  Intervention 锚在 SeqID 上而非 Note.id。
- **note_order** — SeqID 的显式有序链表，是轨道的 ground truth
- **tombstones** — 被 merge 或 delete 的音符 SeqID 保留在链表中（墓碑），维护邻接稳定性。
  区分 merge 墓碑（seq_map 保留条目）和 delete 墓碑（seq_map 已移除）
- **adjacent/2** — 给定 SeqID，返回 `{prev, current, next}` 三元组
- **nearest_active/3** — 跳过墓碑双向扫描，孤儿 push 用
- **gc/2** — 手动回收无 intervention 引用的墓碑

### 干预锚定：NoteTriplet + 2-of-3 exact match

Intervention 锚在三个 SeqID 上：`{prev_seq, current_seq, next_seq}`。
当 Timeline 变更后，`Anchor.NoteTriplet.rebase/3` 用 2-of-3 exact match（不是 fuzzy）
决定存活：

| try_match 结果 | rebase 决策 |
|---|---|
| 3/3 | `:preserve` |
| 2/3 | `{:rebase, updated_intervention}`（自动跟） |
| 0–1/3 | `{:conflict, :adjacency_lost}` |
| merge tombstone | `{:conflict, :merged_away}` |
| delete tombstone | `{:push, nearest_seq, updated_intervention}`（沿 `orphan_direction` 推到最近活跃邻居） |

[^direction]: 方向由 channel strategy 决定——pitch 曲线尾巴往 `:prev` 找，phoneme timing offset 往 `:next` 找。各论各的。

### Intervention 生命周期

**结构层**（zongzi 内）：

1. 挂载 — 创建 `Intervention` struct，记录 anchor（三元组）、payload（delta）、snapshot（投影快照）
2. 编辑 — 音符 split/drag/merge/delete 后，`rebase` 判结构存活
3. 回收 — 用户确认无 conflict 后，手动 `gc` 清理未引用墓碑

**语义层**（引擎侧，由 `Intervention.Declaration` behaviour 定义）：

- `snapshot/2` — 从投影中提取干预依赖的原始值
- `resolve/2` — 比对存储快照与当前投影，apply delta 或上浮 conflict
- `scope/2` — 声明渲染范围（保守上界，静态可算）

载荷轻量：控制点 + vector（如 phoneme timing delta）。策略可通过 `strategy: module()`
字段插拔。

## 安装

```elixir
def deps do
  [{:zongzi, github: "SynapticStrings/Zongzi", branch: "main"}]
end
```
