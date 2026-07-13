defmodule Zongzi.Timeline.Neighborhood do
  @moduledoc """
  以 focus 为中心的局部序列视图（纯结构，无 Note 字段）。

  - `left` / `right`：由近到远
  - `hops_from_focus`：在 note_order 上的格距（含墓碑格）
  """

  alias Zongzi.Timeline.SeqID

  @type status :: :active | :merge_tombstone | :delete_tombstone

  @type cell :: %{
          seq_id: SeqID.t(),
          status: status(),
          order_index: non_neg_integer(),
          hops_from_focus: non_neg_integer()
        }

  @type t :: %__MODULE__{
          focus: SeqID.t() | nil,
          focus_status: status() | :missing,
          left: [cell()],
          right: [cell()]
        }

  defstruct focus: nil, focus_status: :missing, left: [], right: []
end
