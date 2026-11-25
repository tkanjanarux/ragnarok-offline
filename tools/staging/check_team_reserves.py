"""Low SP pauses new pulls; critical HP and healer loss trigger a team retreat."""
import time
from nearby_hunt_fixture import c,knight,mage,priest,stage,wait,egg,hp
from build_fixture import BuildFixture

f=BuildFixture(c)
f.note(f'bench {mage["id"]}')
c.command('@set BaseLevel 85')
c.command('@set JobLevel 45')
f.select(mage['id'],'storm')
f.note(f'summon {mage["id"]}')
for row in (knight,priest,mage):f.note(f'assist {row["id"]}')
actor={row['id']:f.row(row['id'])[11] for row in (knight,priest,mage)}
script=stage/'npc/custom/qa_team_vitals.txt'
script.write_text('''-	script	QA Team Vitals	-1,{
OnInit: bindatcmd "qateamv",strnpcinfo(3)+"::OnRun",99,99; end;
OnRun:
 .@a=atoi(.@atcmd_parameters$[0]); .@h=atoi(.@atcmd_parameters$[1]); .@s=atoi(.@atcmd_parameters$[2]);
 if(!attachrid(.@a)) end;
 if(.@h==0) { percentheal -100,0; end; }
 Hp=MaxHp*.@h/100; Sp=MaxSp*.@s/100; end;
}
''')
c.command('@loadnpc npc/custom/qa_team_vitals.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
def vitals(row,h,s):
    c.command(f'@qateamv {actor[row["id"]]} {h} {s}')
def mode():
    f.seq+=1
    c.command(f'@companion ui {f.seq} list ui2 team2 hunt1')
    prefix=f'[RCO1] {f.seq} team '.encode()
    return wait(c,lambda i,b:i==0x8e and prefix in b)[4:].split()[-2]
for who in (priest,mage):
    for row in (knight,priest,mage): vitals(row,100,100)
    vitals(who,100,0)
    target=egg(156,180)
    c.command('@companion mob on')
    shortage = 'Priest เหลือไม่พอฮีล' if who is priest else 'Wizard ไม่พอร่ายวง'
    wait(c,lambda i,b:i==0x8e and shortage.encode() in b)
    wait(c,lambda i,b:i==0x8e and b'Mob mode ON.' in b)
    time.sleep(2)
    assert mode()==b'mob' and hp(target)==60000
    f.note('mob off')
    c.command(f'@huntremove {target}')
for row in (knight,priest,mage):vitals(row,100,100)
assert f.note('mob on')=='Mob mode ON.'
vitals(knight,20,100)
time.sleep(1)
assert mode()==b'retreat'
f.note('mob off')
vitals(knight,100,100)
assert f.note('mob on')=='Mob mode ON.'
vitals(priest,0,100)
time.sleep(1)
assert mode()==b'retreat'
print('PASS Priest/Wizard SP reserves, Knight critical HP and Priest death')
c.close()
