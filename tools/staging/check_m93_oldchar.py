import pathlib,time,json
from protocol import login
from check_m6_profiles import api
from check_m4_skills import wait
from check_m8_gear import query
R=pathlib.Path('/stage');assert (R/'M9_TEST').exists()
c=login();c.command('@setbattleflag companion_enable 1');c.command('@item 501 10');rows=api(c,'recruit knight')[0];pid=rows[0]['id']
frames=[];orig=c.packet
def packet():
 i,b=orig()
 if i==0x8e and b'supplybag' in b:frames.append(b[4:].decode().strip('\0').split())
 return i,b
c.packet=packet;api(c,f'inspect {pid}');c.packet=orig;t=next(t for t in frames if t[4]=='501')
assert 'Waiting' in api(c,f'supplygive {pid} {t[3]}:501:{t[5]}:5')[1]
wait(c,lambda i,b:i==0x8e and b'Supply transfer cancelled' in b)
assert query('SELECT amount FROM inventory WHERE nameid=501')==[(10,)]
assert not query('SELECT * FROM ragoff_companion_supply') and not query('SELECT * FROM ragoff_companion_supply_journal')
c.close();(R/'artifacts/m93-oldchar.json').write_text(json.dumps(dict(old_char_capability_rejected=True,player_potions_unchanged=10,supplies_unchanged=True)));print('OLD_CHAR_TRANSFER_REJECTED_NO_MUTATION')
