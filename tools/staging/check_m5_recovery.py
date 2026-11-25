"""M5 native wire integration; disposable fixtures only, no production access."""
import time,struct,pathlib,socket
from check_m4_skills import summon,state,wait,skill,dismiss_all
from protocol import entry

def verify_recovery(c,text):
 result={}
 c.command('@heal');c.command('@killmonster2')
 # Retain a corpse away from saved camp, then let native Resurrection consume SP/gem.
 c.command('@warp prontera 170 180')
 wait(c,lambda i,b:i==0x91);c.send(struct.pack('<H',0x7d));time.sleep(1)
 knight=summon(c,'knight');priest=summon(c,'priest');time.sleep(1)
 c.command('@companion assist');text(c,'Companion assisting')
 c.command('@companion skills off');text(c,'skills disabled')
 c.command(f'#kill Companion{knight}');time.sleep(2)
 assert state(c,knight)['hp']==0
 assert f'released id={knight}' not in pathlib.Path('/stage/artifacts/map-server.log').read_text()
 # Party lifecycle must update even while the AI is a corpse.
 c.send(struct.pack('<H',0x100));time.sleep(1)
 assert state(c,knight)['party']==0
 c.command('@party M5Recovery');time.sleep(1)
 assert state(c,knight)['party']>0
 c.command('@companion assist');text(c,'Companion assisting')
 result['dead_actor_party_leave_and_rebind']=True
 c.command(f'#heal Companion{priest}')
 c.command('@companion skills on');text(c,'skills enabled')
 skill(c,priest,54,knight)
 assert state(c,knight)['hp']>0
 result['retained_corpse_and_native_ai_resurrection']=True
 # Full companion wipe remains dead away from saved camp; owner returns to save point.
 c.command('@companion stop');text(c,'Companion stopped')
 for aid in [knight,priest]:c.command(f'#kill Companion{aid}')
 time.sleep(11)
 assert state(c,knight)['hp']==0 and state(c,priest)['hp']==0
 c.command('@warp prontera 150 180');wait(c,lambda i,b:i==0x91);c.send(struct.pack('<H',0x7d))
 end=time.monotonic()+10
 while time.monotonic()<end:
  if state(c,knight)['hp']>0 and state(c,priest)['hp']>0:break
 else:raise AssertionError('camp recovery failed')
 result['wipe_no_field_revive_and_savepoint_recovery']=True
 dismiss_all(c,[knight,priest],text)
 # Native sitting regeneration, no grants from the engine.
 wizard=summon(c,'wizard');time.sleep(1)
 c.command(f'#set Companion{wizard} Sp 1');c.command('@companion assist');text(c,'Companion assisting')
 wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<I',b,2)[0]==wizard and b[29]==2)
 before=state(c,wizard)['sp'];assert before==1
 time.sleep(14)
 assert state(c,wizard)['sp']>before
 result['native_sitting_and_natural_sp_regeneration']=True
 c.command('@companion stop')
 wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<I',b,2)[0]==wizard and b[29]==3)
 text(c,'Companion stopped')
 # Modern party option request / effective rejection / automatic recovery.
 c.send(struct.pack('<HIBB',0x7d7,0,0,0))
 wait(c,lambda i,b:i==0x7d8 and struct.unpack_from('<I',b,2)[0]==0)
 c.send(struct.pack('<HIBB',0x7d7,1,0,0))
 wait(c,lambda i,b:i==0x7d8 and struct.unpack_from('<I',b,2)[0]==1)
 c.command('@baselevel 20')
 wait(c,lambda i,b:i==0x7d8 and struct.unpack_from('<I',b,2)[0]==2)
 text(c,'Party EXP: Level difference 20 exceeds limit 15.')
 assert state(c,wizard)['share']==0
 c.command('@baselevel -20')
 wait(c,lambda i,b:i==0x7d8 and struct.unpack_from('<I',b,2)[0]==1)
 assert state(c,wizard)['share']==1
 result['modern_party_options_effective_level_feedback']=True
 dismiss_all(c,[wizard],text)
 return result

def verify_skill_target(c,text):
 c.command('@jobchange 2');c.command('@allskill');c.command('@heal');time.sleep(1)
 wizard=summon(c,'wizard');time.sleep(1)
 c.command('@companion assist');text(c,'Companion assisting')
 c.command('@monster 1008 1')
 b=wait(c,lambda i,b:i in (0x9fe,0x9ff) and struct.unpack_from('<H',b,23)[0]==1008)
 mob=struct.unpack_from('<I',b,5)[0]
 ident,e=entry('clif_parse_UseSkillToId')
 c.send(struct.pack('<HHHI',ident,1,19,mob)) # Fire Bolt 1 only: no attack request.
 b=wait(c,lambda i,b:i==0x1de and struct.unpack_from('<HII',b,2)==(19,wizard,mob))
 assert struct.unpack_from('<i',b,24)[0]>0
 dismiss_all(c,[wizard],text);c.command('@killmonster2');c.command('@jobchange 0')
 # A live aggressive monster is already attacking the owner before Knight arrives.
 c.command('@baselevel 40');c.command('@heal');time.sleep(.5)
 c.command('@monster 1054 1')
 b=wait(c,lambda i,b:i in (0x9fe,0x9ff) and struct.unpack_from('<H',b,23)[0]==1054)
 mob=struct.unpack_from('<I',b,5)[0]
 wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(mob,2000001))
 knight=summon(c,'knight');time.sleep(.5)
 c.command('@companion assist');text(c,'Companion assisting')
 wait(c,lambda i,b:i==0x9cb and struct.unpack_from('<H',b,2)[0]==6 and struct.unpack_from('<II',b,8)==(mob,knight))
 wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(mob,knight))
 dismiss_all(c,[knight],text);c.command('@killmonster2');c.command('@baselevel -40');c.command('@heal')
 return {'owner_targeted_skill_opener_wizard_assist':True,'knight_protects_party_with_native_provoke':True}
