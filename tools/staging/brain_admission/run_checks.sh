#!/usr/bin/env bash
set -euo pipefail
observer=$(realpath "$1"); out=$(realpath "$2")
export BRAIN_ADMISSION=1 BRAIN_SHADOW=1 BRAIN_FIVE=1 BRAIN_NATURAL=1 BRAIN_LIMITED=1 TRIAL_RADIUS=6 BRAIN_MODEL="$PWD/reports/companion-brain-stage2-revision/model.json"
mkdir "$out/checks"
pids=()
for probe in critical late range heartbeat manual cover raise orc orc_late; do
    roles=(knight); seconds=24
    if [[ $probe == orc* ]]; then roles=(priest knight); seconds=90; fi
    for role in "${roles[@]}"; do
        d="$out/checks/$probe-$role"; mkdir "$d"
        TRIAL_PROBE="$probe" bash companion-dev/tools/staging/brain_stage1/run.sh "$observer" 09 "$role" "$seconds" "$d" >"$d/run.log" 2>&1 &
        pids+=("$!")
    done
done
rc=0; for pid in "${pids[@]}"; do wait "$pid" || rc=1; done; exit "$rc"
