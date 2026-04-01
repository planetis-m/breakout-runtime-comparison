#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LD_LIBRARY_PATH="$ROOT"
BENCH_ROOT="$ROOT/breakout-runtime-comparison"
mkdir -p "$BENCH_ROOT/.nimcache"

nim c --threads:on -d:release --nimcache:"$BENCH_ROOT/.nimcache/data_oriented" "$BENCH_ROOT/run_data_oriented.nim"
nim c --threads:on -d:release --nimcache:"$BENCH_ROOT/.nimcache/entity_component" "$BENCH_ROOT/run_entity_component.nim"
nim c --threads:on -d:release --nimcache:"$BENCH_ROOT/.nimcache/archetype_ecs" "$BENCH_ROOT/run_archetype_ecs.nim"
nim c --threads:on -d:release --nimcache:"$BENCH_ROOT/.nimcache/signature_query_ecs" "$BENCH_ROOT/run_legacy_signature_ecs.nim"

"$BENCH_ROOT/run_data_oriented"
"$BENCH_ROOT/run_entity_component"
"$BENCH_ROOT/run_archetype_ecs"
"$BENCH_ROOT/run_legacy_signature_ecs"
