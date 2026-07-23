# 粽子

![img](https://img.shields.io/badge/code_translation-40%25-orange) ![img](https://img.shields.io/badge/中文文档进度-60%25-cyan)

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

等我写完。

## 安装

```elixir
def deps do
  [{:zongzi, github: "SynapticStrings/Zongzi", branch: "main"}]
end
```
