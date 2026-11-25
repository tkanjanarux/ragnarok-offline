"""Real wire M6 roster/NPC/ownership/persistence tests, isolated fixtures only."""
import pathlib,json,time,struct,sqlite3,socket
from protocol import login,entry
from check_m4_skills import wait,skill
ROOT=pathlib.Path('/stage');assert (ROOT/'STAGING_ONLY').exists()
seq=0;npc_id=None

def api(c,action):
 global seq,npc_id
 seq+=1;token=seq;c.command(f'@companion ui {token} {action}')
 rows=[];total=None;enabled=None;end=time.monotonic()+15
 while time.monotonic()<end:
  i,b=c.packet()
  if i in (0x9fe,0x9ff) and b'Companion Recruiter' in b:npc_id=struct.unpack_from('<I',b,5)[0]
  if i!=0x8e:continue
  line=b[4:].rstrip(b'\0').decode(errors='replace');t=line.split()
  if len(t)<3 or t[:2]!=['[RCO1]',str(token)]:continue
  if t[2]=='begin':total=int(t[3]);enabled=int(t[4])
  elif t[2]=='row':
   assert len(t)==17,t
   r=dict(zip(['id','job','level','job_level','exp','job_exp','hp','max_hp','sp','max_sp','actor','mode','gems'],map(int,t[3:16])));r['name']=t[16];rows.append(r)
  elif t[2]=='end':
   assert len(rows)==total and total<=9
   return rows,' '.join(t[3:]),enabled
 raise AssertionError('M6 roster response missing')

def read_db():
 db=sqlite3.connect('file:/stage/ragoff-stage.sqlite3?mode=ro',uri=True)
 db.row_factory=sqlite3.Row
 rows=[dict(r) for r in db.execute('SELECT * FROM ragoff_companion ORDER BY id')];db.close();return rows

