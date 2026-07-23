defmodule Zongzi.Timeline.Neighborhood do
  @moduledoc """
  Local sequences view 以 focus 为中心

  List order in `left` / `right` prensents 由近到远
  """

  alias Zongzi.Timeline.SeqID

  @type status :: :active | :merge_tombstone | :delete_tombstone

  @typedoc "在链表上的格距（依照 Query 的选项确定包含或舍弃墓碑格）"
  @type hops_from_focus :: non_neg_integer()

  @type cell :: %{
          seq_id: SeqID.t(),
          status: status(),
          hops_from_focus: hops_from_focus()
        }

  @type t :: %__MODULE__{
          focus: SeqID.t() | nil,
          focus_status: status() | :missing,
          left: [cell()],
          right: [cell()]
        }

  defstruct focus: nil, focus_status: :missing, left: [], right: []
end
