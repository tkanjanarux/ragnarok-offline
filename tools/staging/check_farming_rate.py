"""Time real EXP, deaths and consumables on an isolated copy with native map spawns.
Prepare supplies/gear and a matching owner in the fixture before starting it.
The paired run imports the first map's natural starting positions by species.
"""
import collections
import json
import os
import re
import select
import struct
import zlib
import time
from pathlib import Path
from build_fixture import BuildFixture
from check_m4_exp import warp
from companion_ai_fixture import attack
from protocol import login, entry

stage=Path('/stage')
assert (stage/'STAGING_ONLY').is_file()
field=os.environ['FARM_MAP']
mode=os.environ['FARM_MODE']
duration=int(os.environ.get('FARM_SECONDS','600'))
stationary=os.environ.get('FARM_STATIONARY')=='1'
assert field in ('alde_dun02','yuno_fild08','yuno_fild07','yuno_fild09','yuno_fild11','ra_fild01','ra_fild05','in_sphinx5','ve_fild03','dew_dun02') and mode in ('mob','assist')
measure_train=os.environ.get('FARM_HERD')=='1'
c=login()
f=BuildFixture(c)
f.db.execute('pragma busy_timeout=30000')
c.command('@setbattleflag companion_enable 1')
warp(c,'prontera 150 180')
c.command('@killmonster2')  # Clear only the fixture town before party setup.
time.sleep(.4)
f.note('party')
puller=os.environ.get('FARM_PULLER')
if puller:
    assert puller in ('priest','knight') and mode=='mob'
    if puller=='priest': assert f.note('build 1 mobber').startswith('Build: mobber')
    assert 'saved' in f.note('mob puller '+puller)
profiles=range(1,6 if os.getenv('BRAIN_FIVE')=='1' else 5)
for pid in profiles:
    reply=f.note(f'summon {pid}'); assert 'Summoned' in reply,(pid,reply)
for pid in profiles:
    f.note(f'assist {pid}')
c.send(struct.pack('<HI',0x102,1))
c.command('@heal')
warp(c,field+(' 43 24' if field=='alde_dun02' else ' 169 69' if field=='dew_dun02' else ' 143 21'))
script=stage/'npc/custom/qa_farm.txt'
log=stage/'artifacts/map-server.log'
script.write_text('''-	script	QA Farm	-1,{
OnInit:
 bindatcmd "farmobs",strnpcinfo(3)+"::OnObs",99,99;
 bindatcmd "farmpulse",strnpcinfo(3)+"::OnPulse",99,99;
 end;
OnObs:
 getmapxy .@m$,.@x,.@y,BL_PC;
 .@n=getmapunits(BL_MOB,.@m$,.@ids);
 for(.@i=0;.@i<.@n;.@i++){
  getunitdata .@ids[.@i],.@u;
  debugmes "FARMMOB "+.@ids[.@i]+" "+.@u[UMOB_CLASS]+" "+.@u[UMOB_X]+" "+.@u[UMOB_Y];
 }
 debugmes "FARMEND";end;
OnPulse:
 getmapxy .@m$,.@x,.@y,BL_PC;
 .@r=atoi(.@atcmd_parameters$[0])==2 ? max(35,atoi(.@atcmd_parameters$[2])+5) : 28;
 .@n=getareaunits(BL_MOB,.@m$,.@x-.@r,.@y-.@r,.@x+.@r,.@y+.@r,.@ids);
 .@nearest=100;
 for(.@i=0;.@i<.@n;.@i++){
  getunitdata .@ids[.@i],.@u;
  if(.@u[UMOB_CLASS]>=1078 && .@u[UMOB_CLASS]<=1085)continue;
  .@d=max(max(.@x-.@u[UMOB_X],.@u[UMOB_X]-.@x),max(.@y-.@u[UMOB_Y],.@u[UMOB_Y]-.@y));
  if(atoi(.@atcmd_parameters$[0])==2)debugmes "HERD "+.@ids[.@i]+" "+.@d+" "+.@u[UMOB_TARGETID];
  if(atoi(.@atcmd_parameters$[0])==1)debugmes "FARMFOE "+.@ids[.@i]+" "+.@u[UMOB_X]+" "+.@u[UMOB_Y]+" "+.@u[UMOB_HP];
  if(.@d>=.@nearest)continue;
  .@nearest=.@d; .@mob=.@ids[.@i]; .@tx=.@u[UMOB_X]; .@ty=.@u[UMOB_Y];
 }
 if(atoi(.@atcmd_parameters$[0])==2){getmapxy .@km$,.@kx,.@ky,BL_PC,.@atcmd_parameters$[1]; debugmes "FARMTANK "+.@kx+" "+.@ky;}
 debugmes "FARMPULSE "+BaseLevel+" "+BaseExp+" "+JobLevel+" "+JobExp+" "+Hp+" "+.@mob+" "+.@nearest+" "+.@tx+" "+.@ty+" "+.@x+" "+.@y+" "+NextBaseExp+" "+NextJobExp;
 end;
}
''')
def query(cmd, terminator):
    offset=log.stat().st_size
    c.command(cmd)
    for attempt in range(400):
        if attempt and attempt%100==0: c.command(cmd)  # Read-only probe can be retried.
        with log.open('rb') as stream:
            stream.seek(offset)
            text=stream.read().decode(errors='replace')
        if terminator in text:return text
        time.sleep(.05)
    raise RuntimeError((cmd,text[-900:]))
