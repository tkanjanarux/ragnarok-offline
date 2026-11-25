#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
mode=${1:?usage: run.sh m1|asan|baseline}
case "$mode" in baseline|m1|asan|m2|m2asan|m3|m3asan|m4|m4asan|m4probe|m5|m5asan|m6|m6asan|m7|m7asan|m8|m8asan|m8probe|m9|m9asan|m9off|m9job|m92|m92asan|m92off|m93|m93asan|m93regress|m93oldchar) ;; *) exit 2 ;; esac
stage="$root/runtime/$mode"
test -f "$stage/STAGING_ONLY"
args=()
if [[ "$mode" == *asan ]]; then
  args+=(-e ASAN_OPTIONS=detect_leaks=1:handle_segv=2:abort_on_error=1 -e UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=0)
fi
docker run -d --name "ragoff-companion-$mode" --network none \
  --user "$(id -u):$(id -g)" --cap-drop ALL --security-opt no-new-privileges \
  --cpus 4 --memory 5g --pids-limit 128 \
  --mount "type=bind,src=$stage,dst=/stage" \
  --mount "type=bind,src=$root/tools/staging,dst=/tests,readonly" \
  "${args[@]}" ragoff-companion-staging:m1 python3 /tests/serve.py
