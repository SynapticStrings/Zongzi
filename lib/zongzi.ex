defmodule Zongzi do
  @moduledoc """
  轻量级 SVS 领域的函数式组件与适配契约，旨在尽可能保留用户的调教参数而被设计。

  ## 组件适配范围

  - 谱表数据（`Zongzi.Score`）
      * 包括音高系统、时间系统（谱表、刻及物理时间）以及音符结构体
  - 音符时间线（`Zongzi.Timeline`）
      * 维护音符序列以及提供查询原语，以供和音符序列相关的结构锚定工作
  - 锚定策略（`Zongzi.Anchor`）
      * 执行编辑操作后的结构 rebase（`rebase_all` / Strategy / NoteTriplet / ScoredHost）
  - 干涉数据（`Zongzi.Intervention`）
      * 可改的上游生成结果之形状 + `Declaration` 语义契约
  - 分窗（`Zongzi.Windowing`）
      * post-rebase 瞬态 `Segment`（`Strategy.window/1`、默认 `RestSplit3Beats`）
  - 引擎行为（`Zongzi.Engine`）
      * 接收单个或多个 `Zongzi.Windowing.Segment`，执行检查或渲染操作

  ## 在您的系统中的角色

  - **Caller** 是任意编排者：持 Note 表、组 Context、串联 rebase → window → check/render、上浮 conflict
  - 编辑器操作面（曲线手绘等）不进系统
  - Declaration 具体 channel、真模型推理 — 引擎或旁路适配层
  """
end
