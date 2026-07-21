# Zongzi

Zongzi is:

1. Providing functional components and specifications for building SVS(Singing Voice Synthesis) editors
2. Providing unified adaptation for different SVS processing components in the BEAM ecosystem

i.e. it's [plug](https://hex.pm/packages/plug) without server in SVS.

## Core Architecture

```mermaid
sequenceDiagram
    actor User
    participant Caller as Caller (orchestrator)
    participant Zongzi
    participant Engine as Engine (implementation agnostic)

    User->>Caller: Score / Edit
    Caller->>Zongzi: update Timeline(write op.)
    Caller->>Engine: check / render(segments derived from WholeTrack usually)
    Engine-->>Caller: artifact₀
    Caller-->>User: artifact₀

    loop antagonistic loop between user editing and constraints
        User->>Caller: mount/remove interventions and/or edit notes
        Caller->>Zongzi: update Timeline
        Caller->>Zongzi: Anchor.rebase_all(ints, tl, ctx)
        Zongzi-->>Caller: survived + structural conflicts
        Caller-->>User: maybe structural conflicts

        Note over Caller: Windowing.run_stages → [Segment]
        Caller->>Engine: check(%{segments: ...})
        Engine-->>Caller: check_artifact ± semantic conflicts
        Caller->>Engine: render(%{segments: ...}) (heavy, optional)
        Engine-->>Caller: render_artifact
        Caller-->>User: check/render result
    end

    opt cleanup
        User->>Caller: ensure there's no conflict
        Caller->>Zongzi: Timeline.gc
    end
```

## Documents

TODO

## Install

```elixir
def deps do
  [{:zongzi, github: "SynapticStrings/Zongzi", branch: "main"}]
end
```
