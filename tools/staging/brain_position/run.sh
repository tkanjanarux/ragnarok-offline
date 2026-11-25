#!/usr/bin/env bash
# Independent map/char/login servers and database for every observation.
set -euo pipefail
observer=$(realpath "$1"); root=$(realpath "$2")
export BRAIN_FIVE=1 BRAIN_SHADOW=0
run(){
 local radius=$1 map=$2 role=$3 arm=$4 round=$5 seconds=$6 probe=$7
 local d="$root/$radius-$map-$role-$round-$arm"
 mkdir "$d"
 POSITION_ARM="$arm" TRIAL_RADIUS="$radius" TRIAL_PROBE="$probe" bash companion-dev/tools/staging/brain_stage1/run.sh "$observer" "$map" "$role" "$seconds" "$d" >"$d/run.log" 2>&1
}
batch(){
 local radius=$1 rounds=$2 seconds=$3 probe=$4
 local pids=()
 for map in ${5:-07 09}; do for role in knight priest; do for ((round=1;round<=rounds;round++)); do for arm in native moved; do
   run "$radius" "$map" "$role" "$arm" "$round" "$seconds" "$probe" & pids+=("$!")
 done; done; done; done
 local failed=0; for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
 ((failed==0))
}
case "$3" in
short) batch 6 3 180 '';;
far) batch 96 2 180 '';;
emergency) batch 6 1 12 orc 09;;
esac
