defmodule Zongzi.Anchor do
  @moduledoc ~S"""
  Intervention 结构 rebase 的批量编排。

  消费 edit batch（一组 interventions + 编辑后的 Timeline），
  对每个 intervention 调其 strategy 的 `rebase/3`，
  按决策分类为 `:survived` 与 `:conflicts`。

  这是纯函数编排——不调用引擎、不比对 snapshot。
  语义存活判定属于 `Declaration.resolve`（渲染时），
  本模块只做结构锚的批量判定（编辑后）。

  ## 两阶段全景

  1. **编辑后** — `Anchor.rebase_all/4`（本模块）
     结构锚 rebase → preserve/rebase/relocate/conflict 分类

  2. **渲染时** — 各引擎 `render` → `Declaration.resolve/2`
     snapshot 比对 → delta apply / conflict

  ## 谁调用

  **Host**（库外，如 Equinox）在 Timeline 写操作落地后调用本模块，
  并注入 `Anchor.Context`（Note 快照等）。zongzi 不实现 Host。

  ## 交互契约

      # edit batch ───────────────────────────────────┐
      #     │                                         │
      #     ▼                                         │
      # Timeline 状态落地（insert/split/merge/delete）│
      #     │                                         │
      #     ▼                                         │
      # Anchor.rebase_all(ints, tl, ctx)  ←── Host 注入 Context
      #     │
      #     ├─ survived [Intervention.t()] ──→ 可进 render request
      #     │
      #     └─ conflicts [{int, reason}]  ──→ 上浮 UI
  """
  alias Zongzi.{Intervention, Timeline}

  @type rebase_result :: %{
          survived: [Intervention.t()],
          conflicts: [{Intervention.t(), Zongzi.Anchor.Strategy.reason()}]
        }

  @doc """
  edit batch 对全部 intervention 跑结构 rebase，按决策分类。

  ## 参数

  - `interventions` — 需要 rebase 的 interventions（可以为空）
  - `timeline` — **编辑后**的 Timeline（note_order/tombstones/seq_map 已更新）
  - `context` — Host 注入的 Context（`notes_by_seq`、`seq_to_window` 等）
  - `opts`:
    - `:default_strategy` — intervention 未指定 strategy 时的回退，默认 `Zongzi.Anchor.NoteTriplet`

  ## 分类规则

  | decision | 去向 |
  |---|---|
  | `{:ok, :preserve}` | survived（原样） |
  | `{:ok, {:rebase, updated}}` | survived（锚已更新） |
  | `{:ok, {:relocate, updated, meta}}` | survived（锚已重定位） |
  | `{:conflict, reason}` | conflicts |
  """
  @spec rebase_all([Intervention.t()], Timeline.t(), Zongzi.Anchor.Context.t(), keyword()) ::
          rebase_result()
  def rebase_all(interventions, timeline, context \\ Zongzi.Anchor.Context.new(), opts \\ []) do
    default_strategy = Keyword.get(opts, :default_strategy, Zongzi.Anchor.NoteTriplet)

    interventions
    |> Enum.map(fn int ->
      strategy = int.strategy || default_strategy
      {int, strategy.rebase(int, timeline, context)}
    end)
    |> Enum.reduce(%{survived: [], conflicts: []}, fn
      {int, {:ok, :preserve}}, acc ->
        %{acc | survived: [int | acc.survived]}

      {_int, {:ok, {:rebase, updated}}}, acc ->
        %{acc | survived: [updated | acc.survived]}

      {_int, {:ok, {:relocate, updated, _meta}}}, acc ->
        %{acc | survived: [updated | acc.survived]}

      {int, {:conflict, reason}}, acc ->
        %{acc | conflicts: [{int, reason} | acc.conflicts]}
    end)
    |> then(fn %{survived: s, conflicts: c} ->
      %{survived: Enum.reverse(s), conflicts: Enum.reverse(c)}
    end)
  end
end