c.command('@loadnpc npc/custom/qa_farm.txt')
time.sleep(.3)
obs=query('@farmobs','FARMEND')
mobs=[tuple(map(int,m)) for m in re.findall(r'FARMMOB (\d+) (\d+) (\d+) (\d+)',obs)]
assert len(mobs)>70,len(mobs)
def load_cells():
    for path in ('db/import/map_cache.dat','db/re/map_cache.dat','db/map_cache.dat'):
        data=(stage/path).read_bytes()
        pos=8
        while pos<len(data):
            name,width,height,size=struct.unpack_from('<12shhi',data,pos)
            pos+=20
            if name.split(bytes(1))[0].decode()==field:
                return width,height,zlib.decompress(data[pos:pos+size])
            pos+=size
    raise ValueError(field)
width,height,cells=load_cells()
def open_cell(x,y):
    return 0<=x<width and 0<=y<height and cells[y*width+x] in (0,2,3,4,6)
layout=stage/'artifacts/farm-layout.json'
if mode=='mob' and not layout.exists():
    types=(1213,1211,1194) if field=='alde_dun02' else {'ra_fild01':(1106,), 'ra_fild05':(1135,), 'in_sphinx5':(1154,), 've_fild03':(1836,), 'dew_dun02':(2154,)}.get(field,(1369,1372))
    choices=[(x,y) for _,k,x,y in mobs if k in types]
    anchor=max(choices,key=lambda p:sum(max(abs(x-p[0]),abs(y-p[1]))<=22 for x,y in choices))
    margin=int(os.environ.get('FARM_MARGIN','0'))
    if margin:
        live=[(x,y) for _,k,x,y in mobs if not 1078<=k<=1085]
        score=-1
        for x in range(8,width-8,4):
            for y in range(8,height-8,4):
                if not all(open_cell(x+dx,y+dy) for dx in (-2,0,2) for dy in (-2,0,2)):continue
                if any(max(abs(mx-x),abs(my-y))<margin for mx,my in live):continue
                n=sum(max(abs(mx-x),abs(my-y))<=30 for mx,my in choices)
                if n>score:anchor,score=(x,y),n
        assert score>=2,score
    if field=='dew_dun02':anchor=(169,69)
    layout.write_text(json.dumps([anchor,sorted(mobs)]))
else:
    for _ in range(160):
        if layout.exists():break
        time.sleep(.25)
    anchor,original=json.loads(layout.read_text())
    by_type=collections.defaultdict(list)
    for _,k,x,y in original:by_type[k].append((x,y))
    restore=stage/'npc/custom/qa_farm_positions.txt'
    lines=['-\tscript\tQA Farm Positions\t-1,{','OnInit:']
    for gid,k,_,_ in sorted(mobs):
        if by_type[k]:
            x,y=by_type[k].pop()
            lines.append(f'unitwarp {gid},"{field}",{x},{y};')
    lines+=['end;','}']
    restore.write_text('\n'.join(lines)+'\n')
    c.command('@loadnpc npc/custom/qa_farm_positions.txt')
    time.sleep(.4)
