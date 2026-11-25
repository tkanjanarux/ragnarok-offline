"""Verify native base and equipped battle stats across owner level and class changes."""
import json
import re
import sqlite3
import time
from pathlib import Path

from check_m4_skills import wait
from check_m6_profiles import api
from protocol import login

stage = Path('/stage')
assert (stage/'M9_TEST').exists() and (stage/'STAGING_ONLY').exists()
db = sqlite3.connect(stage/'ragoff-stage.sqlite3')
keys = ('str','agi','vit','int','dex','luk')
paths = {
    7: 'dex20 str30 vit30 dex35 vit50 str60 vit80 str90 dex70 agi30',
    8: 'int50 vit20 int70 dex30 vit40 int90 dex50 vit60 int99 dex70 agi20',
    9: 'int50 vit15 dex50 int70 dex80 vit30 int85 dex90 int99 vit40 agi15',
}
budgets = dict((int(l),int(p)) for l,p in re.findall(
    r'Level: (\d+)\s+Points: (\d+)',(stage/'db/re/statpoint.yml').read_text()))
def expected(line,level):
    values = dict.fromkeys(keys,1)
    remaining = budgets[level]
    for stat,goal in re.findall(r'([a-z]+)(\d+)',paths[line]):
        for current in range(values[stat],int(goal)):
            cost = 2+(current-1)//10
            if remaining < cost:
                return list(values.values()),remaining
            remaining -= cost
            values[stat] += 1
    return list(values.values()),remaining

def belongings():
    tables = ('gear','gear_details','policy','preset','supply')
    return {t:db.execute('SELECT * FROM ragoff_companion_'+t+' ORDER BY rowid').fetchall() for t in tables}

before = belongings()
copy = (stage/'stat-test-owner.json')
client = login()
client.command('@setbattleflag companion_enable 1')
profiles = api(client,'list')[0]
assert len(profiles)==3
def summon_all():
    for profile in profiles:
        pid=profile['id']
        assert 'Summoned' in api(client,f'summon {pid}')[1]
        api(client,f'stop {pid}')
    return {p['actor']:p for p in api(client,'list')[0]}

def verify(owner_class,level,job):
    client.command(f'@jobchange {owner_class}')
    client.command(f'@set BaseLevel {level}')
    client.command(f'@set JobLevel {job}')
    time.sleep(.8)
    client.command('@companion status')
    seen=set()
    while len(seen)<len(actors):
        packet=wait(client,lambda i,b:i==0x8e and b'Companion id=' in b)
        stats={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',packet.decode(errors='replace'))}
        profile=actors[stats['id']]
        line=profile['job']
        cls={7:1,8:4,9:2}[line] if owner_class in (1,3) else line
        assert (stats['class'],stats['base'],stats['job'])==(cls,level,job),stats
        base=[stats[k] for k in keys]
        total=[stats['total_'+k] for k in keys]
        assert (base,stats['points'])==expected(line,level),stats
        seen.add(stats['id'])
        if level==52:
            print('MEASURE',profile['name'],'class',cls,'base',base,'total',total)
    assert belongings()==before

if copy.exists():
    owner=json.loads(copy.read_text())
    # Equip restrictions are checked at spawn, so start at the original owner's level.
    client.command(f"@jobchange {owner['class']}")
    client.command(f"@set BaseLevel {owner['base_level']}")
    client.command(f"@set JobLevel {owner['job_level']}")
    time.sleep(1)
actors=summon_all()
if copy.exists():
    verify(owner['class'],owner['base_level'],owner['job_level'])
    verify(owner['class'],52,44)
    verify(7,52,44)
    verify(owner['class'],owner['base_level'],owner['job_level'])
else:
    for lv in (10,30,50,52,80,99,30,52):
        verify(1,lv,44)
    verify(7,52,44)
    verify(1,52,44)
for p in profiles:
    api(client,f"bench {p['id']}")
actors=summon_all()
verify(owner['class'] if copy.exists() else 1,52,44)
client.close()
print('PASS step boundaries, unspent points, resummon and persisted equipment, potions, skills and presets')
