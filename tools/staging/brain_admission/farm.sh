#!/usr/bin/env bash
set -euo pipefail
observer=$(realpath "$1"); root=$(realpath "$2")
python3 "$(dirname "$0")/checks.py" "$root/checks" > "$root/checks.json"
export BRAIN_ADMISSION=1 BRAIN_SHADOW=1 BRAIN_FIVE=1 BRAIN_NATURAL=1 TRIAL_RADIUS=6 BRAIN_MODEL="$PWD/reports/companion-brain-stage2-revision/model.json"
mkdir "$root/farm"; pids=()
for field in 07 09; do for role in knight priest; do for rep in 1 2; do for mode in 0 1; do
  d="$root/farm/check-$mode-$rep-$field-$role"; mkdir "$d"
  BRAIN_LIMITED="$mode" bash companion-dev/tools/staging/brain_stage1/run.sh "$observer" "$field" "$role" 180 "$d" >"$d/run.log" 2>&1 &
  pids+=("$!")
done; done; done; done
rc=0; for pid in "${pids[@]}"; do wait "$pid" || rc=1; done; exit "$rc"
