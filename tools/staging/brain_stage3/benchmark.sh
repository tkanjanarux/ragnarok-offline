#!/usr/bin/env bash
# From the workspace root, provide trial observer and directory with passed preflight traces.
set -euo pipefail
observer=$(realpath "$1"); root=$(realpath "$2")
tool=companion-dev/tools/staging
python3 "$tool/brain_stage3/preflight.py" "$root/preflight" > "$root/preflight.json"
export BRAIN_SHADOW=1 BRAIN_FIVE=1 BRAIN_NATURAL=1 TRIAL_RADIUS=6 BRAIN_MODEL="$PWD/reports/companion-brain-stage2-revision/model.json"
pids=()
run(){
    local mode=$1 field=$2 role=$3 seconds=$4 dest=$5 probe=$6
    mkdir "$dest"
    TRIAL_PROBE="$probe" BRAIN_LIMITED="$mode" bash "$tool/brain_stage1/run.sh" "$observer" "$field" "$role" "$seconds" "$dest" > "$dest/run.log" 2>&1
}
mkdir "$root/normal" "$root/emergency"
for role in knight priest; do
    for hazard in orc orc_late; do
        run 1 09 "$role" 90 "$root/emergency/check-$hazard-09-$role" "$hazard" &
        pids+=("$!")
    done
    for field in 07 09; do
        for rep in 1 2; do
            for mode in 0 1; do
                run "$mode" "$field" "$role" 180 "$root/normal/check-$mode-$rep-$field-$role" '' &
                pids+=("$!")
            done
        done
    done
done
failed=0
for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
((failed==0))
