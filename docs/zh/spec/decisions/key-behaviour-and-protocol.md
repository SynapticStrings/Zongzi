# Key：Behaviour 构造 + Protocol 换算

**Status**: Accepted  
**In-tree**: `Score.Key`、`Score.Key.TwelveET`

## 决策

- **构造**（`new` / 从 MIDI 等）：调用方选定律制模块 → **Behaviour** 级分派。  
- **换算**（`to_midi` / `to_frequency` 等）：已有值 → **Protocol** 值分派。  

理由：构造时还没有统一 struct 实例；换算时 Track/Note 只持 `Key.t()` 不应关心律制模块名。

## 非目标

- 五线谱 `from_score`/`to_score` 可保留签名后置。  
- 不在此引入第三种律制，除非有具体消费者。
