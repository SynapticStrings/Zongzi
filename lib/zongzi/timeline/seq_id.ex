defmodule Zongzi.Timeline.SeqID do
  @moduledoc """
  A module used only for recording IDs of the relationships between note sequences.

  设计借鉴 Sequence CRDT 的 position identifier（RGA 系）：

  - **永不改变、永不重用**：即使所属 Note 被 split/merge/drag，SeqID 也不变
  - **单调递增**：保证 Timeline 上的全序
  - **不编码后代关系**：split 产生的子 Note 用新 SeqID，父子关系由上层（Timeline）维护

  > **注意**：
  > 其和用户可见的注入 `"Note_abc123"` 的 `Note.id` 是不同的。`SeqID` 的生命周期更长，
  > 当其所属的 Note 被删除后，它的 `Note.id` 被回收/替换，但 `SeqID` 变成墓碑继续留在 Timeline 上，
  > 锚在其上的 Intervention 不会因为 ID 回收而失效。
  >
  > 此外，SeqID 只是稳定身份和分配顺序，在乐谱的顺序只能由 Timeline 链表决定。

  ## 用途

  - Timeline 双向链表的节点标识
  - Intervention anchor 的锚定目标
  - Note 删除后的墓碑标记
  """

  @typedoc "SeqID is a monotonically increasing positive integer."
  @type t :: pos_integer()
end
