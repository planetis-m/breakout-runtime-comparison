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
| `entity-component` | `11.188ms` | `5593.880` |
| `signature-query-ecs` | `11.317ms` | `5658.341` |
| `pooled-data-oriented` | `12.852ms` | `6425.923` |
| `archetype-ecs` | `17.035ms` | `8517.273` |

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
| `pooled-data-oriented` | `48.049ms` | `24024.390` |
| `signature-query-ecs` | `50.506ms` | `25253.042` |
| `entity-component` | `68.688ms` | `34344.204` |
| `archetype-ecs` | `81.973ms` | `40986.389` |

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
| `signature-query-ecs` | `88.549ms` | `44274.452` |
| `pooled-data-oriented` | `115.284ms` | `57641.757` |
| `entity-component` | `134.143ms` | `67071.656` |
| `archetype-ecs` | `164.855ms` | `82427.591` |

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
| `signature-query-ecs` | `160.623ms` | `80311.690` |
| `pooled-data-oriented` | `197.744ms` | `98872.197` |
| `entity-component` | `226.661ms` | `113330.709` |
| `archetype-ecs` | `313.931ms` | `156965.516` |

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
| `signature-query-ecs` | `245.269ms` | `122634.522` |
| `pooled-data-oriented` | `287.037ms` | `143518.454` |
| `entity-component` | `354.660ms` | `177329.889` |
| `archetype-ecs` | `475.554ms` | `237776.818` |

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
| `pooled-data-oriented` | `2652KB` | `4084KB` | `3596KB` | `4184KB` | `4184KB` |
| `entity-component` | `2692KB` | `4356KB` | `3976KB` | `4868KB` | `4868KB` |
| `signature-query-ecs` | `2640KB` | `3396KB` | `3468KB` | `3344KB` | `3716KB` |
| `archetype-ecs` | `3236KB` | `7176KB` | `5612KB` | `6060KB` | `6920KB` |

### Per-System Highlights

- `entity-component` wins the current `small` run, while `signature-query-ecs` stays fastest from `large` upward
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
