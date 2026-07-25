#!/bin/sh
set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "usage: $0 s|m|l /path/to/report.json [/path/to/baseline.json]" >&2
  exit 64
fi

scale=$1
report=$2
baseline=${3:-}
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture_root=${CURRENT_BENCHMARK_ROOT:-"$project_dir/.build/Benchmarks"}
repository="$fixture_root/$scale"
git_executable=${CURRENT_BENCHMARK_GIT:-/usr/bin/git}
iterations=${CURRENT_BENCHMARK_ITERATIONS:-7}

case "$scale" in
  s|m|l) ;;
  *)
    echo "error: scale must be s, m, or l" >&2
    exit 64
    ;;
esac

mkdir -p "$fixture_root" "$(dirname -- "$report")"

swift run -c release current-benchmark generate \
  --scale "$scale" \
  --output "$repository" \
  --git "$git_executable"

swift run -c release current-benchmark run \
  --repository "$repository" \
  --iterations "$iterations" \
  --output "$report" \
  --git "$git_executable"

if [ -n "$baseline" ]; then
  swift run -c release current-benchmark compare \
    --baseline "$baseline" \
    --candidate "$report" \
    --threshold 10
fi
