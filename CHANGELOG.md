# Changelog

## 0.3.0 — 2026/07/23

0.3.0 focused on Timeline internals, Intervention validation,
Engine render contract tightening, and extensive documentation/translation work.

### Breaking Changes

- **`Engine.render/1` now accepts `checked_request`** (not bare `request`):
  `%{request: request(), artifact: check_artifact(), fingerprint: term()}`.
  Implementations must verify the fingerprint matches current state before
  rendering. Return type extended with `{:async, ref}` for async pipelines.
  (`4b97a2b`)
- **`NoteTriplet.Options.orphan_direction` default changed from `:next` to `:never`**:
  delete tombstones now return `{:conflict, :adjacency_lost}` without attempting
  relocation unless explicitly opted in. `ScoredHost.Options` follows the same
  convention. (`990c5c8`)
- **`Intervention` struct: removed `:scope` field**: scope is now computed
  on-the-fly via `Declaration.scope/2` (pure function). Cached scope was stale
  after tempo/drag edits. (`41184c7`)
- **Delete tombstone simplified**: removed SeqID comparison logic from
  `Timeline.delete`; tombstone placement no longer depends on seq ordering.
  (`ec35864`)

### Added

- `Timeline` implements `Enumerable` protocol — timelines are now directly
  iterable with `Enum.*` functions. (`c1b42a7`)
- `Zongzi.Timeline.Link`: extracted linked-list mechanics (insert, delete,
  neighborhood traversal) into a dedicated internal module. (`2888801`)
- `Intervention.mount/5`: new lifecycle function that validates anchor seq_ids
  against the timeline, rejecting interventions referencing inactive positions.
  (`f2bb1ba`)
- `Engine.supports_render?/1`: convenience guard for checking render callback
  availability. (`4b97a2b`)
- `Intervention.validate/1`: structural validation for strategy and declaration
  fields. (`f2bb1ba`)
- MIT License added. (`bd30cd0`)

### Fixed

- `Timeline.gc/2` now correctly removes orphan items from `seq_map` that were
  previously leaked during undo operations. (`8dbc735`)
- `Engine.render/1` signature mismatch: callback accepted bare `request` but
  the dispatch contract expected `checked_request`. (`4b97a2b`)

### Refactored

- `Timeline`: reduced code lines; extracted linked-list mechanics to
  `Timeline.Link`; gc enhanced for undo scenarios. (`e3dcc3b`, `2888801`,
  `9a69f69`)
- `Anchor` relocation logic refined for missing anchor edge cases;
  `orphan_direction: :never` now short-circuits before attempting relocate.
  (`10069d5`)
- `Intervention` resolution updated with proper typespecs for `resolve_all/2`.
  (`82d6423`, `bf5a734`)
- Anchor option handling improved with cleaner defaults propagation.
  (`092dee8`)

### Documentation

- Translated timeline, score, note module comments to English. (`0a00f7a`,
  `f752d8c`, `5666d47`)
- Added/updated glossary (`docs/zh/spec/GLOSSARY.md`). (`ce2d586`, `f752d8c`,
  `58c0195`)
- Added golden scenarios (`docs/zh/spec/GOLDEN_SCENARIOS.md`) and mental models
  (`docs/zh/spec/MENTAL_MODELS.md`). (`ce2d586`)
- Added Chinese guide: TheLittleZongzi-zh with Mermaid diagrams.
  (`ea25ccf`, `d610efb`, `0b927b4`)
- Added CallerDesigning-zh design guide. (`055aa58`)
- Added decision records for intervention semantics, windowing post-rebase,
  declaration projection, anchor orthogonality, and more
  (`docs/zh/spec/decisions/`). (`ce2d586`)
- Migrated document snippets from moduledocs into guides. (`e11d645`)
- Refined architecture docs; added language links in README. (`3e897f8`,
  `5666d47`)

## 0.2.0 — 2026/07/21

Contract revisions driven by Caller integration feedback (zongzi_feasibility),
plus Strategy Options decoupling.

### Breaking Changes

- **`Declaration.on_rebase/3` → `on_rebase/4`**: added 4th argument `context` (the
  `Anchor.Context` injected by the Caller into `rebase_all`, carrying `notes_by_seq`).
  Declarations can now maintain payloads at tick granularity without the Caller
  pre-injecting split metadata. Strategy meta on relocate (from/to/method/scoring)
  is merged into the meta passed through, no longer discarded.
- **`Timeline.gc/2` returns `{:ok, t()}`** (was bare struct), consistent with the rest
  of the library's write operations. Also fixed a bug where gc was reading
  `int.declaration.referenced_seqs/1` — the correct source is
  `int.strategy || NoteTriplet` (declaration has no such callback in its contract).
- **`Strategy.rebase/3` → `rebase/4`**: added 4th argument `opts :: term()` (a
  strategy-specific struct or map), unpacked from the `Intervention.strategy` tuple
  and passed through by the dispatch layer. Custom strategies must adapt.
