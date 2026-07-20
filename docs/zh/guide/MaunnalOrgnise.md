# 手动整理笔记

由 DeepSeek v4 + Hermes Agent 输出，后续会人工编辑修正更新。

最终目标是如 *The Reasoned Schemer* 一样的问答形式的文档。

## Phase 0 —— 是什么

> Q0. 这个库想解决什么问题？它给谁用的？

A. zongzi 是一个应用于 SVS 应用的内核/接口，其针对调教过程中音符变化后（拖拽等）调教参数静默失效的情况而被设计，旨在将失效行为暴露给用户让其定夺。

> Q1. 除了这个仓库还有什么？

A. 可以看 <https://github.com/GES233/zongzi_feasibiliity>

## Phase 1：数据层 —— 存了什么

涉及的模块：

- `Zongzi.Score.{Note, Key}` 不包括时间系统（`Zongzi.Score.{Tick, TimeSig, TimeSigMap, Tempo, TempoMap, Record, RecordMap}`）
- `Zongzi.Timeline`

> Q0. 方便介绍一些存了些什么吗？

A. 主要是音符以及音高的领域模型（`Zongzi.Score`），逻辑相对简单，并不需要在这里展开，除此之外还有维护邻近音符序列的 `Zongzi.Timeline` 。
对 Timeline 而言，初次阅读可能显得过于抽象，可以先跳到下一节再回看。

> Q1. Timeline 存的是什么？一个 note 有哪些字段？

A. 

先回答第一个问题，`Timeline` 的数据结构是将轨道上音符之间的邻接关系显式建模所设立，其需求是在注入拖拽音符到新位置的这类情况以及需要用到邻近音符之间的关系。

按照代码，如下：

```elixir
defmodule Zongzi.Timeline do
  ...
  @type t :: %__MODULE__{
          track_id: ID.t(),
          head: SeqID.t() | nil,
          tail: SeqID.t() | nil,
          nodes: %{SeqID.t() => {prev_seq_id :: SeqID.t() | nil, next_seq_id :: SeqID.t() | nil}},
          seq_map: %{SeqID.t() => ID.t(Note)},
          tombstones: MapSet.t(SeqID.t()),
          next_seq: pos_integer()
        }
  defstruct [
    :track_id,
    head: nil,
    tail: nil,
    nodes: %{},
    seq_map: %{},
    tombstones: MapSet.new(),
    next_seq: 1
  ]
end
```

下面简单介绍下字段：

* `:track_id` - 轨道的 ID ，用于下游应用的身份标识 *（其实可选）*
* `:head` 以及 `:tail` - 两端的音符的 SeqID
* `:nodes` - 记录音符邻接表的字段
* `:seq_map` - SeqID 到目前存活 NoteID （以及被合并的 NoteID）的映射
* `:tombstone` - 记录哪些被删除或被合并的 SeqID
    * 区分的方法就是看 `:seq_map` 中存不存在
* `:next_seq` - 用于维护新 SeqID 的计数器

而 note 主要用于记录音符本身。

```elixir
defmodule Zongzi.Score.Note do
  use Model,
    keys: [
      :id,              # 记录音符的 ID
      :start_tick,      # 记录音符的开始时刻
      :duration_tick,   # 记录音符的时长
      :key,             # 音高
      :lyric,           # 歌词
      seq_id: nil,      # SeqID
      annotation: nil,  # 面向用户/UI的标注
      metadata: %{}     # 元数据
    ],
    id_prefix: "Note_"
end
```

> Q2. seq_id 是什么，谁分配它？

A. 是一组独立于音符ID的序列ID，其本质上是正整数。
和音符最大的不同是当某个轨道的音符消失了（因为被删除或被合并），该ID依旧存在，且不允许被修改。
分配 SeqID 的模块是 `Zongzi.Timeline` 。

> Q3. Timeline 是双向链表还是别的数据结构？怎么遍历？

A.

以前是列表，现在由于性能要求是基于字典的邻接表以及表示两端的字段。

形如：

```elixir
%{
  head: seq_id | nil,
  tail: seq_id | nil,
  nodes: %{seq_id => {prev_seq_id | nil, next_seq_id | nil}}
}
```

我们假设某个 Timeline 完成了一系列操作（创建、创建、创建、创建、创建、在 SeqID 为 4 前的地方插入、在 SeqID 为 4 前的地方插入、删除 SeqID 为 6 的音符）。

<details>
<summary>Code</summary>