warp(c,f'{field} {anchor[0]} {anchor[1]}')
c.command('@set BaseExp 0')
c.command('@set JobExp 0')
def stock():
    items=dict(f.db.execute('select nameid,sum(amount) from ragoff_companion_supply group by nameid'))
    items[717]=items.get(717,0)+f.db.execute('select coalesce(sum(gems),0) from ragoff_companion').fetchone()[0]
    return items
before=stock()
if mode=='mob':
    assert 'saved' in f.note('mob radius '+os.environ.get('FARM_RADIUS','28'))
    assert 'saved' in f.note('mob '+os.environ.get('FARM_CAP','5'))
    assert 'ON' in f.note('mob on')
def visible(x,y,tx,ty):
    steps=max(abs(tx-x),abs(ty-y),1)
    return all(cells[round(y+(ty-y)*i/steps)*width+round(x+(tx-x)*i/steps)]!=1 for i in range(1,steps))
def approach(x,y,tx,ty,max_steps=32):
    todo=collections.deque([(x,y,None,0)])
    seen={(x,y)}
    while todo:
        cx,cy,waypoint,n=todo.popleft()
        if max(abs(tx-cx),abs(ty-cy))<=9 and visible(cx,cy,tx,ty):return waypoint
        if n>=max_steps:continue
        for dx,dy in ((0,1),(0,-1),(1,0),(-1,0),(1,1),(1,-1),(-1,1),(-1,-1)):
            q=(cx+dx,cy+dy)
            if q in seen or not open_cell(*q) or not open_cell(cx+dx,cy) or not open_cell(cx,cy+dy):continue
            seen.add(q)
            todo.append((*q,q if n<8 else waypoint,n+1))
    return None
