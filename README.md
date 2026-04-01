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
| `signature-query-ecs` | `11.362ms` | `5680.767` |
| `entity-component` | `12.330ms` | `6164.901` |
| `pooled-data-oriented` | `12.952ms` | `6475.760` |
| `archetype-ecs` | `17.718ms` | `8859.060` |

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
| `signature-query-ecs` | `30.709ms` | `15354.313` |
| `pooled-data-oriented` | `32.743ms` | `16371.713` |
| `entity-component` | `33.179ms` | `16589.544` |
| `archetype-ecs` | `47.397ms` | `23698.413` |

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
| `signature-query-ecs` | `55.963ms` | `27981.581` |
| `pooled-data-oriented` | `60.944ms` | `30472.087` |
| `entity-component` | `67.857ms` | `33928.431` |
| `archetype-ecs` | `95.768ms` | `47884.168` |

Final normalized snapshot for `large`:

- `live=518`
- `total=518`
- `max=1812`
- `paddle=1`
- `ball=10`
- `brick=317`
- `particle=0`
- `trail=190`

### Xlarge

| Implementation | Avg total | Ns/tick |
| --- | ---: | ---: |
| `signature-query-ecs` | `100.872ms` | `50435.957` |
| `pooled-data-oriented` | `118.228ms` | `59114.145` |
| `entity-component` | `129.587ms` | `64793.734` |
| `archetype-ecs` | `188.161ms` | `94080.258` |

Final normalized snapshot for `xlarge` in `pooled-data-oriented`,
`entity-component`, and `archetype-ecs`:

- `live=939`
- `total=939`
- `max=2348`
- `paddle=1`
- `ball=13`
- `brick=646`
- `particle=32`
- `trail=247`

`signature-query-ecs` diverged at `xlarge` and ended with:

- `live=890`
- `total=890`
- `max=2348`
- `paddle=1`
- `ball=12`
- `brick=649`
- `particle=0`
- `trail=228`

### Xxlarge

| Implementation | Avg total | Ns/tick |
| --- | ---: | ---: |
| `signature-query-ecs` | `148.699ms` | `74349.383` |
| `pooled-data-oriented` | `176.532ms` | `88266.227` |
| `entity-component` | `195.506ms` | `97753.216` |
| `archetype-ecs` | `275.663ms` | `137831.505` |

Final normalized snapshot for `xxlarge`:

- `live=1493`
- `total=1493`
- `max=2848`
- `paddle=1`
- `ball=12`
- `brick=1124`
- `particle=128`
- `trail=228`

### Peak Resident Memory

Peak RSS is measured separately for each size by running one benchmark scale per
process:

| Implementation | Small | Medium | Large | Xlarge | Xxlarge |
| --- | ---: | ---: | ---: | ---: | ---: |
| `pooled-data-oriented` | `2532KB` | `2840KB` | `2776KB` | `3360KB` | `3548KB` |
| `entity-component` | `2504KB` | `2964KB` | `3720KB` | `3608KB` | `4148KB` |
| `signature-query-ecs` | `2704KB` | `2640KB` | `3084KB` | `3224KB` | `3164KB` |
| `archetype-ecs` | `3416KB` | `3708KB` | `4348KB` | `4792KB` | `5232KB` |

### Per-System Highlights

- `signature-query-ecs` stays in front at every tested size by raw runtime
- `pooled-data-oriented` and `entity-component` remain close, with the gap still smaller than the jump to `archetype-ecs`
- `transform2d` and `collide` dominate more of the total cost as the brick grid grows
- `entity-component` still pays noticeably more in `cleanupDead` than the others
- `archetype-ecs` is the most memory-hungry implementation in this run
- `xlarge` is not currently fairness-clean because `signature-query-ecs` diverges from the other three on the final normalized snapshot

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
