"""Prepare active/dead actors for native shutdown, after M9 focused suites."""
import pathlib,json,time,socket
from protocol import login
from check_m6_profiles import api
R=pathlib.Path('/stage');assert (R/'M9_TEST').exists()
c=login();rows=api(c,'list')[0]
for r in rows[:3]:api(c,f'summon {r["id"]}')
rows=api(c,'list')[0];active=[r['actor'] for r in rows if r['actor']]
assert len(active)==3
c.command('#kill '+rows[0]['name']);time.sleep(.3)
(R/'artifacts/m9-shutdown-ready.json').write_text(json.dumps(active))
# Keep the real connection open until server shutdown; no artificial cleanup.
try:
 while True:
  try:c.packet()
  except socket.timeout:continue
except (EOFError,ConnectionResetError):pass
print('M9_SHUTDOWN_CLIENT_CLOSED',flush=True)
