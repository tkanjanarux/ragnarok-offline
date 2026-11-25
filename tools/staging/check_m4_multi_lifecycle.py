import time,pathlib,json
from protocol import login
from check_m4_skills import summon,wait
p=pathlib.Path('/stage/artifacts')
c=login();c.command('@setbattleflag companion_enable 1');actors=[summon(c,j) for j in ('knight','priest','wizard')];time.sleep(1);c.close()
end=time.monotonic()+15
while time.monotonic()<end:
 log=(p/'map-server.log').read_text()
 if all(f'released id={a} detached=1 timers_clear=1' in log for a in actors):break
 time.sleep(.1)
else:raise AssertionError('multi-owner logout cleanup failed')
c=login();live=[summon(c,j) for j in ('knight','priest','wizard')];time.sleep(1)
(p/'multi-shutdown-ready.json').write_text(json.dumps({'logout_cleaned':actors,'shutdown_live':live}))
try:
 while True:c.packet()
except (EOFError,ConnectionError,OSError):pass
