#!/usr/bin/env bash
# Run from workspace root with the stage-2 observer binary and an empty output directory.
set -euo pipefail
observer=$(realpath "$1")
out=$(realpath -m "$2")
mkdir -p "$out"
[[ -z $(ls -A "$out") ]]
export BRAIN_MODEL="$PWD/reports/companion-brain-stage2-revision/model.json" BRAIN_SHADOW=1
tool=companion-dev/tools/staging/brain_stage2
pids=()
for group in field1 field2 approach pressure late need; do
    for role in knight priest; do
        for field in 07 09; do
            [[ $group == field* || $field == 09 ]] || continue
            d="$out/check-$group-$field-$role"
            mkdir "$d"
            (
                export BRAIN_NATURAL=0 BRAIN_CAMP_STRESS=0 BRAIN_LATE_PRESSURE=0 BRAIN_APPROACH=0 BRAIN_FAR_STRESS=0
                case $group in
                    field*) export BRAIN_NATURAL=1 ;;
                    approach) export BRAIN_CAMP_STRESS=1 BRAIN_LATE_PRESSURE=1 BRAIN_APPROACH=1 ;;
                    pressure) export BRAIN_CAMP_STRESS=1 ;;
                    late) export BRAIN_CAMP_STRESS=1 BRAIN_LATE_PRESSURE=1 ;;
                    need) export BRAIN_FAR_STRESS=1 ;;
                esac
                bash companion-dev/tools/staging/brain_stage1/run.sh "$observer" "$field" "$role" 165 "$d"
            ) > "$d/run.log" 2>&1 &
            pids+=("$!")
        done
    done
done
failed=0
for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
(( failed == 0 ))
python3 "$tool/revision_metrics.py" "$out" > "$out/metrics.json"
python3 "$tool/incident_report.py" "$out"/check-{pressure,late}-* > "$out/incidents.json"
python3 "$tool/guard_measure.py" "$out"/check-*priest/*.gz > "$out/guard.json"
