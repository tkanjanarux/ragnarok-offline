"""Confirm the live protocol used for visible ground units and area casts."""
import struct
from companion_ai_fixture import setup, stage, wait, warp
c,_ = setup()
warp(c, 'dew_dun02 218 259')
c.command('@killmonster2')
(stage/'npc/custom/qa_ground_spells.txt').write_text('''-	script	QA Ground Spells	-1,{
OnInit:
 bindatcmd "qagspell",strnpcinfo(3)+"::OnCast",99,99; end;
OnCast:
 monster "dew_dun02",219,259,"QA Caster",1002,1;
 .@id=$@mobid[0];
 setunitdata .@id,UMOB_MODE,MD_CANATTACK;
 unitskillusepos .@id,atoi(.@atcmd_parameters$[0]),5,224,259,-50,0,0,1;
 end;
}
''')
c.command('@setbattleflag traps_setting 0')
c.command('@loadnpc npc/custom/qa_ground_spells.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
for skill, kind in [(18,127),(12,126),(70,131),(25,133),(92,142),(117,145),(89,None),(85,None)]:
    c.command('@killmonster2')
    c.command(f'@qagspell {skill}')
    if kind is None:
        p=wait(c,lambda i,b:i==0x117 and struct.unpack_from('<H',b,2)[0]==skill)
        assert struct.unpack_from('<hh',p,10)==(224,259)
    else:
        p=wait(c,lambda i,b:i==0x9ca and struct.unpack_from('<i',b,16)[0]==kind and b[21]==1)
        assert abs(struct.unpack_from('<h',p,12)[0]-224)<=3
    print('PASS ground spell',skill,'visible unit '+str(kind) if kind else 'position cast at (224,259)',flush=True)
# With hidden traps enabled the same unit must stay hidden until revealed.
c.command('@killmonster2')
c.command('@setbattleflag traps_setting 2')
c.command('@qagspell 117')
hidden = wait(c,lambda i,b:i==0x9ca and struct.unpack_from('<i',b,16)[0]==134 and b[21]==0)
uid = struct.unpack_from('<I',hidden,4)[0]
c.command('@qagspell 130')
wait(c,lambda i,b:i==0x9ca and struct.unpack_from('<I',b,4)[0]==uid and struct.unpack_from('<i',b,16)[0]==145 and b[21]==1)
print('PASS hidden Hunter trap revealed with Detect by same unit ID', flush=True)
c.close()
