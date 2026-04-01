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
- same benchmark size set
- same high-level update order
- same headless environment

Each benchmark now reports total runtime, peak resident memory, and per-system
timing buckets, so the
suite can answer:

- which architecture wins overall
- how much memory each architecture needs
- where each architecture spends time

## Current Results

Latest local run with the default suite configuration:

- `--threads:on`
- `-d:release`
- `small=10x10`, `medium=20x15`, `large=30x20` brick grids
- `2000` ticks per repetition
- `5` repetitions

### Small

| Implementation | Avg total | Ns/tick |
| --- | ---: | ---: |
| `signature-query-ecs` | `13.491ms` | `6745.378` |
| `pooled-data-oriented` | `13.496ms` | `6748.132` |
| `entity-component` | `14.593ms` | `7296.435` |
| `archetype-ecs` | `18.661ms` | `9330.346` |

Final normalized snapshot for `small`:

- `live=81`
- `total=81`
- `max=693`
- `paddle=1`
- `ball=4`
- `brick=0`
- `particle=0`
- `trail=76`

### Medium

| Implementation | Avg total | Ns/tick |
| --- | ---: | ---: |
| `signature-query-ecs` | `27.858ms` | `13929.085` |
| `pooled-data-oriented` | `31.502ms` | `15750.879` |
| `entity-component` | `31.667ms` | `15833.620` |
| `archetype-ecs` | `45.589ms` | `22794.280` |

Final normalized snapshot for `medium`:

- `live=349`
- `total=349`
- `max=1194`
- `paddle=1`
- `ball=9`
- `brick=104`
- `particle=64`
- `trail=171`

### Large

| Implementation | Avg total | Ns/tick |
| --- | ---: | ---: |
| `signature-query-ecs` | `54.202ms` | `27100.796` |
| `pooled-data-oriented` | `68.325ms` | `34162.402` |
| `entity-component` | `68.868ms` | `34433.751` |
| `archetype-ecs` | `93.422ms` | `46710.923` |

Final normalized snapshot for `large`:

- `live=518`
- `total=518`
- `max=1812`
- `paddle=1`
- `ball=10`
- `brick=317`
- `particle=0`
- `trail=190`

### Peak Resident Memory

Peak RSS is measured once per executable over the full `small` -> `medium` ->
`large` sweep:

| Implementation | Peak RSS |
| --- | ---: |
| `pooled-data-oriented` | `2772KB` |
| `entity-component` | `3600KB` |
| `signature-query-ecs` | `3360KB` |
| `archetype-ecs` | `6192KB` |

### Per-System Highlights

- `signature-query-ecs` stays in front at every tested size
- `pooled-data-oriented` and `entity-component` remain close, with the gap still
  smaller than the jump to `archetype-ecs`
- `transform2d` and `collide` dominate more of the total cost as the brick grid grows
- `entity-component` still pays noticeably more in `cleanupDead` than the others
- `archetype-ecs` is the most memory-hungry implementation in this run

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

`run_all.sh` also expects GNU `time` (`/usr/bin/time` on Linux or `gtime` on
macOS) so it can record peak resident memory per benchmark process.

## Output

Each runner prints:

- one block per benchmark size
- one line per repetition
- average total runtime
- nanoseconds per tick
- peak resident memory for the whole benchmark process
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
