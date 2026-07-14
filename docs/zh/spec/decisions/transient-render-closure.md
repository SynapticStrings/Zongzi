# 渲染闭包是瞬态的；干预不绑窗身份

**Status**: Accepted  
**In-tree**: `Windowing.Segment`、`Intervention`、`Engine`

## 决策

1. **渲染用切片**（`Windowing.Segment`）瞬态、可丢、每次 post-rebase 可重算。  
2. **干预**锚在结构指称（默认 SeqID 三元组）或 channel 定义的锚上，**不**锚在 slice/window id。  
3. 缓存键（若 Caller 做 phrase cache）= 内容指纹（notes + tempo 切片 + 存活 interventions + 引擎版本 ± 邻片 context），**不是**窗实体 id。  
4. 引擎契约只吃 Request 数据（`segments: [Segment]`），**不** import Slicer/Windowing 模块。

## 与 Slicer

`Score.Slicer` 的 `Window` 与 `Windowing.Segment` 概念相近（都是投影），但：

- Slicer：仅 notes + gap/flag  
- Windowing：Timeline 序 + scopes + 默认三拍策略等  

产品默认以 Windowing 为准。

## 非目标

- 不规定 Caller 的 `data_channels` / LayerChunk 存储形态（产品层）。  
- 不规定 Compiler/Orchid 图如何接线。
