# 粽子

[English](./README.md) | [简体中文](./README.zh-CN.md)

Zongzi 是：

1. 提供构建 SVS 编辑器的函数式组件与规范
2. 为 BEAM 生态的不同 SVS 处理组件提供统一适配

换言之，就是 SVS 领域的 plug without server。

## 核心架构

```mermaid
sequenceDiagram
    actor User
    participant Caller as Caller (orchestrator)
    participant Zongzi
    participant Engine as Engine (implementation agnostic)

    User->>Caller: Score / 编辑
    Caller->>Zongzi: Timeline 写操作
    Caller->>Engine: check / render（segments 常来自 WholeTrack）
    Engine-->>Caller: artifact₀
    Caller-->>User: artifact₀

    loop 对抗轮
        User->>Caller: 挂/撤 interventions 和/或 编辑 notes
        Caller->>Zongzi: Timeline 更新
        Caller->>Zongzi: Anchor.rebase_all(ints, tl, ctx)
        Zongzi-->>Caller: survived + 结构 conflicts
        Caller-->>User: 结构 conflicts（若有）

        Note over Caller: Windowing.run_stages → [Segment]
        Caller->>Engine: check(%{segments: ...})
        Engine-->>Caller: check_artifact ± semantic conflicts
        Caller->>Engine: render(%{segments: ...})（可选，重）
        Engine-->>Caller: render_artifact
        Caller-->>User: check/render 结果
    end

    opt 清理
        User->>Caller: 确认无 conflict
        Caller->>Zongzi: Timeline.gc
    end
```

## 文档

- `docs/zh/spec/MENTAL_MODELS.md` — 分层与角色
- `docs/zh/spec/decisions/` — 设计决策（无编号）
- `docs/zh/spec/GOLDEN_SCENARIOS.md` — 场景约束（骨架；用例随实现补）

## 安装

```elixir
def deps do
  [{:zongzi, github: "SynapticStrings/Zongzi", branch: "main"}]
end
```

# ROADMAP

## 编码

- [ ] Resolve 操作也来一个 resolve_all
    - 可以照着 zongzi_feasibility 实现
- [ ] Intervention 缺完整的生命周期
    - [x] 简单实现
    - [ ] 验证
- [ ] Scope 的单位（Tick frame seconds）
    - 变速怎么办？预期当然是要失效的（原始数据变了），所以 interv 的锚定不能够一定按照 Tick 来 => 写进新的 Golden Scenarios 里？
- [ ] Bug Fix
    - [ ] Timelinge.gc
- [ ] 内核的序列化（Note Key Timeline Intervention）
- 工程卫生类
    - 错误信息的分类 -> 每个模块自己负责吧，还用不上 Exception
    - Telemetry
    - Dialyzer
    - Hex package
- 收束分窗和引擎到底时什么？`notes_for_seq` ？ `notes_by_seq` ？ `notes` ？
    - 分清 Context 或 Engine
- 把 Anchor 的 context 升级下？把常用字段固化进去？

## 文档

- 确定 glossary
    - 多语言的词典
