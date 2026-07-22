defmodule Zongzi do
  @moduledoc """
  Lightweight functional components and adaptation contracts in the SVS domain are designed to
  preserve as many user-defined parameters as possible.

  ## Components

  - **Stage Data (`Zongzi.Score`)**
    * Includes pitch system, time system (stage, ticks, and physical time), and note structure.
  - **Note Timeline (`Zongzi.Timeline`)**
    * Maintains note sequences and provides query primitives for anchoring structures related to note sequences.
  - **Anchoring Strategies (`Zongzi.Anchor`)**
    * Rebase the structure after editing operations (`rebase_all` / Strategy / NoteTriplet / ScoredHost)
  - **Intervention Data (`Zongzi.Intervention`)**
    * Modifiable shape of upstream generated results + `Declaration` semantic contract
  - **Windowing (`Zongzi.Windowing`)**
    * Post-rebase transient `Segment` (`Strategy.window/1`, default `RestSplit3Beats`)
  - **Engine Behavior (`Zongzi.Engine`)**
    * Accepts single or multiple... `Zongzi.Windowing.Segment` performs an inspection or rendering operation.

  ## 在您的系统中的角色

  - **Caller** 是任意编排者：持 Note 表、组 Context、串联 rebase → window → check/render、上浮 conflict
  - 编辑器操作面（曲线手绘等）不进系统
  - Declaration 具体 channel、真模型推理 — 引擎或旁路适配层
  """
end
