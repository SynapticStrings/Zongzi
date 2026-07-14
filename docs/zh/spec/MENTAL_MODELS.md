# 心智模型

本文钉死 zongzi 的分层与角色，避免把 Host / 编辑器操作面 / 引擎实现误读成核内职责。

## 一句话

zongzi = **序列真相 + 结构 rebase + 契约壳**。  
渲染、用户画曲线、channel 真 resolve、分窗编排，都在库外或后置。

## 角色

| 角色 | 是谁 | 职责 |
|---|---|---|
| **核 (zongzi)** | 本库 | Timeline / Query / Anchor / Intervention 形状 / Engine·Declaration 契约 / Score 基础 |
| **Host** | Equinox 等调用方 | 持 Note 表；edit 后组 `Anchor.Context`；调 `rebase_all`；组 `Engine.Request`；上浮 conflicts |
| **Engine** | 任意实现 `@callback render/1` 的适配器 | 投影 → 调 Declaration.resolve → 产出 artifact |
| **Declaration 实现** | 按 channel 的模块（可在 engine 包 / feasibility） | scope / snapshot / resolve 真逻辑；**接模型后再落生产实现** |
| **编辑器操作面** | UI / 工具层 | 曲线手绘、重叠合成、清除；产出「控制点+边界」再挂成 Intervention |

> **Host ≠ `Anchor.ScoredHost`**  
> Host = 编排者。  
> `ScoredHost` / `choose_host` 里的 host = 孤儿 intervention 的**新 focus seq**。

## 两阶段存活

```
编辑后（结构）                    渲染时（语义）
─────────────────                ─────────────────
Timeline 已更新                  Engine 生成投影
    ↓                                ↓
Anchor.Strategy.rebase           Declaration.resolve
preserve / rebase /              snapshot 一致 → apply delta
relocate / conflict              不一致 → conflict（或 channel 策略允许的 skip）
    ↓                                ↓
survived → 可进 Request          写入 artifact / 上浮 UI
```

规则：

- Strategy **不得**读投影、不得比 snapshot（那是 Declaration）。
- Declaration **不得**改 Timeline 邻接（那是 Strategy）。
- Context 只允许 Note **静态**字段（key / lyric / tick 等）与 Host 注入的窗映射；无投影。

## Intervention 数据心智

Intervention 描述：「在某处（anchor）、对某通道（channel）、做某种偏移（payload）」。  
不是渲染指令。

### 载荷三类（产品语义）

1. **曲线参数**（pitch 等）  
   - 数据 = 控制点 + 边界 + **原始值**（原始值进 `snapshot`，供 conflict detect）  
   - 用户如何画出这些点 → 编辑器；挂上之后的结构命运 → zongzi

2. **timing**  
   - 同构：边界 / 偏移 + 原始值 → snapshot

3. **挂在 note / note 序列上的改动**（如 G2P 结果）  
   - 锚在 note 或序列，payload 形状另一套；仍走结构 rebase + 语义 resolve 两阶段

### 字段分工

```elixir
%Intervention{
  id: _,
  channel: :pitch | :phoneme_timing | ...,
  anchor: {prev_seq | nil, current_seq, next_seq | nil},
  payload: term(),       # delta / 控制点等「意图」
  snapshot: term(),      # 挂载时原始值；resolve 比对用
  scope: term(),         # 可选缓存；真源仍是 Declaration.scope/2
  strategy: module() | nil  # Anchor.Strategy；默认 NoteTriplet
}
```

## Timeline 与分窗

两条轴目前**未在核内缝合**：

```
Timeline（seq_id 轴）              Slicer（tick 轴）
note_order / tombstones            gap_tolerance + slice_flag → Window
```

- Slicer 不持 SeqID，只按 tick 切。
- `Context.seq_to_window` 由 **Windowing**（未落地；属 Host 侧或未来薄层）在 rebase 前注入。
- `Declaration.scope/2` 声明保守 tick 上界；**scope 并集 / 按窗调引擎** 是 Host 编排，不是 Timeline 的职责。

## 故意不进核

- 曲线 Cluster 重叠合成、手绘/清除工具、Cadencii 风格编辑 UX  
- Declaration 生产实现（等接 DiffSinger / NPSS 等模型）  
- 引擎错误的细粒度分类与 artifact schema（契约可后补）  
- Session / 多轨持久化 / 序列化编解码（仅约定 `next_seq` 反序列化语义）

## 读代码顺序

1. `README.md`（边界 + 循环）  
2. `Timeline` + `Timeline.Query`  
3. `Anchor` / `NoteTriplet` / `ScoredHost` / `Context`  
4. `Intervention` + `Intervention.Declaration`  
5. `Engine`  
6. Score 基础按需（Note / TempoMap / Slicer）
