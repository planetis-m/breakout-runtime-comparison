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
- same deterministic event-derived randomness
- same tick count
- same benchmark size set
- same high-level update order
- same headless environment

Each benchmark now reports total runtime, per-size peak resident memory, and
per-system timing buckets, so the
suite can answer:

- which architecture wins overall
- how much memory each architecture needs
- where each architecture spends time

## Current Results

Latest local run with the default suite configuration:

- `--threads:on`
- `-d:release`
- `small=20x15`, `medium=30x20`, `large=40x30`, `xlarge=50x40`, `xxlarge=60x50` brick grids
- `2000` ticks per repetition
- `5` repetitions

### Small

| Implementation | Avg total | Ns/tick |
| --- | ---: | ---: |
| `pooled-data-oriented` | `51.225ms` | `25612.414` |
| `signature-query-ecs` | `51.453ms` | `25726.391` |
| `entity-component` | `64.940ms` | `32470.090` |
| `archetype-ecs` | `78.701ms` | `39350.586` |

Final normalized snapshot for `small`:

- `live=593`
- `total=593`
- `max=4482`
- `paddle=1`
- `ball=14`
- `brick=88`
- `particle=224`
- `trail=266`

### Medium

| Implementation | Avg total | Ns/tick |
| --- | ---: | ---: |
| `signature-query-ecs` | `87.540ms` | `43770.102` |
| `pooled-data-oriented` | `111.859ms` | `55929.694` |
| `entity-component` | `134.969ms` | `67484.423` |
| `archetype-ecs` | `183.646ms` | `91822.955` |

Final normalized snapshot for `medium`:

- `live=793`
- `total=793`
- `max=3331`
- `paddle=1`
- `ball=19`
- `brick=316`
- `particle=96`
- `trail=361`

### Large

| Implementation | Avg total | Ns/tick |
| --- | ---: | ---: |
| `signature-query-ecs` | `198.611ms` | `99305.367` |
| `pooled-data-oriented` | `255.016ms` | `127508.247` |
| `entity-component` | `304.912ms` | `152456.059` |
| `archetype-ecs` | `396.528ms` | `198263.831` |

Final normalized snapshot for `large`:

- `live=1458`
- `total=1458`
- `max=4402`
- `paddle=1`
- `ball=27`
- `brick=821`
- `particle=96`
- `trail=513`

### Xlarge

| Implementation | Avg total | Ns/tick |
| --- | ---: | ---: |
| `signature-query-ecs` | `299.262ms` | `149631.006` |
| `pooled-data-oriented` | `401.334ms` | `200666.891` |
| `entity-component` | `414.899ms` | `207449.727` |
| `archetype-ecs` | `701.989ms` | `350994.705` |

Final normalized snapshot for `xlarge`:

- `live=2258`
- `total=2258`
- `max=5202`
- `paddle=1`
- `ball=25`
- `brick=1621`
- `particle=96`
- `trail=513`

### Xxlarge

| Implementation | Avg total | Ns/tick |
| --- | ---: | ---: |
| `signature-query-ecs` | `427.762ms` | `213881.131` |
| `pooled-data-oriented` | `571.237ms` | `285618.291` |
| `entity-component` | `626.676ms` | `313338.203` |
| `archetype-ecs` | `973.466ms` | `486732.909` |

Final normalized snapshot for `xxlarge`:

- `live=3258`
- `total=3258`
- `max=6202`
- `paddle=1`
- `ball=27`
- `brick=2621`
- `particle=96`
- `trail=513`

### Peak Resident Memory

Peak RSS is measured separately for each size by running one benchmark scale per
process:

| Implementation | Small | Medium | Large | Xlarge | Xxlarge |
| --- | ---: | ---: | ---: | ---: | ---: |
| `pooled-data-oriented` | `4044KB` | `3572KB` | `4300KB` | `4056KB` | `4636KB` |
| `entity-component` | `4536KB` | `4088KB` | `4864KB` | `6200KB` | `6328KB` |
| `signature-query-ecs` | `4364KB` | `4076KB` | `4368KB` | `4752KB` | `5508KB` |
| `archetype-ecs` | `7148KB` | `5408KB` | `6444KB` | `7072KB` | `8224KB` |

### Per-System Highlights

- `pooled-data-oriented` narrowly wins the current `small` run, but `signature-query-ecs` is fastest from `medium` upward
- `pooled-data-oriented` and `entity-component` remain closer to each other than to `archetype-ecs` at larger sizes
- `transform2d` and `collide` dominate more of the total cost as the brick grid grows
- `entity-component` still pays noticeably more in `cleanupDead` than the others
- `archetype-ecs` is the most memory-hungry implementation in this run
- all five sizes now end with matching normalized snapshots across all four implementations

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
├── bench_sizes.nim
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
- identical benchmark size set
- identical repetition count
- identical tick count
- identical scripted input
- identical deterministic event-derived randomness
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

`run_all.sh` also expects GNU `time` (`/usr/bin/time` on Linux or `gtime` on
macOS) so it can record peak resident memory per benchmark process.

## Output

Each runner prints:

- one block per benchmark size
- one line per repetition
- average total runtime
- nanoseconds per tick
- peak resident memory for that benchmark size
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
