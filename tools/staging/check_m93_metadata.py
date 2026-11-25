"""Native favorite stacks must never be merged into by a supply return."""
import pathlib,time,json,struct
from protocol import login
from check_m6_profiles import api
from check_m4_skills import wait
from check_m8_gear import query
R=pathlib.Path('/stage');assert (R/'M9_TEST').exists()
c=login();c.command('@setbattleflag companion_enable 1');kid=next(r['id'] for r in api(c,'list')[0] if r['job']==7)
frames=[];orig=c.packet
def packet():
 i,b=orig()
 if i==0x8e and b'supplybag' in b:frames.append(b[4:].decode().strip('\0').split())
 return i,b
c.packet=packet;api(c,f'inspect {kid}');c.packet=orig;t=next(x for x in frames if x[4]=='501');slot=int(t[3]);amount=int(t[5])
# Native inventory tab packet: client index = server zero-based index +2.
c.send(struct.pack('<HHB',0x907,slot+1,0));wait(c,lambda i,b:i==0x908)
stock=query('SELECT amount FROM ragoff_companion_supply WHERE profile_id=? AND nameid=501',(kid,))[0][0]
assert 'Waiting' in api(c,f'supplytake {kid} 0:501:0:1')[1]
wait(c,lambda i,b:i==0x8e and b'Matching potion stack is protected or full' in b)
assert query('SELECT amount FROM ragoff_companion_supply WHERE profile_id=? AND nameid=501',(kid,))[0][0]==stock
assert query('SELECT amount,favorite FROM inventory WHERE char_id=150001 AND nameid=501')==[(amount,1)]
c.send(struct.pack('<HHB',0x907,slot+1,1));wait(c,lambda i,b:i==0x908)
assert 'Waiting' in api(c,f'supplytake {kid} 0:501:0:1')[1]
wait(c,lambda i,b:i==0x8e and b'Supplies returned.' in b);time.sleep(.3)
assert query('SELECT amount,favorite FROM inventory WHERE char_id=150001 AND nameid=501')==[(amount+1,0)]
assert query('SELECT amount FROM ragoff_companion_supply WHERE profile_id=? AND nameid=501',(kid,))[0][0]==stock-1
assert not query('SELECT * FROM ragoff_companion_supply_journal');c.close()
result=dict(protected_stack_merge_rejected=True,unfavorite_then_return_success=True,no_quantity_or_metadata_corruption=True)
(R/'artifacts/m93-metadata-results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
