"""A single real bow shot at twelve cells must bring both damage companions into range."""
import re
import socket
import struct
import time

from companion_ai_fixture import setup, api, wait, stage, spawn, owner
from check_m4_exp import warp
from protocol import entry

c, party = setup(7,9)
c.command('@jobchange 3')
c.command('@set JobLevel 44')
c.command('@allskill')
fixture = stage/'npc/custom/qa_archer_assist.txt'
fixture.write_text("""-	script	QA Archer Assist	-1,{
OnInit:
 bindatcmd "qabow",strnpcinfo(3)+"::OnBow",99,99;
 bindatcmd "qamelee",strnpcinfo(3)+"::OnMelee",99,99;
 bindatcmd "qaequip",strnpcinfo(3)+"::OnEquip",99,99;
 bindatcmd "qadistance",strnpcinfo(3)+"::OnDistance",99,99;
 bindatcmd "qaegg",strnpcinfo(3)+"::OnEgg",99,99;
 end;
OnBow:
 getitem 1701,1; equip 1701; getitem 1750,100; equip 1750; end;
OnMelee:
 unequip EQI_HAND_R; end;
OnEquip:
 equip 1701; equip 1750; end;
OnDistance:
 getmapxy(.@map$,.@x,.@y,BL_PC);
 getunitdata atoi(.@atcmd_parameters$[0]),.@target;
 debugmes "QA positions "+.@x+" "+.@y+" "+.@target[UMOB_X]+" "+.@target[UMOB_Y]; end;
OnEgg:
 .@m=atoi(.@atcmd_parameters$[0]);
 setunitdata .@m,UMOB_MODE,MD_NOCAST;
 setunitdata .@m,UMOB_MAXHP,60000; setunitdata .@m,UMOB_HP,60000;
 unitwarp .@m,"prontera",150,180; end;
}
""")
c.command('@loadnpc npc/custom/qa_archer_assist.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
c.command('@qabow')
knight,mage=party[7],party[9]
for companion,skills in ((knight,'none'),(mage,'firebolt')):
    api(c,f"skills {companion['id']} {skills}")
    api(c,f"assist {companion['id']}")
mob,_,_=spawn(c,1097)
c.command(f'@qaegg {mob}')
warp(c,'prontera 150 192')
time.sleep(1)
action,_=entry('clif_parse_ActionRequest')
seen=set()
def damage(code,p):
    if code==0x8c8:
        src,dst=struct.unpack_from('<II',p,2)
        if dst==mob and src in (owner,knight['actor']):
            if src!=owner:assert owner in seen,'Knight attacked before owner'
            seen.add(src)
    if code==0x1de and struct.unpack_from('<HII',p,2)==(46,owner,mob):
        seen.add(owner)
    if code==0x1de and struct.unpack_from('<HII',p,2)==(19,mage['actor'],mob):
        assert owner in seen,'Mage attacked before owner'
        seen.add(mage['actor'])
    return len(seen)==3
for style in ('single','auto','Double Strafe'):
    if style!='single':
        c.command('@killmonster2')
        mob,_,_=spawn(c,1097)
        c.command(f'@qaegg {mob}')
    warp(c,'prontera 150 192')
    c.command('@qamelee')
    c.send(struct.pack('<HIB',action,mob,7))
    wait(c,lambda i,b:i==0x139 and struct.unpack_from('<I',b,2)[0]==mob)
    c.s.settimeout(.2)
    try:
        deadline=time.monotonic()+1.6
        while time.monotonic()<deadline:
            try:code,packet=c.packet()
            except socket.timeout:continue
            assert not damage(code,packet) and not seen,'damage before owner came within range'
    finally:
        c.s.settimeout(10)
    c.command('@qaequip')
    log=stage/'artifacts/map-server.log'
    offset=log.stat().st_size
    c.command(f'@qadistance {mob}')
    for _ in range(40):
        with log.open('rb') as f:
            f.seek(offset)
            coords=re.search(rb'QA positions (\d+) (\d+) (\d+) (\d+)',f.read())
        if coords:break
        time.sleep(.05)
    assert coords
    x,y,mx,my=map(int,coords.groups())
    assert max(abs(x-mx),abs(y-my))==12,(x,y,mx,my)
    if style=='Double Strafe':
        use,_=entry('clif_parse_UseSkillToId')
        c.send(struct.pack('<HHHI',use,1,46,mob))
    else:
        c.send(struct.pack('<HIB',action,mob,0 if style=='single' else 7))
    try:wait(c,damage,15)
    except (AssertionError,socket.timeout) as exc:
        raise AssertionError((style,'owner/Mage/Swordman hits',owner in seen,mage['actor'] in seen,knight['actor'] in seen)) from exc
    print('PASS',style,'at 12 cells: owner, Mage Fire Bolt and Swordman melee on the same target',flush=True)
    seen.clear()
c.close()