```
iex> {:ok, tl} = Timeline.new("a")
iex> tl |>
...> Timeline.insert_note(Zongzi.Score.Note.new(%{id: "Note_12345"}) |> elem(1)) |> elem(1) |>
...> Timeline.insert_note(Zongzi.Score.Note.new(%{id: "Note_114514"}) |> elem(1)) |> elem(1) |>
...> Timeline.insert_note(Zongzi.Score.Note.new(%{id: "Note_1919810"}) |> elem(1)) |> elem(1) |>
...> Timeline.insert_note(Zongzi.Score.Note.new(%{id: "Note_19110"}) |> elem(1))  |> elem(1) |>
...> Timeline.insert_note(Zongzi.Score.Note.new(%{id: "Note_19190"}) |> elem(1)) |> elem(1) |>
...> Timeline.insert_note_before(Zongzi.Score.Note.new(%{id: "Note_191900"}) |> elem(1), 4) |> elem(1) |>
...> Timeline.insert_note_before(Zongzi.Score.Note.new(%{id: "Note_191901"}) |> elem(1), 4) |> elem(1) |> Timeline.delete_note(6)
{:ok,
 %Zongzi.Timeline{
   track_id: "a",
   head: 1,
   tail: 5,
   nodes: %{
     1 => {nil, 2},
     2 => {1, 3},
     3 => {2, 6},
     4 => {7, 5},
     5 => {4, nil},
     6 => {3, 7},
     7 => {6, 4}
   },
   seq_map: %{
     1 => "Note_12345",
     2 => "Note_114514",
     3 => "Note_1919810",
     4 => "Note_19110",
     5 => "Note_19190",
     7 => "Note_191901"
   },
   tombstones: MapSet.new([6]),
   next_seq: 8
 }}
```
</details>

其结构应该为：

```elixir
%{
  head: 1,
  tail: 5,
  nodes: %{
    1 => {nil, 2},
    2 => {1, 3},
    3 => {2, 6},
    4 => {7, 5},
    5 => {4, nil},
    6 => {3, 7},
    7 => {6, 4}
  },
}
```

我们不需要在意删除的音符。

如果想要遍历所有的音符，最好先从 `:head` 开始（一般是 $1$ ），我们得知了 `Timeline` 从 $1$ 开始，之后从 `:nodes` 中取 $1$ 对应的邻接关系，得知没有前一项并且后一项是 $2$ ，因此我们知道 $1$ 的后面是 $2$ ，以此类推。

因为我设计了插入音符，整个列表并不按照自然数列递增（当然，就 SeqID 的生成而言，一定是单调递增的）。可以发现 $3$ 的后面是 $6$ ，$6$ 的后面是 $7$ ，$7$ 又回到 $4$ 了。

其结构为：

$$
1, 2, 3, 6, 7, 4, 5
$$

> Q4. 如果我改一个 note 的歌词，Timeline 本身会变吗？

A. 

并不会。

Timeline 只维护音符序列的关系（谁前谁后），修改音符歌词、时长等并不会修改 Timeline 。

同时也不难得出，如果存在同时刻音符，prev/next 退化为任意序（插入先后），失去了时间语义。
我们建议一个 Timeline 仅有一条音符序列，和弦/同时刻音符应由多条 Timeline 承载。

> **注意**
>
> Timeline 并不是轨道！

> Phase1Fin. 手写一张 A4 纸的图——一个三音符 Timeline，标出每个 note 的 seq_id、start_tick、duration、彼此的 prev/next 关系。

这个先算了吧。

## Phase 2：介入数据 —— 用户怎么盖掉模型生成

涉及的模块：

- `Zongzi.Intervention`

要回答的问题：

> Q0. 为什么叫 Intervention ？什么才算做 Interv ？

A.

在这里简单介绍下。

Intervention 的本意是「干预」，在这里，就是创作者认为模型生成的并不能够很好的表达其想法，因此对模型输出做出的修改。

我们可以发现，其存在如下的约束：

* 这个参数的原始输出是模型而不是人类
    * 音符的音高于歌词不是 Interv
    * 速度变化不是 Interv
* 这个参数是可以被人类理解以及修改的
    * Interv 需要工具来「介入」数据流
    * 无法根据手绘的方式来修改梅尔谱或波形（我没把话说死）
    * 音素时长应该在时间轴上被拖拽而不是曲线
* 修改的有效与否也跟着原始输出的变化而变化
    * **修改的调教是针对旧数据的，无法确保数据更新后调教使得否有效**

这也是开发 zongzi 的主要原因。

> Q1. Intervention 绑在哪个 note 上？（anchor 三元组是什么）

A. 

从以上的定义我们可以得到这里的 Intervention 和音符的耦合很大。

但是一个音符所对应的 Interv 真的和音符一一对应吗？

从 preutterance 以及某参数可能在音符末留下超出音符范围的尾巴两个场景开始。
当然也包括数据在跨语言 FFI 时所产生的估算偏差。
经过了一系列的思考，我们选择了一个有些原始的策略：

一个音符产生结构变化（Timeline 的变化）以及部分的语义变化，就会「污染」到临近的音符。

所以三元组就是此刻给定音符的前一个、它本身，以及下一个音符（其实是 SeqID 组成的，要是没有那就 nil 了）。可以看出三元组的策略其实是相当保守的，是一种「宁肯错杀，绝不放过」的思路。

> Q2. payload 里存什么？

A. `:payload` 里存着的，就是源于用户的 Interv 数据本身。

暂时并没有明确的构想，但是按照往常的构思，大抵可以分成两类：

* 离散的分类数据（类比于 textGrid）
* 某一维度内的连续数据（也适用于高维，但那种情况太极端了，也就是参数曲线）

> Q3. snapshot 是什么时候拍的？为什么要拍？

