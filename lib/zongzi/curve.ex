defmodule Zongzi.Curve do
  @moduledoc """
  曲线相关工具的**残留入口**（非对抗循环必经路径）。

  ## 边界（2026-07）

  产品心智里，曲线参数 intervention 的数据是：

      控制点 + 边界 + 原始值（原始值进 Intervention.snapshot）

  **用户操作面**（手绘、直线/曲线工具、重叠 Cluster 合成、部分清除）
  计划留在编辑器 / Caller 侧，**不进 zongzi 核**。

  本命名空间下现有：

  - `Curve.ControlPoint` / `Curve.Chunk` — 轻量数据结构
  - `Curve.Adapter` + Bezier / CatmullRom — 按 tick 序列采样（rasterize）

  不承诺：Cluster 重叠合成管线、编辑 UX、与 Tempo 曲线的一体化。
  需要高性能栅格化时，下游用 NIF 替换 Adapter 即可。

  对抗循环请读 `Intervention` + `Anchor` + `Engine`，不要从本模块起步。
  """

  # 历史注释保留意图：工具型采样，不是编辑器产品面。
end
