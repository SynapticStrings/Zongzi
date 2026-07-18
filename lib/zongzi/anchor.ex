defmodule Zongzi.Anchor do
  @moduledoc ~S"""
  Intervention 结构在变基时的批量编排。

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

  **Caller**（库外编排者）在 Timeline 写操作落地后调用本模块，
  并注入 `Anchor.Context`（Note 快照等）。zongzi 不实现 Caller。

  ## 交互契约

      # edit batch ───────────────────────────────────┐
      #     │                                         │
      #     ▼                                         │
      # Timeline 状态落地（insert/split/merge/delete）│
      #     │                                         │
      #     ▼                                         │
      # Anchor.rebase_all(ints, timeline, ctx)  ←── Caller 注入 Context
      #     │
      #     ├─ survived [Intervention.t()] ──→ 可进 render request
      #     │
      #     └─ conflicts [{int, reason}]  ──→ 上浮 UI
  """
  alias Zongzi.{Intervention, Timeline}

  @type decision_label :: :preserve | :rebase | :relocate | :split | :conflict

  @type rebase_result :: %{
          survived: [Intervention.t()],
          conflicts: [{Intervention.t(), Zongzi.Anchor.Strategy.reason()}],
          decisions: %{optional(term()) => decision_label()}
        }

  @doc """
  edit batch 对全部 intervention 跑结构 rebase，按决策分类。

  ## 参数

  - `interventions` — 需要 rebase 的 interventions（可以为空）
  - `timeline` — **编辑后**的 Timeline（nodes/tombstones/seq_map 已更新）
  - `context` — Caller 注入的 Context（`notes_by_seq`、`seq_to_window` 等）
  - `opts`:
    - `:default_strategy` — intervention 未指定 strategy 时的回退，默认 `Zongzi.Anchor.NoteTriplet`

  ## 分类规则

  | decision | 去向 |
  |---|---|
  | `{:ok, :preserve}` | survived（原样） |
  | `{:ok, {:rebase, updated}}` | survived（锚已更新） |
  | `{:ok, {:relocate, updated, meta}}` | survived（锚已重定位；strategy 的 meta 并入 on_rebase meta） |
  | `{:conflict, reason}` | conflicts |

  ## 返回值

  - `:survived` — 存活 interventions（含 `on_rebase` split 出的子干预）
  - `:conflicts` — `{intervention, reason}` 列表
  - `:decisions` — `%{intervention_id => :preserve | :rebase | :relocate | :split | :conflict}`，
    每条 intervention 的结构决策（split 标在子干预上），供 Caller 做指标/日志

  ## on_rebase 钩子

  策略决策成功后，若 intervention 的 declaration 实现了 `on_rebase/4`，
  以 `(int, meta, timeline, context)` 调用——meta 含 `%{decision, old_anchor, new_anchor}`
  （relocate 时并入 strategy 的 meta），context 即本函数的 Caller 注入 Context
  （declaration 可用 `notes_by_seq` 等做 payload 的 tick 级维护）。
  `{:split, children}` 的子干预**不再过 strategy.rebase**——子干预锚的正确性由
  declaration 负责。
  """
  @spec rebase_all([Intervention.t()], Timeline.t(), Zongzi.Anchor.Context.t(), keyword()) ::
          rebase_result()
  def rebase_all(interventions, timeline, context \\ Zongzi.Anchor.Context.new(), opts \\ []) do
    default_strategy = Keyword.get(opts, :default_strategy, Zongzi.Anchor.NoteTriplet)

    interventions
    |> Enum.flat_map(fn int ->
      strategy = int.strategy || default_strategy

      case strategy.rebase(int, timeline, context) do
        {:ok, :preserve} ->
          meta = %{decision: :preserve, old_anchor: int.anchor, new_anchor: int.anchor}
          apply_on_rebase(int, meta, timeline, context, :preserve)

        {:ok, {:rebase, updated}} ->
          meta = %{decision: :rebase, old_anchor: int.anchor, new_anchor: updated.anchor}
          apply_on_rebase(updated, meta, timeline, context, :rebase)

        {:ok, {:relocate, updated, m}} ->
          meta =
            Map.merge(m, %{
              decision: :relocate,
              old_anchor: int.anchor,
              new_anchor: updated.anchor
            })

          apply_on_rebase(updated, meta, timeline, context, :relocate)

        {:conflict, reason} ->
          [{:conflict, {int, reason}}]
      end
    end)
    |> Enum.reduce(%{survived: [], conflicts: [], decisions: %{}}, fn
      {:ok, int, decision}, acc ->
        %{acc | survived: [int | acc.survived], decisions: Map.put(acc.decisions, int.id, decision)}

      {:conflict, {int, reason}}, acc ->
        %{
          acc
          | conflicts: [{int, reason} | acc.conflicts],
            decisions: Map.put(acc.decisions, int.id, :conflict)
        }
    end)
    |> then(fn %{survived: s, conflicts: c} = acc ->
      %{acc | survived: Enum.reverse(s), conflicts: Enum.reverse(c)}
    end)
  end

  defp apply_on_rebase(int, meta, timeline, context, decision) do
    decl = int.declaration

    if decl && function_exported?(decl, :on_rebase, 4) do
      case decl.on_rebase(int, meta, timeline, context) do
        {:ok, updated} -> [{:ok, updated, decision}]
        {:split, children} -> Enum.map(children, &{:ok, &1, :split})
        {:conflict, reason} -> [{:conflict, {int, {:on_rebase_conflict, reason}}}]
      end
    else
      [{:ok, int, decision}]
    end
  end
end
