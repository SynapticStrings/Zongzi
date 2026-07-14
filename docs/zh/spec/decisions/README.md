# 设计决策（无编号）

本目录是 zongzi **自洽**的决策记录，文件名即稳定引用。

| 文件 | 一句话 |
|---|---|
| [slicer-is-projection.md](slicer-is-projection.md) | Segment/切片输出是单向投影，非持久实体 |
| [transient-render-closure.md](transient-render-closure.md) | 渲染闭包瞬态；干预不绑在窗身份上 |
| [windowing-post-rebase.md](windowing-post-rebase.md) | 分窗在结构 rebase 之后；Strategy + 默认三拍 |
| [control-points-authoritative.md](control-points-authoritative.md) | 曲线控制点为真源，栅格化是缓存 |
| [key-behaviour-and-protocol.md](key-behaviour-and-protocol.md) | Key：构造用 behaviour，换算用 protocol |
| [declaration-projection-resolution.md](declaration-projection-resolution.md) | Declaration → 投影 → resolve 生命周期 |
| [intervention-semantics.md](intervention-semantics.md) | 什么是/不是 intervention；snapshot 语义 |
| [anchor-operate-orthogonality.md](anchor-operate-orthogonality.md) | 结构锚（编辑时）⊥ 语义 operate（check 时） |
| [boundary-ownership-open.md](boundary-ownership-open.md) | 邻片 pad/归属由 Host/引擎选型 |

Host 产品（编辑器 Session、缓存层、UI）的决策**不**放在本目录。
