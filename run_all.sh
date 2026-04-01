#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LD_LIBRARY_PATH="$ROOT"
BENCH_ROOT="$ROOT/breakout-runtime-comparison"
mkdir -p "$BENCH_ROOT/.nimcache"

if [[ -x /usr/bin/time ]]; then
  TIME_BIN=/usr/bin/time
elif command -v gtime >/dev/null 2>&1; then
  TIME_BIN="$(command -v gtime)"
else
  echo "error: GNU time is required to report peak resident memory (expected /usr/bin/time or gtime)" >&2
  exit 1
fi

run_benchmark() {
  local label="$1"
  local executable="$2"
  local memory_file
  memory_file="$(mktemp)"

  "$TIME_BIN" -f "peak_rss_kb=%M" -o "$memory_file" "$executable"

  local peak_rss_kb
  peak_rss_kb="$(sed -n 's/^peak_rss_kb=//p' "$memory_file")"
  rm -f "$memory_file"

  if [[ -n "$peak_rss_kb" ]]; then
    echo "$label peak-rss: ${peak_rss_kb}KB"
  fi
}

nim c --threads:on -d:release --nimcache:"$BENCH_ROOT/.nimcache/data_oriented" "$BENCH_ROOT/run_data_oriented.nim"
nim c --threads:on -d:release --nimcache:"$BENCH_ROOT/.nimcache/entity_component" "$BENCH_ROOT/run_entity_component.nim"
nim c --threads:on -d:release --nimcache:"$BENCH_ROOT/.nimcache/archetype_ecs" "$BENCH_ROOT/run_archetype_ecs.nim"
nim c --threads:on -d:release --nimcache:"$BENCH_ROOT/.nimcache/signature_query_ecs" "$BENCH_ROOT/run_legacy_signature_ecs.nim"

run_benchmark "pooled-data-oriented" "$BENCH_ROOT/run_data_oriented"
run_benchmark "entity-component" "$BENCH_ROOT/run_entity_component"
run_benchmark "archetype-ecs" "$BENCH_ROOT/run_archetype_ecs"
run_benchmark "signature-query-ecs" "$BENCH_ROOT/run_legacy_signature_ecs"
