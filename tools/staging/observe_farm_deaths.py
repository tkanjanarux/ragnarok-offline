"""Load a read-only native death-counter probe from the synthetic peer in a farm fixture.
The normal client only receives vanish packets for deaths within viewing distance.
Run in the same isolated namespace as check_farming_rate.py after the party spawns.
"""
import time
from pathlib import Path
from protocol import login
from check_m4_skills import wait
stage=Path('/stage')
assert (stage/'STAGING_ONLY').is_file()
src=stage/'npc/custom/qa_multibox_deaths.txt'
src.write_text('''-	script	QA Mob Planner Mortality	-1,{
OnInit:
 initnpctimer;
 end;
OnTimer2000:
 .@own=2000001;
 for(.@i=0;.@i<5;.@i++){
   .@id=.@i ? 95000000+.@i-1 : .@own;
   if(attachrid(.@id)){
     debugmes "MB_MORTALITY "+.@id+" "+readparam(PC_DIE_COUNTER);
     detachrid;
   }
 }
 setnpctimer 0;
 end;
}
''')
c=login('/stage/peer-fixture.json')
c.command('@loadnpc npc/custom/qa_multibox_deaths.txt')
wait(c,lambda op,b:op==0x8e and b'Script loaded' in b)
time.sleep(3)
c.close()
