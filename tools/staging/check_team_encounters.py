"""Real native packs and MVP, no changes to monster stats, AI or skill DB."""
import os
import select
import struct
import time
from nearby_hunt_fixture import c, knight, mage, priest, stage, wait, query
from build_fixture import BuildFixture
from check_m4_exp import warp
from check_m8_gear import slot, transfer, held

f = BuildFixture(c)
for member in (knight, priest, mage):
    f.note(f'bench {member["id"]}')
c.command('@jobchange 3')
c.command('@set JobLevel 50')
c.command('@jobchange 11')
c.command('@set BaseLevel 85')
c.command('@set JobLevel 45')
c.command('@heal')
area_build=os.environ.get('TEAM_WIZARD','storm')
area_id={'storm':89,'vermilion':85}[area_build]
f.select(mage['id'], area_build)
f.note('recruit hunter')
members = [int(row[1]) for row in f.frames('list') if row[0]=='row']
for pid in members:
    for item, amount in [(504,40),(505,20),(1750,800)]:
        f.db.execute('insert or replace into ragoff_companion_supply select id,owner_char,?,? from ragoff_companion where id=?',(item, amount, pid))
warp(c, 'prontera 150 180')
c.command('@killmonster2')
for pid in members:
    gear=[]
    job=int(f.row(pid)[2])
    items=[2345,{7:1128,8:1610,9:1610,11:1714}[job]]
    if job==7: items.append(2106)
    for item in items:
        # Bigfoot Card reduces insect damage. The Knight trades Quicken for a shield.
        if item==2106: c.command('@item2 2106 1 1 4 0 4074 0 0 0')
        else: c.command(f'@item {item} 1')
        transfer(c,pid,slot(c,item))
        gear.append(held(pid)[-1][0])
    assert 'Summoned'  in f.note(f'summon {pid}')
    if gear:
        f.note(f'stop {pid}')
        for gid in gear: assert 'equipped and saved' in f.note(f'equip {pid} {gid}')
    if pid==priest['id']: f.note(f'preset {pid} protect')
    f.note(f'assist {pid}')
script=stage/'npc/custom/qa_encounter.txt'
script.write_text('''-	script	QA Team	-1,{
OnInit:
 bindatcmd "qateamspawn",strnpcinfo(3)+"::OnSpawn",99,99;
 bindatcmd "qateamarmor",strnpcinfo(3)+"::OnArmor",99,99;
 bindatcmd "qateamcheck",strnpcinfo(3)+"::OnCheck",99,99;
 end;
OnArmor:
 getitem 2345,1; equip 2345; end;
OnSpawn:
 getmapxy .@map$,.@x,.@y,BL_PC;
 .count=atoi(.@atcmd_parameters$[1]);
 for(.@i=0;.@i<.count;.@i++){
   monster .@map$,.@x+atoi(.@atcmd_parameters$[2])+(.@i%3),.@y+(.@i/3),"Team QA",atoi(.@atcmd_parameters$[0]),1;
   .ids[.@i]=$@mobid[0];
 }
 debugmes "QA_TEAM_FIRST "+.ids[0]; end;
OnCheck:
 .@alive=0;
 for(.@i=0;.@i<.count;.@i++) if(unitexists(.ids[.@i])) { .@alive++; getunitdata .ids[.@i],.@last; }

 if(unitexists(.ids[0])) getunitdata .ids[0],.@stats;
 debugmes "QA_TEAM_LEFT "+.@alive+" hp="+Hp+" target_hp="+.@stats[UMOB_HP]+" survivor="+.@last[UMOB_X]+","+.@last[UMOB_Y];end;
}
''')
c.command('@loadnpc npc/custom/qa_encounter.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
def stock():
    return tuple(f.db.execute('select coalesce(sum(case when nameid in (504,505) then amount end),0),coalesce(sum(case when nameid=717 then amount end),0)+(select sum(gems) from ragoff_companion) from ragoff_companion_supply').fetchone())
def fight(boss, count):
    before=stock()
    tank_actor=int(f.row(knight['id'])[11])
    tank_hits=[]
    owner_deaths=[]
    hits=set()
    last_hits=[]
    def read_combat():
        while select.select([c.s],[],[],0)[0]:
            op,b=c.packet()
            if op==0x80 and struct.unpack_from('<I',b,2)[0]==2000001 and b[6]==1:
                owner_deaths.append(time.monotonic())
            if op==0x1de:
                skill,actor,target=struct.unpack_from('<HII',b,2)
                amount=struct.unpack_from('<i',b,24)[0]
                if skill==area_id and amount>0: hits.add(target)
                if target==tank_actor and amount>0: tank_hits.append((skill,actor,amount))
                if target==2000001 and amount>0: last_hits.append((skill,actor,amount))
            if op==0x8c8:
                actor,target=struct.unpack_from('<II',b,2)
                if target==tank_actor:tank_hits.append((0,actor,struct.unpack_from('<i',b,22)[0]))
                if target==2000001:last_hits.append((0,actor,struct.unpack_from('<i',b,22)[0]))

    species=1086 if boss else int(os.environ.get('TEAM_SPECIES','1213'))
    spawn_distance=4 if species==1060 else 7
    ident=query(f'@qateamspawn {species} {count} {spawn_distance}',r'QA_TEAM_FIRST (\d+)')
    if not boss: assert 'saved' in f.note(f'mob {count}')
    mode='boss' if boss else 'mob'
    result=f.note(f'boss {ident}' if boss else 'mob on')
    assert 'ON' in result,result
    log=stage/"artifacts/map-server.log"
    offset=log.stat().st_size
    decision=[]
    deadline=time.monotonic()+(240 if boss else 100)
    while time.monotonic()<deadline:
        time.sleep(1)
        read_combat()
        alive=query('@qateamcheck',r'QA_TEAM_LEFT (\d+)')
        hp=query('@qateamcheck',r'QA_TEAM_LEFT \d+ hp=(\d+)')
        with log.open('rb') as ftrace:
            ftrace.seek(offset)
            decision=[r.decode(errors='replace') for r in ftrace if b'Companion retreat:' in r]
        if not alive or not hp or decision:break
    # The last native damage notification can arrive after the NPC queried HP.
    time.sleep(.5)
    read_combat()
    used=tuple(a-b for a,b in zip(before,stock()))
    print(mode,count,'AoE targets',len(hits),'recent hits on owner',last_hits[-5:],'alive',alive,'owner hp',hp,'potions/gems',used,flush=True)
    print('decision',decision,'recent hits on Knight',tank_hits[-6:],flush=True)
    assert hp and not alive and not owner_deaths
    if not boss: assert len(hits)>=count,(count,hits)
    assert 'off' in f.note(mode+' off')
if os.environ.get('TEAM_BOSS'):
    c.command('@qateamarmor')
    time.sleep(35)  # Give the team time to cast their ordinary pre-fight buffs.
    for n in range(3): fight(True,1)
else:
    time.sleep(25)
    for count in ([int(os.environ['TEAM_SIZE'])] if 'TEAM_SIZE' in os.environ else (5,8)): fight(False,count)
c.close()
