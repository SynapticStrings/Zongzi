defmodule Zongzi do
  @moduledoc """
  SVS 领域的函数式组件与适配契约（plug without server）。

  ## 核内

  - **Score** — Note / Key / Tempo / TimeSig / Grid / RecordMap / Slicer
  - **Timeline** — 序列真相（写）+ `Timeline.Query`（读原语）
  - **Anchor** — 编辑后结构 rebase（`rebase_all` / Strategy / NoteTriplet / ScoredHost）
  - **Windowing** — post-rebase 瞬态切片（`Strategy.window/1`、默认 `RestSplit3Beats`）
  - **Intervention** — 可改的上游生成结果之形状 + `Declaration` 语义契约
  - **Engine** — `check_*` / 可选 `render_*`（不跑引擎）

  ## 库外（Host / 引擎 / 编辑器）

  - **Host** — 任意编排者：持 Note 表、组 Context、串联 rebase → window → check/render、上浮 conflict
  - 编辑器操作面（曲线手绘等）— 不进核
  - Declaration 具体 channel、真模型推理 — 引擎或旁路适配层

  分层细节：`README.md`、`docs/zh/spec/MENTAL_MODELS.md`、`docs/zh/spec/decisions/`。
  """
end
