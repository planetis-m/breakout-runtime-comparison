# Breakout Runtime Comparison

`breakout-runtime-comparison` is a standalone Nim benchmark suite for comparing
multiple runtime architectures on the same Breakout simulation.

It exists to answer a narrow question:

Which runtime model is faster when the gameplay, update order, input script, and
simulation rules are held constant?

This repo benchmarks five implementations of the same headless Breakout runtime:

- `pooled-data-oriented`
- `pure-dod`
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
| `pure-dod` | `29.623ms` | `14811.470` |
| `pooled-data-oriented` | `50.882ms` | `25440.981` |
| `signature-query-ecs` | `51.505ms` | `25752.540` |
| `entity-component` | `62.704ms` | `31352.137` |
| `archetype-ecs` | `77.453ms` | `38726.291` |

Final normalized snapshot for the fairness-matched runtimes at `small`:

- `live=593`
- `total=593`
- `max=4482`
- `paddle=1`
- `ball=14`
- `brick=88`
- `particle=224`
- `trail=266`

`pure-dod` diverged in this run:

- `live=371`
- `total=371`
- `max=4482`
- `paddle=1`
- `ball=14`
- `brick=90`
- `particle=0`
- `trail=266`

### Medium

| Implementation | Avg total | Ns/tick |
| --- | ---: | ---: |
| `pure-dod` | `49.095ms` | `24547.487` |
| `signature-query-ecs` | `92.504ms` | `46251.959` |
| `pooled-data-oriented` | `112.585ms` | `56292.702` |
| `entity-component` | `122.741ms` | `61370.365` |
| `archetype-ecs` | `164.093ms` | `82046.748` |

Final normalized snapshot for the fairness-matched runtimes at `medium`:

- `live=793`
- `total=793`
- `max=3331`
- `paddle=1`
- `ball=19`
- `brick=316`
- `particle=96`
- `trail=361`

`pure-dod` diverged in this run:

- `live=636`
- `total=636`
- `max=3331`
- `paddle=1`
- `ball=16`
- `brick=315`
- `particle=0`
- `trail=304`

### Large

| Implementation | Avg total | Ns/tick |
| --- | ---: | ---: |
| `pure-dod` | `110.021ms` | `55010.643` |
| `signature-query-ecs` | `216.685ms` | `108342.344` |
| `pooled-data-oriented` | `248.319ms` | `124159.567` |
| `entity-component` | `289.481ms` | `144740.725` |
| `archetype-ecs` | `391.245ms` | `195622.589` |

Final normalized snapshot for the fairness-matched runtimes at `large`:

- `live=1458`
- `total=1458`
- `max=4402`
- `paddle=1`
- `ball=27`
- `brick=821`
- `particle=96`
- `trail=513`

`pure-dod` diverged in this run:

- `live=1327`
- `total=1327`
- `max=4402`
- `paddle=1`
- `ball=24`
- `brick=814`
- `particle=32`
- `trail=456`

### Xlarge

| Implementation | Avg total | Ns/tick |
| --- | ---: | ---: |
| `pure-dod` | `204.726ms` | `102363.178` |
| `signature-query-ecs` | `323.905ms` | `161952.634` |
| `pooled-data-oriented` | `380.067ms` | `190033.361` |
| `entity-component` | `448.429ms` | `224214.663` |
| `archetype-ecs` | `687.179ms` | `343589.579` |

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
| `pure-dod` | `315.826ms` | `157913.025` |
| `signature-query-ecs` | `420.378ms` | `210189.115` |
| `pooled-data-oriented` | `570.333ms` | `285166.328` |
| `entity-component` | `627.400ms` | `313699.923` |
| `archetype-ecs` | `1006.844ms` | `503421.903` |

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
| `pooled-data-oriented` | `4212KB` | `3572KB` | `4172KB` | `4116KB` | `4748KB` |
| `pure-dod` | `4360KB` | `3780KB` | `4220KB` | `4420KB` | `4612KB` |
| `entity-component` | `4496KB` | `3892KB` | `4740KB` | `6268KB` | `6152KB` |
| `signature-query-ecs` | `4340KB` | `3972KB` | `4612KB` | `4868KB` | `5328KB` |
| `archetype-ecs` | `7208KB` | `5408KB` | `6592KB` | `6956KB` | `8224KB` |

### Per-System Highlights

- `pure-dod` is the fastest implementation in this run at every tested size
- `pure-dod` matches the other runtimes at `xlarge` and `xxlarge`, but diverges at `small`, `medium`, and `large`
- among the fairness-matched runtimes, `signature-query-ecs` is the fastest at `medium` through `xxlarge`
- `transform2d` and `collide` dominate more of the total cost as the brick grid grows
- `entity-component` still pays noticeably more in `cleanupDead` than the others
- `archetype-ecs` remains the most memory-hungry implementation in this run

These numbers are machine-dependent. Treat them as a benchmark snapshot for the
current code in this repository, not as a universal claim about these
architectures.

## Implementations

### `pooled-data-oriented`

Concrete actor records with typed component indices and explicit pool-backed
storage.

### `pure-dod`

Dense per-kind stores with a shared transform hierarchy service. This variant is
intentionally more game-shaped and more directly data-oriented than the pooled
baseline.

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
├── bench_random.nim
├── shared/
│   ├── headless_raylib.nim
│   └── vmath.nim
├── implementations/
│   ├── pooled_data_oriented/runtime.nim
│   ├── pure_dod/runtime.nim
│   ├── entity_component/runtime.nim
│   ├── archetype_ecs/runtime.nim
│   └── signature_query_ecs/runtime.nim
├── run_data_oriented.nim
├── run_pure_dod.nim
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
