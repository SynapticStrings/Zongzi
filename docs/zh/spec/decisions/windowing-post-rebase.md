# Windowing：结构 rebase 之后的瞬态闭包

**Status**: Accepted  
**In-tree**: `Windowing.*`、`Engine`  
**Related**: [slicer-is-projection.md](slicer-is-projection.md), [transient-render-closure.md](transient-render-closure.md), [anchor-operate-orthogonality.md](anchor-operate-orthogonality.md)

## 一句话

```text
Timeline  = 「谁和谁是邻居」（持久指称）
Slice     = 「这一锅 [start,end) + seq_ids」（瞬态批处理）
```

## 契约

```elixir
@callback Windowing.Strategy.window(Context.t()) ::
  {:ok, [Slice.t()]} | {:error, term()}

# Slice: 半开 [start_tick, end_tick) + seq_ids
# Context: timeline + notes_by_seq + 可选 time_sig/tempo/interventions/opts
```

- **不是** atom plug 管道；组合逻辑放在 Strategy 模块内部。  
- intervention 按 `channel` pattern match 决定是否撑窗。  
- 默认策略 `RestSplit3Beats`：空 **≥ 3 拍** 才切开；**1 拍归前、2 拍归后**；更长空隙中间死区。  
- `WholeTrack`：单一切片（无 phrase cache 引擎友好）。  
- `Score.Slicer` 默认 64 tick **不得**冒充 phrase 边界。

## 管道（硬）

```text
edit → Timeline → Anchor.rebase_all
  → Strategy.window(survived interventions)
  → Engine.check_* →（可选）render_*
  → 可选 Timeline.gc
```

`Anchor.Context.seq_to_window` 在 rebase 时若存在，仅为**上一轮**启发式。

## Engine（与分窗正交）

```elixir
@callback check_whole/1            # 必选
@callback check_partial/1          # optional
@callback render_whole/1           # optional
@callback render_partial/1         # optional
```

check 轻（语义 resolve、参数约束）；render 重（终态产物）。artifact 分层。

## 边界归属

pad/scope 打穿邻片 → Host/引擎选型，见 [boundary-ownership-open.md](boundary-ownership-open.md)。

## 非目标

协同编辑；frame 增量；持久 phrase 实体；冻结全部 channel 的 scope 数值。