- **`Intervention.strategy` type change**: `module() | nil` → `{module(), options :: term()} | nil`.
  When `nil`, dispatch falls back to `{default_strategy, %{}}`; each strategy
  normalizes the opts map into its own struct defaults.
- **`Anchor.Context` no longer carries strategy-level keys**: removed `:match_threshold`,
  `:allow_follow_merge`, `:orphan_direction`, and `:allow_relocate` (the last two
  merged into `Options.orphan_direction: :never`). Shared keys `notes_by_seq`,
  `seq_to_window`, `focus_note`, `channel`, and `extra` remain.
- **`allow_relocate` merged into `orphan_direction: :never`**: `NoteTriplet.Options.orphan_direction`
  accepts `:prev | :next | :never` (default `:next`). When `:never`, a delete
  tombstone directly returns `{:conflict, :adjacency_lost}` without attempting
  relocation. `ScoredHost.Options` follows the same convention.

### Added

- `Anchor.rebase_all/4` now returns a `:decisions` key:
  `%{intervention_id => :preserve | :rebase | :relocate | :split | :conflict}`,
  allowing the Caller to consume structural decisions (metrics/logging) without
  re-deriving them from anchor diffs.
- `Timeline.split_note/5`: added optional `attrs` parameter, forwarded to
  `Note.split/4` (e.g. to give the second half a different lyric).
- `Zongzi.Anchor.NoteTriplet.Options`: defstruct with `match_threshold` (default 2),
  `allow_follow_merge` (default false), `orphan_direction` (default `:next`).
- `Zongzi.Anchor.ScoredHost.Options`: same fields as NoteTriplet + `scan_limit`
  (default 4).
- Both strategies include `normalize_opts/1`, accepting `%Options{}`, a plain map,
  or anything else — always filling in struct defaults. The dispatch layer passes
  `%{}` for nil-strategy interventions; strategies tolerate this gracefully.
- Bugfix: `do_relocate` was mistakenly receiving `opts.allow_follow_merge` (a boolean)
  instead of `opts.orphan_direction`, which would cause a `FunctionClauseError` when
  the value hit the `case` matching `:prev | :next`.

### Refactored

- `Timeline.gc/2`: dispatch layer unpacks the `{module, opts}` tuple before calling
  `referenced_seqs`.
- `Anchor.rebase_all/4`: dispatch unpacks `{strategy_mod, strategy_opts}` and forwards opts.

### Documentation

- `RestSplit3Beats`: added caveat that intervention scope is a conservative upper
  bound that inflates windows; excess slack can fuse gaps that should have been
  separate windows.
- Clarified that `on_rebase`-split child interventions do not go through
  `strategy.rebase` again; anchor correctness is the declaration's responsibility.

## 0.1.0 — 2026/07/14

Initial release. Zongzi is a functional component library for the SVS domain,
providing Score primitives, Timeline write paths, Anchor structural rebase,
Intervention data contracts, and Engine/Windowing behaviour definitions.

### Score Primitives

- Note / Tempo / TimeSig / Grid data structures and merge logic
- Key behaviour (with TwelveET implementation) and Note merge semantics
- Configurable TPQN (ticks per quarter note)
- RecordMap / TempoMap / TimeSigMap
- `Helpers.normalize_attrs/1`

### Timeline

- SeqID: permanent position identifier, generated from Timeline's own counter
- `note_order`: ordered linked list + tombstones (merge / delete)
- Write operations: insert / delete / split / merge / drag
- `Timeline.Query` read primitives: `status/2`, `scan/4`, `neighborhood/3`,
  `scrub_triplet/2`, `hops/3`
- `gc/2`: reclaim unreferenced tombstones

### Anchor & Intervention

- `Intervention` struct: anchor, payload, snapshot, strategy, declaration,
  on_rebase callback
- `Anchor.Context`: carries orphan_direction, strategy parameters, etc.
- `Anchor.rebase_all/4`: post-edit batch structural rebase
- `Anchor.NoteTriplet` strategy: 3-of-3 exact → preserve; 2-of-3 → rebase;
  0–1/3 → conflict
- `Anchor.ScoredHost`: scored relocation strategy for deleted/orphan notes
  (same key / same window)
- `Intervention.Declaration` behaviour: `scope/2`, `snapshot/2`, `resolve/2`,
  `on_rebase/3`

### Engine & Windowing

- `Engine` behaviour: `check/1` + optional `render/1`, consumes only `[Segment]`
- `Windowing.Strategy` behaviour: `window/1` → `[Segment]`
- `Windowing.WholeTrack`: whole-track strategy
- `Windowing.RestSplit3Beats`: 3-beat split windowing strategy
- `Windowing.Context` / `Windowing.Segment`

### Curve

- Adapter behaviour (replacing the original Protocol)
- Bezier / CatmullRom adapters
- Chunk / ControlPoint structs

### Refactoring & Documentation

- Unified module naming: Slice → Segment, Host → Caller
- Timeline-related modules moved under Score namespace
- SeqID generation moved from Note into Timeline
- `Model.new/1` requires explicit id (pure-function principle)
- Complete mental-model documentation, design decision records, and golden-path
  scenarios (`docs/zh/spec/`)
