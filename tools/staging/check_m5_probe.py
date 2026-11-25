from protocol import login
from check_m4_skills import wait
from check_m5_recovery import verify_recovery,verify_skill_target
import json,pathlib
c=login()
def text(c,s):return wait(c,lambda i,b:i==0x8e and s.encode() in b)
r=verify_recovery(c,text)
r.update(verify_skill_target(c,text))
pathlib.Path('/stage/artifacts/m5-probe.json').write_text(json.dumps(r,indent=2))
print(r,flush=True)
c.close()
