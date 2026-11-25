#!/usr/bin/env bash
# Compare a pinned planner on the very same native ticks in another directory.
set -euo pipefail
source_dir=$1
output=$2
planner=$3
mkdir -p "$output"
[[ -z $(ls -A "$output") ]]
tool=companion-dev/tools/staging/brain_stage2
for src in "$source_dir"/*/; do
    dest="$output/$(basename "$src")"
    mkdir "$dest"
    ln -sr "$src"*.log.gz "$dest/"
done
find "$output" -name '*.log.gz' -print0 | xargs -0 -P 8 -I{} bash -ec 'python3 "$1" replay "$2" reports/companion-brain-stage2-revision/model.json > "$(dirname "$2")/decisions.jsonl"' _ "$planner" {}
python3 "$tool/revision_metrics.py" "$output" > "$output/metrics.json"
for d in "$output"/old-* "$output"/check-ready-*; do
    [[ -d $d ]] || continue
    python3 "$tool/assess.py" check "$d"/*.gz "$d/decisions.jsonl" > "$d/check.json"
done
