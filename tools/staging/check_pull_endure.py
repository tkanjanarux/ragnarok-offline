"""Check native Endure charges, renewal on a pull, and individual skill settings."""
import time
from nearby_hunt_fixture import c, knight, mage, priest, stage, query, wait
from build_fixture import BuildFixture

assert (stage/'STAGING_ONLY').is_file()
f=BuildFixture(c)
c.command('@set BaseLevel 88')
c.command('@set JobLevel 47')
c.command('@setbattleflag min_hitrate 100')
f.note(f'bench {mage["id"]}')
f.select(mage['id'],'storm')
f.note(f'summon {mage["id"]}')
for member in (knight,priest,mage):
    f.note(f'assist {member["id"]}')
f.note(f'skills {knight["id"]} endure,provoke')
kid=int(f.row(knight['id'])[11])
level=f.ranks(knight['id'])[8]
assert level>0
script=stage/'npc/custom/qa_pull_endure.txt'
script.write_text('''-	script	QA Endure	-1,{
OnInit:
 bindatcmd "qaendure",strnpcinfo(3)+"::OnRead",99,99;
 bindatcmd "qaendoff",strnpcinfo(3)+"::OnClear",99,99;
 bindatcmd "qatap",strnpcinfo(3)+"::OnTap",99,99;
 bindatcmd "qalure",strnpcinfo(3)+"::OnLure",99,99;end;
OnClear: sc_end SC_ENDURE,KID;debugmes "ENDCLEARED "+getstatus(SC_ENDURE,2,KID);end;
OnRead: debugmes "ENDURE "+getstatus(SC_ENDURE,2,KID);end;
OnTap:
 getmapxy .@map$,.@x,.@y,BL_PC,"KNAME";
 monster "prontera",.@x+1,.@y,"QA tap",1002,1;
 .@m=$@mobid[0];unitwarp .@m,"prontera",.@x+1,.@y;
 setunitdata .@m,UMOB_MAXHP,200000; setunitdata .@m,UMOB_HP,200000;
 setunitdata .@m,UMOB_DEX,999;
 unitattack .@m,KID,1;
 unitskilluseid .@m,"NPC_GUIDEDATTACK",1,KID,0;
 end;
OnLure:
 monster "prontera",177,180,"QA pull",1369,1;
 .@m=$@mobid[0];unitwarp .@m,"prontera",177,180;
 debugmes "NEW LURE "+.@m;end;
}
'''.replace('KID',str(kid)).replace('KNAME',knight['name']))
c.command('@loadnpc npc/custom/qa_pull_endure.txt')
wait(c,lambda op,b:op==0x8e and b'Script loaded' in b)
def charges():
    return query('@qaendure',r'ENDURE (\d+)')
def until(check,seconds=8):
    end=time.monotonic()+seconds
    while not check():
        assert time.monotonic()<end
        time.sleep(.1)
def lure():
    return query('@qalure',r'NEW LURE (\d+)')
f.note('mob radius 40')
f.note('mob 1')
lure()
assert 'ON' in f.note('mob on')
until(lambda:charges()==7)
first=time.monotonic()
f.note('mob off')
c.command('@killmonster2')
# Deliver five real monster hits, leaving an active, nearly exhausted buff.
c.command('@qatap')
until(lambda:charges()<=2,20)
c.command('@killmonster2')
assert charges()==2
time.sleep(max(0,first+11-time.monotonic()))
assert charges()==2
lure()
assert 'ON' in f.note('mob on')
until(lambda:charges()==7,4)
assert time.monotonic()-first<28  # The level-7 effect has not expired.
f.note('mob off')
c.command('@killmonster2')
f.note(f'skills {knight["id"]} provoke')
assert query('@qaendoff',r'ENDCLEARED (\d+)')==0
time.sleep(11)
lure()
offset=(stage/'artifacts/map-server.log').stat().st_size
assert 'ON' in f.note('mob on')
until(lambda:'role=pack' in (stage/'artifacts/map-server.log').read_bytes()[offset:].decode(),20)
assert charges()==0
print('PASS disabled Endure stayed off while Knight engaged the new pull')
print('PASS Knight Endure level',level,'seven native charges, two remaining refreshed before expiration')
c.close()