A. 这是对原始输出数据的一个快照或剪影。snapshot 对得上，interv 就有效。
虽然 interv 和音符不是一一对应的，但和 snapshot 是对应的。

（其实我本来的想法是写进 payload 里边，这个是 LLM Vibe 出来的，比我的原始想法要好，而且也可以处理注入拖拽导致数据漂移但保留调教的极端情景）

> Q4. scope 是什么作用的？

A. 简单说就是 interv 的范围，是否可能「污染」到前面或后面的音符。

> Q5. strategy 字段是干嘛的？

那就是针对这个 interv 执行锚定所要走的策略了。一般是实现了 `Zongzi.Anchor.Strategy` 行为的什么模块，后续需要读回调结果。

> Phase2Fin. 在上一步的 A4 图上，画一个 Intervention 挂到中间那个 note 上。标出 anchor = 哪三个 seq_id，snapshot = 什么内容，scope = 什么范围。

## Phase 3：编辑之后怎么同步（Anchor + Rebase）

涉及的模块：

- `Zongzi.Anchor`
- `Zongzi.Anchor.*`

*这是最难的一步，但也是整个库的灵魂。慢读。*

要回答的问题：

> Q1. rebase_all 输入什么输出什么？

---

*以下部分尚未跟进*

2. "结构层冲突"是指什么？（preserve / rebase / relocate / split / conflict 各是什么场景）
3. split note 时，挂在原 note 上的 Intervention 怎么处理？
4. delete note 时，Intervention 怎么可能 relocate？

产出：从 Phase 1 的三音符 Timeline 出发，画三个 case 的 before/after：
- split 中间音符 → 两个子 intervention
- delete 中间音符 → intervention relocate 到邻居
- 改歌词不拆音符 → intervention preserve

## Phase 4：引擎怎么消费（Windowing + Engine）

涉及的模块：

- `Zongzi.Windowing`
- `Zongzi.Engine`

要回答的问题：

1. Windowing 把 Timeline 切成什么给 Engine？为什么要切？
2. Engine behaviour 要求实现哪几个函数？输入输出各是什么形状？
3. preutterance / spill 是什么概念？spill 会导致什么冲突？

产出：画出 Phase 1 的 Timeline 被 Windowing 切成一个 Segment，标注 spill 的范围。然后用伪代码写一个 Engine.check(segments, interventions) 的调用——不要求代码正确，只要求你能写出每个参数"应该长什么样"。

## Phase 5：Declaration（语义层决议）

涉及的模块：

- `Zongzi.Intervention.Declaration`
- `ZongziFeasibility.Declaration.Pitch` (*in <https://github.com/GES233/zongzi_feasibiliity>*)

要回答的问题：

1. Declaration behaviour 要求实现哪几个回调？（scope / snapshot / resolve）
2. resolve 什么时候返回 {:ok, applied}，什么时候返回 {:conflict, :snapshot_stale}？
3. snapshot 的归一化做了什么？为什么需要归一化？
4. "snapshot 失配"在 BRAPA 口音切换场景下对应什么？（参见 <https://github.com/openutau/OpenUtau/pull/1841> ，此会话是和 Hermes 吃过这个 issue 的瓜后搞的，所以沾了点上下文）

产出：写一个具体的 BRAPA 例子：用户在音符上设了 Pitch Intervention，然后声库作者更新了 rendering engine。用 resolve 的输入输出描述这个 rebase 过程——不需要代码，用表格：

| 步骤          | snapshot       | 新投影         | 结果     |
|---------------|----------------|----------------|----------|
| 挂载时        | [42, 440.0, 1] | —              | —        |
| 更新后 rebase | [42, 440.0, 1] | [42, 445.0, 1] | conflict |

## Phase 6：Caller 怎么串起来（编排层）

涉及到模块：

- `ZongziFeasibility.Caller` (*in <https://github.com/GES233/zongzi_feasibiliity>*)

要回答的问题：

1. Caller 持有哪几样东西？
2. edit 函数的完整回路是什么？（写 op → apply → Anchor.rebase → refresh scope → window → report）
3. check_round 和 render_round 的区别？
4. tick↔frame 换算为什么在 Caller 做而不是在 Engine 做？

产出：画一张流程图，从"用户改歌词"开始，到最后拿到 report，中间 Caller 调了哪些 zongzi 模块，每一步的数据形状。

## Phase 7：Golden Scenarios（冒烟测试即文档）

文件：zongzi_feasibility/lib/zongzi_feasibility/scenarios/g_pre_01.ex、g_int_01.ex、g_int_02.ex

按这个顺序读，每个场景问：

1. setup 造了什么数据？
2. edits 做了哪个操作？
3. expect 断言了什么？如果断言失败，意味着什么保护被破坏了？

产出：用自己的话重写这三个 scenario 的标题和期望，不加代码，只讲故事。比如：

> G-PRE-01：两个音符紧挨着，B 改歌词后 preutterance 前移，因为没有 Intervention 挂在 A 尾部，一切自动通过。
>
> G-INT-02：用户在 B 音符挂了 pitch 编辑，然后改了 B 的音高。snapshot 失配 → conflict，不静默 apply。
