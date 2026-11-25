"""Helpers for combat decisions on a disposable copy of the M94 server."""
import pathlib
import sqlite3
import struct
import time

from check_m4_exp import warp
from check_m4_skills import wait
from check_m6_profiles import api
from protocol import login, entry

stage = pathlib.Path('/stage')
assert (stage / 'M9_TEST').exists()
owner = 2000001


def setup(*jobs):
    with sqlite3.connect(stage/'ragoff-stage.sqlite3') as db:
        db.execute('UPDATE ragoff_companion SET hp=g.max_hp,sp=g.max_sp FROM ragoff_companion_growth g WHERE g.profile_id=ragoff_companion.id')
        db.execute('DELETE FROM ragoff_companion_supply')
    c = login()
    c.command('@setbattleflag companion_enable 1')
    c.command('@setbattleflag natural_healhp_interval 3600000')
    c.command('@setbattleflag natural_healsp_interval 3600000')
    c.command('@jobchange 7')
    c.command('@set JobLevel 40')
    c.command('@heal')
    warp(c, 'prontera 150 180')
    c.command('@killmonster2')
    api(c, 'party')
    rows = {r['job']:r for r in api(c,'list')[0]}
    for job in jobs:
        pid = rows[job]['id']
        assert 'Summoned' in api(c,f'summon {pid}')[1]
        api(c,f'stop {pid}')
    return c, {r['job']:r for r in api(c,'list')[0]}


def attack(c, mob):
    code,_ = entry('clif_parse_ActionRequest')
    c.send(struct.pack('<HIB',code,mob,7))


def spawn(c, species):
    c.command(f'@monster {species} 1')
    p = wait(c,lambda i,b: i in (0x9fe,0x9ff) and struct.unpack_from('<H',b,23)[0]==species)
    return struct.unpack_from('<I',p,5)[0], (p[63]<<2)|(p[64]>>6), ((p[64]&63)<<4)|(p[65]>>4)
