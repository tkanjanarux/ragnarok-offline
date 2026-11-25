"""Compare the actual Base/Job EXP packets for the same kill solo and with four active careers."""
import sqlite3
import struct
import time
from nearby_hunt_fixture import c, knight, mage, priest, api, stage, query, wait, chat
from check_m4_exp import drain,warp
from companion_ai_fixture import attack
from protocol import login,entry

for row in (knight,mage,priest):api(c,f"bench {row['id']}")
assert 'Recruited' in api(c,'recruit hunter')[1]
db=sqlite3.connect(stage/'ragoff-stage.sqlite3',isolation_level=None)
hunter,owner=db.execute('select id,owner_char from ragoff_companion where job=11').fetchone()
db.execute('insert into ragoff_companion_supply values(?,?,1750,100)',(hunter,owner))
c.command('@set BaseLevel 80')
c.command('@allskill')
c.command('@dex 200')
c.command('@str 99')
c.command('@heal')
peer=login(str(stage/'peer-fixture.json'))
peer.command('@jobchange 7')
peer.command('@set BaseLevel 80')
peer.command('@set JobLevel 40')
warp(peer,'prontera 70 70')
c.send(struct.pack('<HI',0xfc,2000002))
packet=wait(peer,lambda i,b:i==0x2c6)
peer.send(struct.pack('<HIB',0x2c7,struct.unpack_from('<I',packet,2)[0],1))
wait(c,lambda i,b:i==0xae5 and b'StagePeer' in b)
fixture=stage/'npc/custom/qa_four_exp.txt'
fixture.write_text('''-	script	QA Four EXP	-1,{
OnInit: bindatcmd "fourtarget",strnpcinfo(3)+"::OnSpawn",99,99; end;
OnSpawn:
 getmapxy(.@map$,.@x,.@y,BL_PC); monster .@map$,.@x,.@y,"EXP test",1369,1;
 .@id=$@mobid[0]; setunitdata .@id,UMOB_MODE,MD_NOCAST;
 setunitdata .@id,UMOB_MAXHP,1; setunitdata .@id,UMOB_HP,1;
 unitwarp .@id,.@map$,.@x,.@y;
 debugmes "FOUR_TARGET "+.@id; end;
}
''')
c.command('@loadnpc npc/custom/qa_four_exp.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
baseline={}
for team in (False,True):
    if team:
        for pid in (knight['id'],priest['id'],mage['id'],hunter):
            assert 'Summoned' in api(c,f'summon {pid}')[1]
    for share in (0,1):
        c.send(struct.pack('<HI',0x102,share))
        time.sleep(.4)
        for player in (c,peer):
            player.command('@set BaseExp 0')
            player.command('@set JobExp 0')
            drain(player)
            player.params[1]=player.params[2]=0
        mob=query('@fourtarget',r'FOUR_TARGET (\d+)')
        if team:c.command('@companion hunt on')
        else:
            warp(c,'prontera 150 180')
            use,_=entry('clif_parse_UseSkillToId')
            c.send(struct.pack('<HHHI',use,5,5,mob))
            attack(c,mob)
        wait(c,lambda i,b:i==0x80 and struct.unpack_from('<I',b,2)[0]==mob and b[6]==1,25)
        if team:chat('hunt off')
        time.sleep(.4)
        drain(c);drain(peer)
        exp=tuple((player.params[1],player.params[2]) for player in (c,peer))
        assert min(exp[0])>0 and (min(exp[1])>0)==bool(share),exp
        if team:assert exp==baseline[share],(share,exp,baseline)
        else:baseline[share]=exp
        print('PASS',team,share,'owner/peer Base and Job EXP',exp,flush=True)
assert db.execute('select count(*) from ragoff_companion where base_exp!="0" or job_exp!="0"').fetchone()==(0,)
peer.close();c.close()
