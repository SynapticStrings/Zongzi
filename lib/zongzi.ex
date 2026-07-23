defmodule Zongzi do
  @moduledoc """
  Lightweight, engine-agnostic components for SVS (Singing Voice Synthesis) editors.
  Preserves user edits across upstream regeneration cycles.

  ## Components

  - Stage Data (`Zongzi.Score`)
    - Pitch system, time system (ticks and physical time), note structure.
  - Note Timeline (`Zongzi.Timeline`)
    - Authoritative note sequence (doubly-linked list + SeqID + tombstones).
    Provides query primitives for anchoring.
  - Anchoring (`Zongzi.Anchor`)
    - Rebase anchor structures after edit batches.
  - Intervention (`Zongzi.Intervention`)
    - Mutable overlay on upstream results, with a semantic contract.
  - Windowing (`Zongzi.Windowing`)
    - Splits the Timeline into transient `Zongzi.Windowing.Segment`s after rebase.
  - Engine (`Zongzi.Engine`)
    - Behaviour contract: accepts one or more `Zongzi.Windowing.Segment`s for check or render.

  ## Role in Your System

  Zongzi is a library, not a framework. The Caller (your application) is the orchestrator:

  - Owns the Note table (keyed by SeqID) and assembles the rebase Context.
  - Wires the pipeline: update Timeline → rebase → window → check/render.
  - Surfaces conflicts to the user for resolution.
  - Editor interactions (curve drawing, undo/redo) stay outside Zongzi.
  - Channel-specific declaration fields and model inference are handled by the Engine implementation or an out-of-band adapter.
  """
end
