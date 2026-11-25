"""Compare paired ten-minute multi-box runs against the deployed source on identical fixtures."""
import argparse
import csv
import hashlib
import json
import re
from collections import Counter, defaultdict
from itertools import product
from pathlib import Path
from statistics import median

ORDER = re.compile(r'Mob order owner=\d+ tick=(\d+) actor=(\d+) action=(\d+) target=(\d+).*?reason=(.+?) return_ms=\d+ field_ms=(\d+).*?previous=(.*)$')
DEATH = re.compile(r'MB_MORTALITY (\d+) (-?\d+)')
OWNER = 2000001
ACTORS = range(95000000, 95000004)


def run_metrics(result, stage, version, field, cap, puller, repeat):
    data = json.loads(result.read_text().splitlines()[-1])
    if data['mode'] != 'mob' or data['field'] != 'yuno_fild'+field or not 598 <= data['seconds'] <= 608:
        raise ValueError(f'Invalid measurement in {result}')
    trace = (stage/'artifacts/map-server.log').read_text(errors='replace').splitlines()
    pulses = [i for i, line in enumerate(trace) if 'FARMPULSE ' in line]
    if len(pulses) < 500:
        raise ValueError(f'Incomplete trace in {stage}')
    mortality = Counter()
    orders = defaultdict(dict)
    storm_levels = Counter()
    blocked = Counter()
    simultaneous = 0
    collisions = 0
    pulses_by_state = Counter()
    state = "unknown"
    puller_id = 95000001 if puller=='knight' else 95000000
    anchor_x, anchor_y = data['anchor']
    previous_gap = None
    outbound_during_field = False
    observed_steps = 0
    for line in trace[pulses[0]:pulses[-1]+1]:
        if "Mob wizard owner=" in line:
            state = ("regroup" if "retreat=1" in line else "rest" if "rest=1" in line
                     else "no target" if "target=0 camp=0 pack=0" in line else "engaged")
        if 'Mob field landed wizard=' in line and ' skill=89 ' in line:
            level=int(line.split(' level=')[1].split()[0])
            storm_levels[level]+=1
        if 'FARMPULSE ' in line:
            pulses_by_state[state] += 1
        if 'FARMTANK ' in line:
            x, y = map(int,line.split('FARMTANK ')[1].split()[:2])
            gap=max(abs(x-anchor_x),abs(y-anchor_y))
            if outbound_during_field and previous_gap is not None and gap>previous_gap:
                observed_steps += gap-previous_gap
            previous_gap=gap
        if 'Companion retreat:' in line or ('Mob order owner=' in line and 'reason=regroup' in line):
            outbound_during_field=False
        if match := DEATH.search(line):
            actor, count = map(int, match.groups())
            mortality[actor] = max(mortality[actor], count)
        if match := ORDER.search(line):
            tick, actor, action, target, reason, field_left, previous = match.groups()
            book = orders[int(tick)]
            if int(actor) in book:
                raise ValueError(f'Duplicate decision for {actor} at {tick}')
            book[int(actor)] = (int(action), int(target), int(field_left), reason)
            if int(actor) == puller_id:
                outbound_during_field = reason == 'collect along route' and int(field_left)>0
            if actor == '95000002':
                blocked[previous] += 1
    if set(mortality) != {OWNER, *ACTORS}:
        raise ValueError(f'Missing native death counters in {stage}')
    overlap = sum(1 for book in orders.values() if puller_id in book and
                  book[puller_id][3] == "collect along route" and book[puller_id][2] > 0)
    for book in orders.values():
        if puller_id not in book or book[puller_id][3] != "collect along route":
            continue
        wizard, hunter = book.get(95000002), book.get(95000003)
        simultaneous += bool(wizard and wizard[0]==5)
        collisions += bool(hunter and hunter[0]==3 and hunter[1]==book[puller_id][1])
    intervals = [b-a for a,b in zip(sorted(orders),sorted(orders)[1:]) if b-a<2000]
    return dict(version=version, field=field, cap=cap, puller=puller, repeat=repeat,
                seconds=data['seconds'], base=data['base'], job=data['job'],
                owner_deaths=max(data['owner_deaths'],mortality[OWNER]),
                companion_deaths=max(data['companion_deaths'],sum(mortality[a] for a in ACTORS)),
                arrived=data['arrived'], tagged=data['tagged'], storm_fields=data['storm_fields'], storm_1_to_3=sum(storm_levels[n] for n in (1,2,3)),
                storm_level10=storm_levels[10],
                regroup_seconds=round(data['seconds']*pulses_by_state['regroup']/sum(pulses_by_state.values()),1),
                empty_seconds=round(data['seconds']*pulses_by_state['no target']/sum(pulses_by_state.values()),1),
                withdrawal=sum('Companion retreat:' in line for line in trace[pulses[0]:pulses[-1]+1]),
                overlap_ticks=overlap if version!='production' else None,
                outward_cells_during_field=observed_steps, concurrent_orders=simultaneous, hunter_shot_order_on_pull_target=collisions,
                median_planning_ms=median(intervals) if intervals else None,
                wizard_moving_ticks=blocked['establish casting range'],
                wizard_rejected_ticks=blocked['native-cast-rejected'],
                wizard_resistant_ticks=blocked['no-susceptible-target'],
                field_active_ticks=sum(1 for b in orders.values() if 95000002 in b and b[95000002][2]>0),
                potions=sum(v for k,v in data['used'].items() if int(k)!=717 and not 1750<=int(k)<=1775),
                gems=data['used'].get('717',0), anchor=','.join(map(str,data['anchor'])),
                layout=hashlib.sha256((stage/'artifacts/farm-layout.json').read_bytes()).hexdigest())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('logs',type=Path)
    parser.add_argument('stages',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--candidate', default='candidate')
    args = parser.parse_args()
    rows = []
    for field, cap, puller, repeat in product(('07','08','09'),(10,15,20),('knight','priest'),(1,2)):
        pair = []
        for version in ('production',args.candidate):
            tag = f'bench-mbox-{version}-{field}-{cap}-{puller}-{repeat}'
            pair.append(run_metrics(args.logs/(tag+'.log'), args.stages/('stage-'+tag),
                                    version,field,cap,puller,repeat))
        assert (pair[0]['layout'],pair[0]['anchor']) == (pair[1]['layout'],pair[1]['anchor']), tag
        rows.extend(pair)
    with args.output.open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
