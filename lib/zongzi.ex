defmodule Zongzi do
  @moduledoc """
  Lightweight functional components and adaptation contracts in the SVS domain are designed to
  preserve user-defined parameters during score changed.

  ## Components

  - **Stage Data (`Zongzi.Score`)**
    * Includes pitch system, time system (stage, ticks, and physical time), and note structure.
  - **Note Timeline (`Zongzi.Timeline`)**
    * Maintains note sequences and provides query primitives for anchoring structures related to note sequences.
  - **Anchoring Strategies (`Zongzi.Anchor`)**
    * Rebase the structure after editing operations
  - **Intervention Data (`Zongzi.Intervention`)**
    * Modifiable shape of upstream generated results with semantic contract
  - **Windowing (`Zongzi.Windowing`)**
    * Post-rebase transient `Segment` which splited whole Timeline
  - **Engine Behavior (`Zongzi.Engine`)**
    * Accepts single or multiple... `Zongzi.Windowing.Segment` performs an inspection or rendering operation.

  ## Zongzi's Role in Your System

  - Need a caller can maintian Notes(with SeqID), components Context(for anchor's strategy and for windowing),
    integrate the whole antagonistic loop(and present conflict to user)
  - Operations from editor(e.g. draw a curve, undo, redo) stay outside
  - channel fields in declaration, model inference handle by engine or sideway adapter
  - **Caller** 是任意编排者：持 Note 表、组 Context、串联 rebase → window → check/render、上浮 conflict
  - 编辑器操作面（曲线手绘等）不进系统
  - Declaration 具体 channel、真模型推理 — 引擎或旁路适配层
  """
end
