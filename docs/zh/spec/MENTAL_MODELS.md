# 心智模型

本文钉死 zongzi 的分层与角色，避免把 Caller / 编辑器操作面 / 引擎实现误读成核内职责。

## 一句话

zongzi = **序列真相 + 结构 rebase + 契约壳**。  
渲染、用户画曲线、channel 真 resolve、分窗编排，都在库外或后置。

## 角色

| 角色 | 是谁 | 职责 |
|---|---|---|
| **核 (zongzi)** | 本库 | Timeline / Query / Anchor / Intervention 形状 / Engine·Declaration 契约 / Score 基础 |
| **Caller** | 库外编排者（任意） | 持 Note 表；edit 后组 Context；`rebase_all` → window → check/render；上浮 conflicts |
| **Engine** | `check/1` 必选；`render/1` 可选；只认 `[Segment]` | check / render 分层 artifact |
| **Declaration 实现** | 按 channel 的适配模块（引擎包或旁路库） | scope / snapshot / resolve；**不进 zongzi 核** |
| **编辑器操作面** | UI / 工具层 | 曲线手绘、重叠合成、清除；产出「控制点+边界」再挂成 Intervention |

## 两阶段存活

```plain
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
- Context 只允许 Note **静态**字段（key / lyric / tick 等）与 Caller 注入的窗映射；无投影。

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

| 通道形态 | payload 形状 | 锚 | conflict detect |
|---|---|---|---|
| 曲线参数（pitch 等） | 控制点 + 边界 + 原始值 | Seq 三元组 | snapshot vs 新投影 |
| timing | 边界 / 偏移 + 原始值 | 同上 | 同上 |
| G2P / 音素结果 | 挂在 note 或序列上 | note / 序列 | 另一类 payload（不假装曲线） |

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

## Timeline 与分窗（Windowing）

```text
Timeline = 「谁和谁是邻居」（指称，持久）
Segment  = 「这一锅 [start,end) + seq_ids」（批处理，瞬态；非历史持久短语实体）
```

完整决策：`docs/zh/spec/decisions/windowing-post-rebase.md` 与同目录其它决策。

### 契约

- **`Windowing.Strategy`**：单一回调 `window(Context) → {:ok, Context} | error`（Segments 在 `Context.current_segments`）；`Windowing.run_stages` 串行调用多个策略模块，与 plug 管道的唯一区别是不走 atom 分发。  
- **`Segment`**：`start_tick` / `end_tick` 左闭右开 + `seq_ids`。  
- **Context**：`timeline` + `notes_by_seq` + 可选 TimeSigMap / TempoMap / 存活 interventions。  
- intervention 在 Strategy 内按 **`channel` pattern match** 决定是否/如何撑窗。

### 管道顺序（硬）

```text
edit → Timeline → rebase_all → Windowing.run_stages(survived intervs context)
     → Engine.check →（决议）→ render
```

### 默认策略（RestSplit3Beats）

- 相邻 content 空档 **≥ 3 拍** 才切开。  
- **头 1 个空拍归前片，后 2 个空拍归后片**；更长空隙中间为死区。  
- 「拍」来自 TimeSig（无则显式假定）；切点拍号取前块端。

### Engine

- `check/1`（必选）— 轻量语义与参数检查。  
- `render/1`（可选）— 重渲染；artifact ≠ check 产出；请求均带 `segments`。  
- Intervention = 可改的上游生成结果（含可编辑 G2P）；Gender/Energy 等走 params 约束。

### `seq_to_window`（Anchor.Context）

rebase 时可选、**上一轮**启发式；本轮切片只来自 post-rebase 的 `Windowing.run_stages`。

### 现状

`Windowing.Strategy` / `RestSplit3Beats` / `WholeTrack` 已落地。


## 故意不进核 / 后置

- 曲线手绘、重叠合成、清除等**编辑器操作面**  
- Declaration 生产实现（等接 DiffSinger / NPSS 等模型）  
- 引擎错误的细粒度分类与 artifact schema（契约可后补）  
- Session / 多轨持久化 / 序列化编解码（仅约定 `next_seq` 反序列化语义）  
- 引擎 pad 表、phrase 缓存键、邻片失效策略 — Caller/引擎；zongzi 只提供 Strategy 与默认切开规则，不把产品缓存写进 Timeline

## 读代码顺序

1. `README.md`（边界 + 循环）  
2. `Timeline` + `Timeline.Query`  
3. `Anchor` / `NoteTriplet` / `ScoredHost` / `Context`  
4. `Intervention` + `Intervention.Declaration`  
5. `Engine`  
6. Score 基础按需（Note / TempoMap / Segment）  
7. `docs/zh/spec/decisions/`（设计决策，无编号）
