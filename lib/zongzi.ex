defmodule Zongzi do
  @moduledoc """
  SVS 领域的函数式组件与适配契约（plug without server）。

  ## 核内

  - **Score** — Note / Key / Tempo / TimeSig / Grid / RecordMap / Slicer
  - **Timeline** — 序列真相（写）+ `Timeline.Query`（读原语）
  - **Anchor** — 编辑后结构 rebase（`rebase_all` / Strategy / NoteTriplet / ScoredHost）
  - **Intervention** — 干预数据形状 + `Declaration` 语义契约（实现后置）
  - **Engine** — `render/1` 契约（不跑渲染）

  ## 库外（Host / 引擎 / 编辑器）

  - **Host**（如 Equinox）— 持 Note 表、组 `Anchor.Context`、调引擎、上浮 conflict
  - 曲线手绘 / 重叠合成等操作面 — 不进核；载荷心智见 `docs/zh/spec/MENTAL_MODELS.md`
  - Declaration 具体 channel、真模型推理 — 引擎适配层 / feasibility

  阅读顺序与分层细节：根目录 `README.md`、`docs/zh/spec/MENTAL_MODELS.md`。
  """
end
