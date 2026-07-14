# 邻片边界归属（开放）

**Status**: Open（故意不在 zongzi 选型）  
**Related**: [windowing-post-rebase.md](windowing-post-rebase.md)

## 问题

片 B 的 pad_left / scope 打进片 A 的 tail 时，正确性与缓存如何处理？

## 常见选项（Caller/引擎）

1. 粘 A+B  
2. 邻片 context 进入 hash（改 B 左缘会使 A 失效）  
3. 重叠区双渲 + crossfade  

## zongzi 约束

- 默认深休止切开（≥3 拍）应**降低**打穿频率。  
- 不得用持久 slice id 或改写 Timeline 表示归属。  
- 不在核内实现 Stratum/缓存层。

## 非目标

- 不在本决策冻结产品默认选项。
