"""Summarize a ten-minute instrumented farming fixture without counting cleanup kills."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re

PHASES = ("เตรียม", "ออกลาก", "พาฝูงกลับ", "ลงวง", "เก็บตก", "พัก/ถอย")
PHASE = re.compile(r"Mob phase owner=\d+ tick=(\d+) from=(\S+) to=(\S+) elapsed_ms=(\d+) reason=(.+) pack=\d+")
TICK = re.compile(r"(?:QA_(?:STATE|HIT|BUFF|CAST|DEAD|FIELD) |Mob phase owner=\d+ tick=)(\d+)")


def summarize(lines, seconds):
    pulses = [i for i, line in enumerate(lines) if "FARMPULSE " in line]
    if len(pulses) < 2:
        raise ValueError("Missing farming samples")
    before = (int(m[1]) for line in reversed(lines[:pulses[0]]) if (m := TICK.search(line)))
    start = next(before,None)
    if start is None:
        start = next(int(m[1]) for line in lines[pulses[0]:] if (m := TICK.search(line)))
    end = start + round(seconds * 1000)
    phase = None
    entered = None
    times = Counter()
    last_hit = {}
    fields = kills = 0
    for line in lines[:pulses[-1]+1]:
        if event := PHASE.search(line):
            tick, old, new, elapsed, _ = event.groups()
            tick = int(tick)
            if phase is not None and old != phase:
                raise ValueError(f"Broken phase sequence at {tick}")
            if phase is not None and entered is not None:
                if abs(tick-entered-int(elapsed)) > 5 and old != "เตรียม":
                    raise ValueError(f"Invalid transition duration at {tick}")
                times[phase] += max(0, min(tick,end) - max(entered,start))
            phase,entered = new,tick
        elif "QA_FIELD " in line:
            tick = int(line.split("QA_FIELD ")[1].split()[0])
            fields += start <= tick < end
        elif "QA_HIT " in line:
            tick, actor, mob, skill = map(int,line.split("QA_HIT ")[1].split()[:4])
            last_hit[mob] = (actor,skill)
        elif "QA_DEAD " in line:
            tick,mob,_,killer = map(int,line.split("QA_DEAD ")[1].split())
            last = last_hit.pop(mob,None)
            kills += start <= tick < end and killer != 0 and last == (killer,89)
    if entered is not None:
        times[phase] += max(0,end-max(start,entered))
    return dict(seconds_by_phase={p: round(times[p]/1000,1) for p in PHASES},
                storm_fields=fields, storm_kills=kills,
                kills_per_field=round(kills/fields,2) if fields else None)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace",type=Path)
    parser.add_argument("--seconds",type=float,default=600)
    args = parser.parse_args()
    print(json.dumps(summarize(args.trace.read_text(errors="replace").splitlines(),args.seconds),
                     ensure_ascii=False,indent=2))
