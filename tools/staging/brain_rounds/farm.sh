#!/usr/bin/env bash
# Pass native, v10, rounds executables, and a fresh evidence directory.
set -euo pipefail
bins=("$(realpath "$1")" "$(realpath "$2")" "$(realpath "$3")")
out=$(realpath -m "$4")
mkdir "$out"
for rep in 1 2; do
    pids=()
    order=(0 1 2)
    if [[ $rep == 2 ]]; then order=(2 1 0); fi
    for map in 07 09; do for puller in knight priest; do for idx in "${order[@]}"; do
        arms=(native delivery rounds)
        d="$out/96-$map-$puller-$rep-${arms[idx]}"
        mkdir "$d"
        BRAIN_FIVE=1 POSITION_ARM=native TRIAL_RADIUS=96 bash companion-dev/tools/staging/brain_stage1/run.sh \
            "${bins[idx]}" "$map" "$puller" 120 "$d" >"$d/run.log" 2>&1 &
        pids+=("$!")
    done; done; done
    failed=0
    for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
    (( ! failed )) || exit 1
done
