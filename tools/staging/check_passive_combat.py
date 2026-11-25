"""A/B native damage with and without the learned rank on the same isolated actor."""
import struct
import time
from nearby_hunt_fixture import c, egg, query, api, knight, mage, priest, stage, wait
from check_ai_guard import target_mob_command
from check_m8_gear import held, slot, transfer

c.command('@set BaseLevel 90')
c.command('@setbattleflag min_hitrate 100')
c.command('@jobchange 3')
c.command('@set JobLevel 50')
c.command('@jobchange 11')
c.command('@set JobLevel 50')
time.sleep(1)
path=stage/'npc/custom/qa_mastery.txt'
path.write_text("""-	script	QA Mastery	-1,{
OnInit:
 bindatcmd "qapass",strnpcinfo(3)+"::OnPass",99,99;
 bindatcmd "qastrike",strnpcinfo(3)+"::OnStrike",99,99;
 bindatcmd "qafixedhit",strnpcinfo(3)+"::OnFixed",99,99;
 bindatcmd "qamob",strnpcinfo(3)+"::OnMob",99,99; end;
OnPass:
 .@actor=atoi(.@atcmd_parameters$[0]); .@id=atoi(.@atcmd_parameters$[1]);
 .@lv=atoi(.@atcmd_parameters$[2]);
 if (!attachrid(.@actor)) end;
 if (.@lv>=0) skill .@id,.@lv,SKILL_PERM_GRANT;
 sc_start SC_MAXIMIZEPOWER,120000,1;
 debugmes "QA_PASS "+getskilllv(.@id); end;
OnStrike:
 unitattack atoi(.@atcmd_parameters$[0]),atoi(.@atcmd_parameters$[1]),1; end;
OnFixed:
 .@m=atoi(.@atcmd_parameters$[0]);
 sc_end SC_MAXIMIZEPOWER,.@m;
 sc_start SC_MAXIMIZEPOWER,120000,1,10000,1,.@m;
 end;
OnMob:
 .@m=atoi(.@atcmd_parameters$[0]);
 setunitdata .@m,UMOB_RACE,RC_DEMON;
 setunitdata .@m,UMOB_ATKMIN,400;
 setunitdata .@m,UMOB_ATKMAX,400;
 setunitdata .@m,UMOB_HIT,500;
 setunitdata .@m,UMOB_DEF,0;
 setunitdata .@m,UMOB_CRIT,0;
 sc_start SC_MAXIMIZEPOWER,120000,1,10000,1,.@m;
 end;
}
""")
c.command('@loadnpc npc/custom/qa_mastery.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
target_mob_command(c)
def rank(actor,sk,level):
    return query(f'@qapass {actor} {sk} {level}',r'QA_PASS (\d+)')
def hit(src,dst):
    seen=[]
    def match(i,b):
        if i!=0x8c8:return False
        pair=struct.unpack_from('<II',b,2)
        d=struct.unpack_from('<i',b,22)[0]
        seen.append((pair,b[29],d))
        return pair==(src,dst) and b[29] not in (10,11) and d>1
    try:p=wait(c,match,12)
    except AssertionError as e:raise AssertionError((src,dst,seen[-12:])) from e
    return struct.unpack_from('<i',p,22)[0]
def damage(src,dst):
    # The native action handler rejects swings during the previous attack's delay.
    for _ in range(5):
        time.sleep(1.2)
        c.command(f'@qastrike {src} {dst}')
        try:
            p=wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(src,dst) and b[29]==0 and struct.unpack_from('<i',b,22)[0]>0,2)
            return struct.unpack_from('<i',p,22)[0]
        except AssertionError:pass
    raise AssertionError(('no scripted normal attack',src,dst))
def stop(member):api(c,f"stop {member['id']}")
def bench(member):assert 'reserve' in api(c,f"bench {member['id']}")[1]
bench(mage)
bench(priest)
bench(knight)
weapons={}
for item in (1157,1401):
    c.command(f'@item {item} 1')
    transfer(c,knight['id'],slot(c,item))
    weapons[item]=held(knight['id'])[-1][0]
def summon(member):
    assert 'Summoned' in api(c,f"summon {member['id']}")[1]
    stop(member)
    return next(r['actor'] for r in api(c,'list')[0] if r['id']==member['id'])
actor=summon(knight)
api(c,f"skills {knight['id']} none")
for skill,item in [(2,None),(3,1157),(55,1401)]:
    if item:assert 'equipped and saved' in api(c,f"equip {knight['id']} {weapons[item]}")[1]
    learned=rank(actor,skill,-1)
    assert learned>1
    mob=egg(151,180)
    c.command(f'@qamob {mob}')
    c.command('@companion hunt on')
    trained=hit(actor,mob)
    assert rank(actor,skill,0)==0
    # Drain packets queued before the test rank was changed.
    api(c,'list')
    baseline=hit(actor,mob)
    assert trained-baseline==4*learned,(skill,learned,trained,baseline)
    assert rank(actor,skill,learned)==learned
    print('PASS native mastery',skill,trained,baseline,flush=True)
    stop(knight)
    c.command('@killmonster2')
    time.sleep(1.5)
bench(knight)
actor=summon(priest)
api(c,f"skills {priest['id']} none")
api(c,f"assist {priest['id']}")
mob=egg(151,180,1132)
c.command(f'@qamob {mob}')
c.command(f"@aiguard {mob} {actor} {priest['name']}")
api(c,'list')
c.command(f'@qafixedhit {mob}')
api(c,'list')
trained=hit(mob,actor)
dp=rank(actor,22,-1)
rank(actor,22,0)
api(c,'list')
c.command(f'@qafixedhit {mob}')
api(c,'list')
baseline=hit(mob,actor)
assert baseline-trained==int((90/25+3)*dp+.5),(trained,baseline,dp)
print('PASS Divine Protection',trained,baseline,flush=True)
rank(actor,22,dp)
c.command('@killmonster2')
c.command(f"#heal {priest['name']}")
time.sleep(1)
mob=egg(151,180)
c.command(f'@qamob {mob}')
c.command(f"@aiguard {mob} {actor} {priest['name']}")
time.sleep(.6)
bane=rank(actor,23,-1)
trained=damage(actor,mob)
rank(actor,23,0)
api(c,'list')
baseline=damage(actor,mob)
assert trained-baseline==int((90/20+3)*bane),(trained,baseline,bane)
print('PASS Demon Bane',trained,baseline,flush=True)
c.close()
print('PASS passive combat',flush=True)
