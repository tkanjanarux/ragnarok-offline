"""Exercise the iPhone snapshot and commands across combat mode transitions."""
from nearby_hunt_fixture import c,knight,priest,mage,wait,egg
from check_m4_exp import warp
from protocol import login

sequence=5000
def frames(action, capability="team2"):
    global sequence
    sequence+=1
    cap=f'ui2 skills9 gear3 syrup1 hunter1 voice1 {capability} hunt1'
    c.command(f'@companion ui {sequence} {action} {cap}')
    prefix=f'[RCO1] {sequence} '.encode()
    out=[]
    while True:
        b=wait(c,lambda i,b:i==0x8e and b[4:].startswith(prefix))
        row=b[4+len(prefix):].rstrip(b'\0').decode().split()
        out.append(row)
        if row[0]=='end':return out

def state(action):
    return next(r[1:] for r in frames(action) if r[0]=='team')
for row in (priest,knight,mage): frames('assist '+str(row['id']))
disabled="โหมดบอสยังไม่เปิดใช้งาน"
assert all(row[0]!='team' for row in frames('list','team1'))
for action in ('boss','boss on','boss off','boss 1086'):
    c.command('@companion '+action)
    wait(c,lambda op,b:op==0x8e and disabled.encode() in b)
    assert frames(action)[-1]==['end',disabled]
assert state('list')==['assist','5']
for invalid in ('31','0','-1','5x'): assert state('mob '+invalid)==['assist','5']
assert ['team','assist','30','auto'] in frames('mob 30','loop1 puller1 team2')
assert state('list')==['assist','10']  # readable by the older app
assert state('mob 10')==['assist','10']
assert state('mob 8')==['assist','8']
for action in ('mob stop 34','mob retreat 61','mob stop 100'):
    assert 'Require' in frames(action)[-1][1]
for action in ('mob stop 65','mob retreat 40','mob retreat 35','mob stop 60'):
    assert 'Threshold' in frames(action)[-1][1]
monster=egg(155,181)
assert state(f'boss {monster}')==['assist','8']
c.command(f'@huntremove {monster}')
mvp=egg(155,181,1039)
c.command(f'@companion boss {mvp}')
wait(c,lambda op,b:op==0x8e and disabled.encode() in b)
answer=frames(f'boss {mvp}')
assert ['team','assist','8'] in answer and answer[-1]==['end',disabled]
c.command(f'@huntremove {mvp}')
assert state('mob on')==['mob','8']
modern = 'phase1 loop1 puller1 team2'
phase = [r for r in frames('list',modern) if r[0]=='phase']
assert len(phase)==1 and phase[0][1] in ('เตรียม','พัก/ถอย','ออกลาก'),phase
assert all(r[0]!='phase' for r in frames('list','loop1 puller1 team2'))
assert state('boss on')==['mob','8']
assert state('hunt on')==['mob','8']
assert state('retreat')==['retreat','8']
assert ['phase','พัก/ถอย'] in frames('list',modern)
assert state('teamoff')==['assist','8']
assert all(r[0]!='phase' for r in frames('list',modern))
assert state('hunt on')==['nearby','8']
assert state('mob on')==['nearby','8']
assert state('hunt off')==['assist','8']
assert state('mob on')==['mob','8']
warp(c,'prontera 157 184')
assert state('list')==['assist','8']
assert state('mob on')==['mob','8']
assert state('stop '+str(mage['id']))==['assist','8']
for job in (1,20,45,50):
    c.command(f'@set JobLevel {job}')
    rows=frames('inspect '+str(priest['id']))
    wards=[r for r in rows if r[0]=='skill' and r[1] in ('12','25')]
    assert len(wards)==2,rows
    print('Priest Job',job,'Safety Wall / Pneuma (id,rank,reason)',[(w[1],w[2],w[-1]) for w in wards],flush=True)
assert state('mob on')==['mob','8']
c.close()
c=login()
assert state('list')==['assist','8']
print('PASS mode exclusion, retreat, Stop, warp, login, cap and priest skill snapshot')
c.close()