actors={int(f.row(pid)[11]) for pid in profiles}
tank_row=f.row(1 if puller=="priest" else 2)
tank_id=int(tank_row[11])
tank_name=tank_row[14]
tagged=set()
arrived=set()
return_times=[]
peak_distance=0
peak_time=0
deaths=collections.Counter()
hits=collections.Counter()
field_offset=log.stat().st_size
start=time.monotonic()
base=job=0
base_offset=job_offset=0
old_base,old_job=f.db.execute('select base_level,job_level from char where char_id=(select owner_char from ragoff_companion where id=2)').fetchone()
old_base_max=old_job_max=0
target=0
last_move=None
last_walk=last_attack=0
last_target=last_hp=idle_since=0
ignored={}
patrol=[(x,y) for _,_,x,y in mobs]
patrol_index=0
patrol_goal=None
patrol_until=0
while time.monotonic()-start<duration:
    line=query('@farmpulse '+('1' if mode=='assist' else f"2 {tank_name} {int(os.environ.get('FARM_RADIUS','30'))}" if measure_train else '0'),'FARMPULSE ')
    lvl,base,jlvl,job,hp,mob,dist,x,y,px,py,base_max,job_max=map(int,re.search(r'FARMPULSE ([0-9 ]+)',line)[1].split())
    if measure_train:
        kx,ky=map(int,re.search(r'FARMTANK (\d+) (\d+)',line).groups())
        assert kx>0 and ky>0, 'Knight position unavailable'
        gap=max(abs(kx-anchor[0]),abs(ky-anchor[1]))
        if gap>=peak_distance and gap>7:
            peak_distance,peak_time=gap,time.monotonic()
        elif gap<=4 and peak_distance:
            return_times.append(round(time.monotonic()-peak_time,2))
            peak_distance=0
        for mid,dist,victim in re.findall(r'HERD (\d+) (\d+) (\d+)',line):
            mid,dist,victim=map(int,(mid,dist,victim))
            if dist>7 and victim==tank_id:tagged.add(mid)
            if dist<=7 and mid in tagged:arrived.add(mid)
    if lvl>old_base:
        assert lvl==old_base+1 and old_base_max>0
        base_offset+=old_base_max
    if jlvl>old_job:
        assert jlvl==old_job+1 and old_job_max>0
        job_offset+=old_job_max
    base+=base_offset
    job+=job_offset
    old_base,old_job,old_base_max,old_job_max=lvl,jlvl,base_max,job_max
    if mode=='assist' and hp:
        now=time.monotonic()
        choices=[tuple(map(int,m)) for m in re.findall(r'FARMFOE (\d+) (\d+) (\d+) (\d+)',line)]
        choices.sort(key=lambda m:max(abs(m[1]-px),abs(m[2]-py)))
        mob=0
        step=None
        for candidate,tx,ty,health in choices:
            if not health or ignored.get(candidate,0)>now:continue
            dist=max(abs(tx-px),abs(ty-py))
            can_shoot=dist<=13 and visible(px,py,tx,ty)
            if stationary and not can_shoot:continue
            step=None if can_shoot else approach(px,py,tx,ty)
            if not can_shoot and not step:continue
            if candidate!=last_target or health!=last_hp:
                last_target,last_hp,idle_since=candidate,health,now
            elif now-idle_since>=8:
                ignored[candidate]=now+18
                continue
            mob=candidate
            break
        if not mob and not stationary:
            # Walk the map when the patch is empty. Choose a nearby reachable
            # waypoint from the natural spawn survey, never warp during a run.
            if patrol_goal and now<patrol_until:
                step=approach(px,py,*patrol_goal,96)
            if not step:
                patrol_goal=None
                for n in range(len(patrol)):
                    tx,ty=patrol[patrol_index%len(patrol)]
                    patrol_index+=1
                    if 35<=max(abs(tx-px),abs(ty-py))<=85:
                        step=approach(px,py,tx,ty,96)
                        if step:
                            patrol_goal=(tx,ty)
                            patrol_until=now+20
                            break
        else:
            patrol_goal=None
        if mob and can_shoot:
            if mob!=target or now-last_attack>2:
                attack(c,mob)
                use,_=entry('clif_parse_UseSkillToId')
                c.send(struct.pack('<HHHI',use,10,46,mob))
                target=mob;last_attack=time.monotonic()
        elif step:
            if (last_move!=step or time.monotonic()-last_walk>2):
                wx,wy=step
                walk,desc=entry('clif_parse_WalkToXY')
                frame=bytearray(desc['length'])
                struct.pack_into('<H',frame,0,walk)
                i=desc['offsets'][0]
                frame[i:i+3]=bytes([wx>>2,((wx&3)<<6)|(wy>>4),(wy&15)<<4])
                c.send(frame)
                last_move=step;last_walk=time.monotonic();target=0
    until=time.monotonic()+.85
    while time.monotonic()<until:
        if not select.select([c.s],[],[],max(0,until-time.monotonic()))[0]:break
        op,b=c.packet()
        if op==0x80 and b[6]==1:deaths[struct.unpack_from('<I',b,2)[0]]+=1
        if op==0x1de and struct.unpack_from('<i',b,24)[0]>0:
            skill,actor,_=struct.unpack_from('<HII',b,2)
            if actor in actors:hits[skill]+=1
    if int(time.monotonic()-start)%30==0:print('sample',base,job,hp,flush=True)
after=stock()
with log.open("rb") as trace:
    trace.seek(field_offset)
    storm_fields=len(re.findall(rb"Mob field landed wizard=\d+ skill=89 ", trace.read()))
print(json.dumps(dict(mode=mode,field=field,anchor=anchor,seconds=round(time.monotonic()-start),base=base,job=job,storm_fields=storm_fields,
    **({'tagged':len(tagged),'arrived':len(arrived),'return_seconds':return_times} if measure_train else {}),owner_deaths=deaths[2000001],companion_deaths=sum(deaths[i] for i in actors),hits=hits,
    used={k:v-after.get(k,0) for k,v in before.items() if v!=after.get(k,0)})),flush=True)
c.close()
