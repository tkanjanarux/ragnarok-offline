from protocol import login
from check_m6_profiles import verify_profiles
from check_m4_skills import wait
import json,pathlib,sqlite3
r=pathlib.Path('/stage');assert (r/'M6_TEST').exists()
db=sqlite3.connect(r/'ragoff-stage.sqlite3');db.execute('DELETE FROM ragoff_companion');db.execute('DELETE FROM char WHERE char_id=150004');db.commit();db.close()
c=login()
def text(c,s):return wait(c,lambda i,b:i==0x8e and s.encode() in b)
c,result=verify_profiles(c,text)
(r/'artifacts/m6-probe.json').write_text(json.dumps(result,indent=2));print(result,flush=True);c.close()
