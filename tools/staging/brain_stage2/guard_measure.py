"""Measure camp peel from first backline hit to native aggro switching to Knight."""
import json
import sys
from pathlib import Path

from planner import OWNER, W, H, K, P, CAMP, World, readlog, pos, dist


def measure(log):
    frame = None
    pending = {}
    rows = []

    def close(mid, t, outcome):
        start, victim = pending.pop(mid)
        rows.append(dict(victim=victim, seconds=round((t-start)/1000, 3), outcome=outcome))

    for kind, event in World().frames(readlog(log, False)):
        if kind == 'frame':
            frame = event
            continue
        if frame is None:
            continue
        if kind == 'HIT':
            t, mid, victim = event[:3]
            if (frame['pull'] == P and mid in frame['m'] and victim in (OWNER, W, H, CAMP)
                    and dist(pos(frame['a'][victim]), frame['anchor']) <= 10):
                pending.setdefault(mid, (t, victim))
        elif kind == 'AGGRO':
            t, mid, previous, target = event
            if mid in pending and target:
                victim = pending[mid][1]
                if target != victim:
                    close(mid, t, 'knight' if target == K and previous == victim else 'other_switch')
        elif kind == 'KILL' and event[1] in pending:
            close(event[1], event[0], 'mob_dead')
        elif kind == 'DEATH':
            for mid, (_, victim) in list(pending.items()):
                if victim == event[1]:
                    close(mid, event[0], 'victim_dead')
    for mid in list(pending):
        close(mid, max(frame['t'], pending[mid][0]), 'end')
    return rows


if __name__ == '__main__':
    print(json.dumps({p.parent.name: measure(p) for p in map(Path, sys.argv[1:])}, indent=2))
