# Breakout Runtime Comparison

`breakout-runtime-comparison` is a standalone Nim benchmark suite for comparing
multiple runtime architectures on the same Breakout simulation.

It exists to answer a narrow question:

Which runtime model is faster when the gameplay, update order, input script, and
simulation rules are held constant?

This repo benchmarks four implementations of the same headless Breakout runtime:

- `pooled-data-oriented`
- `entity-component`
- `archetype-ecs`
- `signature-query-ecs`

The comparison is about runtime structure, not rendering, assets, or engine
integration.

## What This Benchmarks

Every implementation runs the same fixed simulation:

- same scene setup
- same scripted input
- same RNG seed policy
- same tick count
- same high-level update order
- same headless environment

Each runner reports both total runtime and per-system timing buckets, so the
suite can answer:

- which architecture wins overall
- where each architecture spends time

## Current Results

Latest local run with the default suite configuration:

- `--threads:on`
- `-d:release`
- `2000` ticks per repetition
- `5` repetitions

### Ranking

| Implementation | Avg total | Ns/tick |
| --- | ---: | ---: |
| `signature-query-ecs` | `12.209ms` | `6104.426` |
| `pooled-data-oriented` | `13.480ms` | `6739.781` |
| `entity-component` | `14.197ms` | `7098.571` |
| `archetype-ecs` | `18.484ms` | `9241.864` |

All four runs ended with the same normalized snapshot:

- `live=81`
- `total=81`
- `max=693`
- `paddle=1`
- `ball=4`
- `brick=0`
- `particle=0`
- `trail=76`

### Per-System Highlights

- `transform2d` is the largest bucket in every implementation
- `archetype-ecs` is currently hurt most by `transform2d`, `fade`, and `collide`
- `entity-component` still pays noticeably more in `cleanupDead` than the others
- `signature-query-ecs` is currently the fastest overall in this measurement set

These numbers are machine-dependent. Treat them as a benchmark snapshot for the
current code in this repository, not as a universal claim about these
architectures.

## Implementations

### `pooled-data-oriented`

Concrete actor records with typed component indices and explicit pool-backed
storage.

### `entity-component`

Entity-centric composition with optional attached components, closer to a
classic Unity-style entity/component model than to ECS.

### `archetype-ecs`

Archetype-based ECS with packed entity handles and columnar component storage.

### `signature-query-ecs`

Signature-mask ECS with slot tables and query-style iteration.

## Repo Layout

```text
breakout-runtime-comparison/
├── common.nim
├── shared/
│   ├── headless_raylib.nim
│   └── vmath.nim
├── implementations/
│   ├── pooled_data_oriented/runtime.nim
│   ├── entity_component/runtime.nim
│   ├── archetype_ecs/runtime.nim
│   └── signature_query_ecs/runtime.nim
├── run_data_oriented.nim
├── run_entity_component.nim
├── run_archetype_ecs.nim
├── run_legacy_signature_ecs.nim
└── run_all.sh
```

`runtime.nim` holds the runtime itself.

Each `run_*.nim` file owns the benchmark-specific glue for that implementation:

- benchmark initialization
- scripted input
- update dispatch
- result snapshotting

Shared support stays shared:

- `common.nim` contains the benchmark harness
- `shared/headless_raylib.nim` provides the no-op platform shim
- `shared/vmath.nim` provides the shared math layer

## Fairness Rules

This suite is only useful if the comparisons stay tight.

All implementations are benchmarked under the same rules:

- `--threads:on`
- `-d:release`
- identical repetition count
- identical tick count
- identical scripted input
- identical per-repetition RNG seed
- identical high-level system order
- headless execution only

The shared system order is:

`controlBall -> controlBrick -> controlPaddle -> shake -> fade -> cleanupDead -> move -> transform2d -> collide`

The suite does not try to erase architectural differences. It intentionally
preserves things like:

- different storage layouts
- different indirection models
- different cleanup mechanics
- different handle schemes

Those are part of what is being measured.

## Normalization

One runtime keeps an extra bookkeeping-only transform node internally.

To keep the reported counts comparable, the public benchmark output normalizes
those bookkeeping-only entities out of the final entity totals. That affects
reporting only. It does not change the runtime’s actual work.

## Requirements

- Nim with ORC/ARC support
- a shell environment that can run `run_all.sh`

This repo is self-contained. It does not depend on the parent Breakout game
sources when compiling or running the benchmark targets in this directory.

## Running

Build and run all implementations:

```bash
cd breakout-runtime-comparison
./run_all.sh
```

Build and run one implementation manually:

```bash
cd breakout-runtime-comparison
nim c --threads:on -d:release run_data_oriented.nim
./run_data_oriented
```

The harness rejects builds that do not use `--threads:on`.

## Output

Each runner prints:

- one line per repetition
- average total runtime
- nanoseconds per tick
- normalized entity counts
- per-system timing buckets

That makes it straightforward to compare both end-to-end cost and hot-path
distribution.

## Scope

This repository is a benchmark suite, not a game project and not a general ECS
framework.

The runtimes here are intentionally small, local benchmark targets built around
one simulation. Their job is to make architectural tradeoffs measurable, not to
serve as reusable production libraries.
