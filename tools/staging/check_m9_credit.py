"""AI corpse damage belongs to the eligible owner; dead owner gets no credit."""
import pathlib,struct,time,json
from protocol import login,entry
from check_m4_skills import wait,summon,state
from check_m4_exp import warp,drain
R=pathlib.Path('/stage');assert (R/'M9_TEST').exists()
def text(c,s):return wait(c,lambda i,b:i==0x8e and s.encode() in b)
def setup(c):
 c.command('@companion dismiss');text(c,'Companion dismissed');c.command('@heal');c.command('@killmonster2');c.command('@set BaseLevel 10');c.command('@set BaseExp 0');c.send(struct.pack('<HI',0x102,0));time.sleep(.3)
 aid=summon(c,'knight');c.command('@companion skills off');text(c,'Companion skills disabled');c.command('@companion assist');text(c,'Companion assisting')
 c.command('@monster 1008 1');b=wait(c,lambda i,b:i in (0x9fe,0x9ff) and struct.unpack_from('<H',b,23)[0]==1008);mob=struct.unpack_from('<I',b,5)[0]
 x=(b[63]<<2)|(b[64]>>6);y=((b[64]&63)<<4)|(b[65]>>4);warp(c,f'prontera {x} {y}')
 c.params[1]=0;ident,_=entry('clif_parse_UseSkillToId');c.send(struct.pack('<HHHI',ident,1,19,mob))
 wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(aid,mob) and struct.unpack_from('<i',b,22)[0]>0)
 return aid,mob
c=login();c.command('@jobchange 2');c.command('@allskill');c.command('@str -1000');c.command('@str 30');c.command('@agi -1000');c.command('@agi 98');c.command('@dex -1000');c.command('@dex 40');c.command('@int -1000');c.command('@int 10');c.command('@setbattleflag exp_calc_type 2');aid,mob=setup(c)
c.command('#kill Companion'+str(aid));assert state(c,aid)['hp']==0;time.sleep(2)
ident,_=entry('clif_parse_ActionRequest');c.send(struct.pack('<HIB',ident,mob,7))
wait(c,lambda i,b:i==0x80 and struct.unpack_from('<I',b,2)[0]==mob and b[6]==1);time.sleep(.3);drain(c)
assert c.params[1]==149,c.params[1]
result={'dead_companion_previous_damage_owner_exp':c.params[1]}
aid,mob=setup(c);c.command('@die');time.sleep(.3);c.command('@killmonster')
wait(c,lambda i,b:i==0x80 and struct.unpack_from('<I',b,2)[0]==mob and b[6]==1);time.sleep(.3);drain(c)
assert c.params.get(1,0)==0,c.params
result['dead_owner_exp']=0;c.command('@alive');c.command('@companion dismiss');text(c,'Companion dismissed');c.close()
(R/'artifacts/m9-credit-results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
