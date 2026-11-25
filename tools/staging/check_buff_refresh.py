"""Check proactive ally refresh, real party AoE and Heal before a higher-priority buff."""
import struct,time
from companion_ai_fixture import setup, api, wait, stage, owner

c,rows=setup(8,9)
priest,mage=rows[8],rows[9]
pid=priest['id']
path=stage/'npc/custom/qa_buff.txt'
path.write_text("""-	script	QA Buff	-1,{
OnInit:
    bindatcmd "qabuff",strnpcinfo(3)+"::OnBuff",99,99;
    end;
OnBuff:
    .@sc=SC_BLESSING;
    if (.@atcmd_parameters$[0]=="SC_INCREASEAGI") .@sc=SC_INCREASEAGI;
    if (.@atcmd_parameters$[0]=="SC_ANGELUS") .@sc=SC_ANGELUS;
    if (.@atcmd_parameters$[0]=="SC_MAGNIFICAT") .@sc=SC_MAGNIFICAT;
    .@unit=atoi(.@atcmd_parameters$[1]);
    sc_end .@sc,.@unit;
    sc_start .@sc,atoi(.@atcmd_parameters$[2]),1,10000,1,.@unit;
    end;
}
""")
c.command('@loadnpc npc/custom/qa_buff.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
def next_cast(skills,timeout=8):
    p=wait(c,lambda i,b:i==0x9cb and struct.unpack_from('<H',b,2)[0] in skills and (struct.unpack_from('<H',b,2)[0] in (33,74) or struct.unpack_from('<I',b,12)[0]==priest['actor']),timeout)
    return struct.unpack_from('<H',p,2)[0],struct.unpack_from('<I',p,8)[0]
for key,sc,skill in [('blessing','SC_BLESSING',34),('agi','SC_INCREASEAGI',29),('angelus','SC_ANGELUS',33),('magnificat','SC_MAGNIFICAT',74)]:
    api(c,f'stop {pid}')
    time.sleep(3)
    api(c,f'skills {pid} {key},heal')
    c.command(f"#heal {priest['name']}")
    c.command(f"#heal {mage['name']}")
    for actor in (owner,priest['actor'],mage['actor']):
        c.command(f'@qabuff {sc} {actor} 60000')
    duration = 5500 if skill == 74 else 2900
    c.command(f'@qabuff {sc} {mage["actor"]} {duration}')
    start=time.monotonic()
    c.command(f'@companion ui 900 assist {pid}')
    # Group skills cast on the Priest, then apply natively to each target.
    while next_cast({skill})[1]!=mage['actor']:
        assert time.monotonic()-start<duration/1000
    assert time.monotonic()-start<duration/1000, key
    print('PASS',key,'refreshed ally before expiration')
api(c,f'stop {pid}')
api(c,f'skills {pid} blessing,heal')
c.command('@set Hp 1')
c.command(f'@qabuff SC_BLESSING {owner} 600')
time.sleep(.8)
c.command(f'@companion ui 901 assist {pid}')
assert next_cast({28,34})==(28,owner)
print('PASS Heal before missing Blessing')
c.close()