def verify_profiles(c,text):
 result={}
 c.command('@heal');c.command('@killmonster2');c.command('@companion dismiss');text(c,'Companion dismissed')
 rows,note,on=api(c,'list');assert on and not rows
 db=sqlite3.connect(ROOT/'ragoff-stage.sqlite3');db.execute("CREATE TRIGGER m6_fail_recruit BEFORE UPDATE OF name ON ragoff_companion BEGIN SELECT RAISE(FAIL,'M6 injected recruit failure'); END");db.commit();db.close()
 rows,note,_=api(c,'recruit knight');assert not rows and 'failed' in note
 assert not read_db()
 db=sqlite3.connect(ROOT/'ragoff-stage.sqlite3');db.execute('DROP TRIGGER m6_fail_recruit');db.commit();db.close()
 result['recruit_transaction_rolls_back_on_failure']=True
 rows,_,_=api(c,'recruit knight');assert len(rows)==1
 knight=rows[0];kid=knight['id'];assert knight['actor']==0 and knight['hp']==-1
 assert read_db()[0]['name']==knight['name']
 # Other real player (ordinary group0) can use the roster, but cannot touch this owner's records.
 db=sqlite3.connect(ROOT/'ragoff-stage.sqlite3');db.execute('UPDATE login SET group_id=0 WHERE account_id=2000002');db.commit();db.close()
 peer=login('/stage/peer-fixture.json')
 peer.send(struct.pack('<H',0x100));time.sleep(1)
 c.command('#allskill StagePeer');time.sleep(.5)
 api(peer,'party')
 wait(peer,lambda i,b:i==0xae5 and b'Team150002' in b)
 result['ordinary_player_native_party_creation']=True
 for action in ('summon','bench','retire'):
  r,n,_=api(peer,f'{action} {kid} confirm');assert not r and 'not found' in n
 r,_,_=api(peer,'recruit priest');assert len(r)==1 and r[0]['id']!=kid
 other=r[0]['id'];api(peer,f'retire {other} confirm');peer.close()
 db=sqlite3.connect(ROOT/'ragoff-stage.sqlite3');db.execute('UPDATE login SET group_id=99 WHERE account_id=2000002');db.commit();db.close()
 result['ordinary_player_api_and_cross_owner_isolation']=True
 # 100 saves/despawns of ONE persistent profile, new actor identity each time.
 identities=set()
 for _ in range(100):
  rows,_,_=api(c,f'summon {kid}');r=next(r for r in rows if r['id']==kid);assert r['actor'] and r['actor'] not in identities;identities.add(r['actor'])
  r2,n,_=api(c,f'summon {kid}');assert 'Already summoned' in n and len(r2)==1
  rows,_,_=api(c,f'bench {kid}');assert rows[0]['actor']==0
 result['persistent_summon_bench_cycles']=len(identities)
 rows,_,_=api(c,f'summon {kid}');name=rows[0]['name']
 db=sqlite3.connect(ROOT/'ragoff-stage.sqlite3');db.execute(f"CREATE TRIGGER m6_fail_save BEFORE UPDATE ON ragoff_companion WHEN OLD.id={kid} BEGIN SELECT RAISE(FAIL,'M6 injected save failure'); END");db.commit();db.close()
 rows,note,_=api(c,f'bench {kid}');assert rows[0]['actor'] and 'Save failed' in note
 db=sqlite3.connect(ROOT/'ragoff-stage.sqlite3');db.execute('DROP TRIGGER m6_fail_save');db.commit();db.close()
 result['failed_save_keeps_actor_active']=True
 c.command(f'#baselevel {name} 1');c.command(f'#set {name} BaseExp 123');c.command(f'#set {name} JobExp 42')
 c.command(f'#set {name} Hp 5');c.command(f'#set {name} Sp 1')
 rows,_,_=api(c,f'bench {kid}');r=rows[0];assert r['level']==11 and r['exp']==123 and r['job_exp']==42,r
 assert 0<r['hp']<30 and r['sp']<10,r
 rows,_,_=api(c,f'summon {kid}');r=rows[0];assert r['level']==11 and r['exp']==123 and r['hp']<30 and r['sp']<10,r
 result['progress_and_resources_survive_resummon']=True
 # Dead remains dead when benched and summoned, rather than healing for free.
 c.command(f'#kill {name}');time.sleep(.1)
 rows,_,_=api(c,f'bench {kid}');assert rows[0]['hp']==0
 rows,_,_=api(c,f'summon {kid}');assert rows[0]['mode']==4 and rows[0]['hp']==0
 api(c,f'bench {kid}');result['corpse_survives_resummon']=True
 # Recruit through real NPC dialogue, not a test-only function.
 c.command('@warp prontera 155 183');wait(c,lambda i,b:i==0x91);c.send(struct.pack('<H',0x7d))
 rows,_,_=api(c,'list')
 assert npc_id,'Recruiter NPC spawn packet/name missing'
 c.send(struct.pack('<HIB',0x90,npc_id,0));wait(c,lambda i,b:i==0xb5)
 c.send(struct.pack('<HI',0xb9,npc_id));wait(c,lambda i,b:i==0xb7)
 c.send(struct.pack('<HIB',0xb8,npc_id,2));wait(c,lambda i,b:i==0xb6)
 c.send(struct.pack('<HI',0x146,npc_id));text(c,'Recruited.')
 rows,_,_=api(c,'list');assert len(rows)==2
 priest=next(r for r in rows if r['job']==8);pid=priest['id']
 result['npc_click_dialogue_and_recruitment']=True
 api(c,f'summon {pid}');api(c,f'assist {pid}')
 aid=api_actor(c,pid)
 c.command(f'#heal {priest["name"]}');c.command('@die');skill(c,aid,54)
 rows,_,_=api(c,f'bench {pid}');p=next(r for r in rows if r['id']==pid);assert p['gems']==19,p
 rows,_,_=api(c,f'summon {pid}');p=next(r for r in rows if r['id']==pid);assert p['gems']==19
 api(c,f'bench {pid}');result['native_reagent_consumption_persisted']=True
 # Cap and confirmed release. Active profiles cannot be permanently removed.
 for _ in range(7):api(c,'recruit wizard')
 rows,n,_=api(c,'recruit knight');assert len(rows)==9 and 'Maximum nine' in n
 extra=[r['id'] for r in rows if r['id'] not in (kid,pid)]
 for ident in extra[:4]:assert 'Summoned' in api(c,f'summon {ident}')[1]
 rows,n,_=api(c,f'summon {pid}');assert 'limit' in n
 rows,n,_=api(c,f'retire {extra[0]} confirm');assert 'reserve' in n
 for ident in extra:api(c,f'bench {ident}')
 rows,n,_=api(c,f'retire {extra[0]}');assert 'confirmation' in n and len(rows)==9
 for ident in extra:api(c,f'retire {ident} confirm')
 result['roster_cap_active_cap_confirmed_release']=True
 # Save periodically while active; final shutdown profile is also left active.
 api(c,f'summon {pid}');c.command(f'#set {priest["name"]} BaseExp 321');time.sleep(6)
 assert next(r for r in read_db() if r['id']==pid)['base_exp']=='321'
 c.close();time.sleep(5)
 c=login();rows,_,_=api(c,'list');assert len(rows)==2 and all(r['actor']==0 for r in rows)
 assert next(r for r in rows if r['id']==pid)['exp']==321
 result['checkpoint_and_owner_logout_persistence']=True
 # Same account, different character must not see the owner's profiles.
 c.close();time.sleep(5)
 db=sqlite3.connect(ROOT/'ragoff-stage.sqlite3')
 db.execute("INSERT INTO char(char_id,account_id,char_num,name,class,base_level,job_level,last_map,last_x,last_y,save_map,save_x,save_y,hp,max_hp,sp,max_sp,sex) VALUES(150004,2000001,1,'StageAlt',0,10,10,'prontera',150,180,'prontera',150,180,100,100,50,50,'M')");db.commit();db.close()
 fixture=json.loads((ROOT/'fixture.json').read_text());fixture.update(name='StageAlt',slot=1,char_id=150004)
 path=ROOT/'alt-fixture.json';path.write_text(json.dumps(fixture));path.chmod(0o600)
 alt=login(str(path));rows,n,_=api(alt,f'summon {pid}');assert not rows and 'not found' in n;alt.close();time.sleep(5)
 c=login();result['same_account_other_character_isolation']=True
 rows,_,_=api(c,f'summon {pid}');c.command(f'#set {priest["name"]} BaseExp 456')
 api(c,f'bench {pid}')
 result['persistent_shutdown_profile']=pid
 return c,result

def api_actor(c,pid):return next(r for r in api(c,'list')[0] if r['id']==pid)['actor']
