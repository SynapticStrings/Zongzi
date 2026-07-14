defmodule Zongzi.Timeline.SeqID do
  @moduledoc """
  全局唯一的序列位置 ID。

  设计借鉴 Sequence CRDT 的 position identifier（RGA 系）：
  - **永不改变、永不重用**——即使所属 Note 被 split/merge/drag，SeqID 也不变
  - **单调递增**——保证 Timeline 上的全序
  - **不编码后代关系**——split 产生的子 Note 用新 SeqID，父子关系由上层（Timeline）维护

  ## Yjs 借鉴

  Yjs 的 ID 是 `(client_id, clock_counter)` 对。zongzi 是单用户编辑，
  不需要 client_id 维度的分片——直接用 Erlang 的 `System.unique_integer([:monotonic])`。
  这是 Yjs 在单副本退化下的等效物。

  ## 用途

  - Timeline.note_order 的链表节点标识
  - Intervention anchor 的锚定目标
  - Note 删除后的墓碑标记

  ## 为什么不用 Note.id

  `Note.id` 是业务标识（用户可见的 "Note_abc123"），`SeqID` 是结构标识（永不消失的序列节点）。
  Note 被 merge 后，它的 `Note.id` 被回收/替换，但 `SeqID` 变成墓碑继续留在 Timeline 上——
  锚在其上的 Intervention 不会因为 ID 回收而失效。
  """

  @typedoc "SeqID 是一个单调递增的正整数"
  @type t :: pos_integer()

  # SeqID 生成权已移交给 Timeline（自持 counter），不再提供全局 generate/0。
  # 这里只保留类型定义和比较函数。
  #
  # 原因：`System.unique_integer([:monotonic])` 是 BEAM 实例级的，跨会话重启后
  # 计数器归零，与已序列化的 seq_id 碰撞。Timeline 自持 `next_seq` 字段，
  # 反序列化时从已载入的 max seq_id + 1 起算。

  @doc """
  比较两个 SeqID 的先后顺序。

  返回 `:lt` | `:eq` | `:gt`。
  """
  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare(a, b) when a < b, do: :lt
  def compare(a, b) when a > b, do: :gt
  def compare(_a, _b), do: :eq

  # defguard is_seq_id(maybe_seq_id) when is_integer(maybe_seq_id) and maybe_seq_id > 0

  # def next(prev) when is_seq_id(prev), do: prev + 1

  # def next, do: 1
end
