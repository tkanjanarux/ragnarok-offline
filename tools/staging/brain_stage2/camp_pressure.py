"""Independent stress scenario. Native High Orcs reach the Wizard while the puller is away."""
from pathlib import Path
p=Path('/tests/brain_stage2/fixture.py')
import os
s=p.read_text()
if os.getenv('BRAIN_LATE_PRESSURE')=='1':
    s=s.replace('sent_scene=False','sent_scene=False\nlap_out=False\nlap_returned=False')
    s=s.replace('            dest=vals[8:10]', '''            gap=max(abs(vals[2]-anchor[0]),abs(vals[3]-anchor[1]))
            lap_out=lap_out or gap>9
            lap_returned=lap_returned or (lap_out and gap<=5)
            dest=vals[8:10]''').replace('if max(abs(dest[0]', 'if lap_returned and elapsed>=45 and max(abs(dest[0]')
s=s.replace('                ev=stage/',"""                wiz=re.findall(r'B_A \\\\d+ 95000002 (.+)',snap)
                wx,wy=map(int,wiz[-1].split()[2:4])
                ev=stage/""")
s=s.replace("str(anchor[0])+','+str(anchor[1])","str(wx)+','+str(wy)").replace('1213,5;', '1213,12;')
if os.getenv('BRAIN_APPROACH')=='1':
    # Spawn on an open approach lane. Native movement and aggro determine contact.
    s=s.replace("str(wx)+','+str(wy)", "str(anchor[0])+','+str(anchor[1])").replace('1213,12;', '1213,3;')
exec(compile(s,str(p),'exec'))
