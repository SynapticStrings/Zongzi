# 控制点为真源，栅格化为缓存

**Status**: Accepted  
**In-tree**: `Curve.ControlPoint`、`Curve.Chunk`、`Curve.Adapter`

## 决策

- 曲线真源是**稀疏控制点**（及 Bezier 手柄等编辑语义），不是逐采样点序列。  
- `rasterize/2` 产出是可丢弃缓存（如 float32 binary）；可按需重建。  
- 高性能实现可用 NIF 替换 Adapter，契约不变。

## 边界

- **用户如何画出控制点**（手绘简化、工具）属编辑器操作面，不进 zongzi 核。  
- 挂到 intervention 时：控制点 + 边界 + **原始值**进 snapshot，见 [intervention-semantics.md](intervention-semantics.md)。

## 非目标

- 不在此规定 Douglas-Peucker 参数或 History 形状。  
- 不把 Cluster 重叠合成管线当作核职责。
