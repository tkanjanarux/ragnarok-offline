#!/usr/bin/env bash
# From the workspace root, pass an instrumented binary, map suffix, puller,
# seconds, output directory, and optionally 'deaths' or 'credit'.
set -euo pipefail
binary=$(realpath "$1")
field=$2
puller=$3
seconds=$4
out=$(realpath "$5")
control=${6:-farm}
[[ "$field" =~ ^(07|09)$ && "$puller" =~ ^(priest|knight)$ && "$seconds" =~ ^[1-9][0-9]*$ ]]
[[ "$control" =~ ^(farm|deaths|credit)$ ]]
data=$PWD/reports/companion-brain-stage1
probes=$PWD/companion-dev/tools/staging/brain_stage1
stage=$(mktemp -d /dev/shm/ragoff-observe.XXXXXXXX)
name=$(basename "$stage")
cleanup() {
    if [[ -n ${shadow_pid:-} ]]; then kill "$shadow_pid" 2>/dev/null || true; fi
    docker rm -f "$name" >/dev/null 2>&1 || true
    rm -rf -- "$stage"
}
trap cleanup EXIT
cp -a companion-dev/runtime/m94/. "$stage/"
test -f "$stage/STAGING_ONLY"
cp cash-shop/item_cash.yml "$stage/db/import/item_cash.yml"
cp companion-dev/npc/custom/companion_recruiter.txt "$stage/npc/custom/"
printf '\nitem_drop_card_min: 100\nitem_drop_card_max: 100\n' >>"$stage/conf/import/battle_conf.txt"
python3 - "$stage" <<'PY'
from pathlib import Path
import sqlite3,sys
with sqlite3.connect(Path(sys.argv[1])/'ragoff-stage.sqlite3') as db:
    for p in sorted(Path('companion-dev/sqlite-files/companion').glob('*.sql')):
        if 7<=int(p.name[:3])<=12:db.executescript(p.read_text())
PY
python3 "$probes/seed.py" "$stage" "$data/team-fixture.json"
python3 - "$stage" <<'PY'
from pathlib import Path
import sqlite3,sys
with sqlite3.connect(Path(sys.argv[1])/'ragoff-stage.sqlite3') as db:
    db.execute('update char set base_level=88,job_level=47 where char_id=150001')
    db.execute("update char_reg_num set value=50 where char_id=150001 and key='jobchange_level'")
    db.execute("update ragoff_companion_policy set skill_order='quicken,provoke,endure' where profile_id=2")
    db.execute("update ragoff_companion_policy set skill_order='storm,firebolt,waterball,coldbolt,lightningbolt,earthspike,jupitelthunder' where profile_id=3")
PY
cp "$data/layout-$field.json" "$stage/artifacts/farm-layout.json"
# The snapshot contains an old readiness banner. Await this instance's startup.
: > "$stage/artifacts/map-server.log"
trial_env=()
if [[ ${BRAIN_LIMITED:-0} == 1 ]]; then trial_env=(-e BRAIN_LIMITED=1); fi
if [[ ${POSITION_ARM:-} == moved ]]; then trial_env+=(-e CAMP_POSITION=1); fi
if [[ ${DELIVERY_FIXTURE:-0} == 1 ]]; then trial_env+=(-e DELIVERY_CASE="${DELIVERY_CASE:-clear}"); fi
docker run -d "${trial_env[@]}" --name "$name" --network none -v "$stage:/stage" -v "$binary:/stage/map-server:ro" \
    -v "$PWD/companion-dev/build-m1/bin/char-server:/stage/char-server:ro" \
    -v "$PWD/companion-dev/build-m1/bin/login-server:/stage/login-server:ro" \
    -v "$PWD/companion-dev/tools/staging:/tests:ro" ragoff-companion-staging:m1 python3 /tests/serve.py >/dev/null
fixture="$probes/fixture.py"
shadow_pid=
if [[ ${BRAIN_SHADOW:-0} == 1 ]]; then
    fixture="$PWD/companion-dev/tools/staging/brain_stage2/fixture.py"
    if [[ ${BRAIN_CAMP_STRESS:-0} == 1 ]]; then fixture="${fixture%/*}/camp_pressure.py"; fi
    if [[ ${BRAIN_NATURAL:-0} == 1 ]]; then fixture="$probes/fixture.py"; fi
    if [[ ${BRAIN_PREPARED:-0} == 1 ]]; then fixture="$PWD/companion-dev/tools/staging/brain_stage2/prepared_fixture.py"; fi
    controller="$PWD/companion-dev/tools/staging/brain_stage2/planner.py"
    if [[ ${BRAIN_LIMITED:-0} == 1 ]]; then
        controller="$PWD/companion-dev/tools/staging/brain_stage3/controller.py"
        fixture="${controller%/*}/fixture.py"
        if [[ ${BRAIN_ADMISSION:-0} == 1 ]]; then
            controller="$PWD/companion-dev/tools/staging/brain_admission/controller.py"
            fixture="${controller%/*}/fixture.py"
        fi
    fi
    python3 "$controller" live "$stage/artifacts/map-server.log" "$BRAIN_MODEL" > "$out/decisions.jsonl" &
    shadow_pid=$!
fi
if [[ -n ${POSITION_ARM:-} && -n ${TRIAL_PROBE:-} ]]; then
    fixture="$PWD/companion-dev/tools/staging/brain_position/emergency.py"
fi
if [[ ${DELIVERY_FIXTURE:-0} == 1 ]]; then fixture="$PWD/companion-dev/tools/staging/brain_delivery/fixture.py"; fi
options=()
case "$control" in
    deaths) options=(-e BRAIN_POSITIVE_CONTROL=1);;
    credit) options=(-e BRAIN_FAR_EXP=1);;
esac
docker exec -i -e DELIVERY_CASE="${DELIVERY_CASE:-clear}" -e TRIAL_PROBE="${TRIAL_PROBE:-}" -e BRAIN_FIVE="${BRAIN_FIVE:-0}" -e BRAIN_APPROACH="${BRAIN_APPROACH:-0}" -e BRAIN_LATE_PRESSURE="${BRAIN_LATE_PRESSURE:-0}" -e BRAIN_FAR_STRESS="${BRAIN_FAR_STRESS:-0}" -e PYTHONPATH=/tests -e FARM_MODE=mob -e FARM_MAP="yuno_fild$field" \
    -e FARM_SECONDS="$seconds" -e FARM_RADIUS="${TRIAL_RADIUS:-96}" -e FARM_CAP=10 -e FARM_HERD=1 \
    -e FARM_PULLER="$puller" "${options[@]}" "$name" python3 -u - <"$fixture" >"$out/$control-$field-$puller.result"
if [[ -n "$shadow_pid" ]]; then wait "$shadow_pid"; fi
docker stop "$name" >/dev/null
rg -a 'B_[A-Z]+ |Mob (escort|wave|wizard)' "$stage/artifacts/map-server.log" | gzip -c >"$out/$control-$field-$puller.log.gz"
