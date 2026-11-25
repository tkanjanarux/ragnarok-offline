#!/usr/bin/env bash
# Each process gets its own DB, server processes, survey layout and ledger.
set -euo pipefail
native=$(realpath "$1")
delivery=$(realpath "$2")
out=$(realpath -m "$3")
mkdir -p "$out"
for rep in 1 2; do
    pids=()
    arms=(native delivery)
    if [[ $rep == 2 ]]; then arms=(delivery native); fi
    for map in 07 09; do for role in knight priest; do for arm in "${arms[@]}"; do
        d="$out/96-$map-$role-$rep-$arm"
        mkdir "$d"
        bin=$native
        if [[ $arm == delivery ]]; then bin=$delivery; fi
        BRAIN_FIVE=1 BRAIN_SHADOW=0 POSITION_ARM=native TRIAL_RADIUS=96 \
            bash companion-dev/tools/staging/brain_stage1/run.sh "$bin" "$map" "$role" 180 "$d" >"$d/run.log" 2>&1 &
        pids+=("$!")
    done; done; done
    failed=0
    for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
    if ((failed)); then exit 1; fi
done
