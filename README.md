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
- `small=10x10`, `medium=20x15`, `large=30x20`, `xlarge=40x25`, `xxlarge=50x30` brick grids
- `2000` ticks per repetition
- `5` repetitions

### Small

| Implementation | Avg total | Ns/tick |
| --- | ---: | ---: |
| `entity-component` | `11.104ms` | `5552.105` |
| `signature-query-ecs` | `11.861ms` | `5930.341` |
| `pooled-data-oriented` | `11.931ms` | `5965.526` |
| `archetype-ecs` | `15.730ms` | `7864.753` |

Final normalized snapshot for `small`:

- `live=96`
- `total=96`
- `max=728`
- `paddle=1`
- `ball=2`
- `brick=23`
- `particle=32`
- `trail=38`

### Medium

| Implementation | Avg total | Ns/tick |
| --- | ---: | ---: |
| `signature-query-ecs` | `45.708ms` | `22853.781` |
| `pooled-data-oriented` | `51.129ms` | `25564.675` |
| `entity-component` | `60.852ms` | `30425.890` |
| `archetype-ecs` | `79.949ms` | `39974.499` |

Final normalized snapshot for `medium`:

- `live=593`
- `total=593`
- `max=4482`
- `paddle=1`
- `ball=14`
- `brick=88`
- `particle=224`
- `trail=266`

### Large

| Implementation | Avg total | Ns/tick |
| --- | ---: | ---: |
| `signature-query-ecs` | `87.791ms` | `43895.694` |
| `pooled-data-oriented` | `116.442ms` | `58221.127` |
| `entity-component` | `131.665ms` | `65832.663` |
| `archetype-ecs` | `172.208ms` | `86104.161` |

Final normalized snapshot for `large`:

- `live=793`
- `total=793`
- `max=3331`
- `paddle=1`
- `ball=19`
- `brick=316`
- `particle=96`
- `trail=361`

### Xlarge

| Implementation | Avg total | Ns/tick |
| --- | ---: | ---: |
| `signature-query-ecs` | `157.384ms` | `78691.768` |
| `pooled-data-oriented` | `206.465ms` | `103232.560` |
| `entity-component` | `222.301ms` | `111150.621` |
| `archetype-ecs` | `310.580ms` | `155289.794` |

Final normalized snapshot for `xlarge`:

- `live=1238`
- `total=1238`
- `max=4202`
- `paddle=1`
- `ball=25`
- `brick=641`
- `particle=96`
- `trail=475`

### Xxlarge

| Implementation | Avg total | Ns/tick |
| --- | ---: | ---: |
| `signature-query-ecs` | `221.914ms` | `110957.062` |
| `pooled-data-oriented` | `319.176ms` | `159587.755` |
| `entity-component` | `335.075ms` | `167537.511` |
| `archetype-ecs` | `473.674ms` | `236836.877` |

Final normalized snapshot for `xxlarge`:

- `live=1758`
- `total=1758`
- `max=4702`
- `paddle=1`
- `ball=27`
- `brick=1121`
- `particle=96`
- `trail=513`

### Peak Resident Memory

Peak RSS is measured separately for each size by running one benchmark scale per
process:

| Implementation | Small | Medium | Large | Xlarge | Xxlarge |
| --- | ---: | ---: | ---: | ---: | ---: |
| `pooled-data-oriented` | `2700KB` | `4172KB` | `3416KB` | `4184KB` | `4212KB` |
| `entity-component` | `2568KB` | `4420KB` | `4036KB` | `4932KB` | `4988KB` |
| `signature-query-ecs` | `2796KB` | `3592KB` | `3468KB` | `3460KB` | `3596KB` |
| `archetype-ecs` | `3100KB` | `7152KB` | `5672KB` | `6180KB` | `6920KB` |

### Per-System Highlights

- `signature-query-ecs` stays in front from `medium` upward, while `entity-component` wins the current `small` run
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
