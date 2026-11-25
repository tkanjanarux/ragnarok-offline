#!/usr/bin/env python3
"""Disposable network-none M8 only: native cash purchase + M7 map rollback compatibility."""
import pathlib,json,subprocess,time,shutil,hashlib
root=pathlib.Path(__file__).resolve().parents[2];stage=root/'runtime/m8';name='ragoff-companion-m8'
info=json.loads(subprocess.check_output(['docker','inspect',name]))[0]
assert info['HostConfig']['NetworkMode']=='none' and not info['State']['Running']
r=json.loads((stage/'artifacts/lifecycle-results.json').read_text());pid=r['gear_shutdown_profile'];uid=r['gear_shutdown_unique']
(stage/'artifacts').rename(stage/'artifacts-final-before-cash');(stage/'artifacts').mkdir()
shutil.copy2(root.parent/'cash-shop/item_cash.pagination.yml',stage/'db/import/item_cash.yml')
def start():
 subprocess.run(['docker','start',name],check=True)
 for _ in range(180):
  p=stage/'artifacts/map-server.log'
  if p.exists() and 'Map Server is now online.' in p.read_text(errors='replace'):return
  time.sleep(1)
 raise RuntimeError('readiness timeout')
def stop():
 subprocess.run(['docker','stop','-t','35',name],check=True)
 assert (stage/'artifacts/exit-codes.txt').read_text()=='[0, 0, 0]'
start();subprocess.run(['docker','exec',name,'python3','/tests/check_cash_purchase.py'],check=True)
shutil.copy2(stage/'artifacts/cash-purchase.json',root/'audit/evidence/m8-cash-purchase.json');stop()
(stage/'artifacts').rename(stage/'artifacts-cash-success');(stage/'artifacts').mkdir()
shutil.copy2(stage/'map-server',stage/'map-server.m8-tested')
shutil.copy2(root/'runtime/m7-source-checkpoint/map-server',stage/'map-server')
start()
code=f'''import sys,sqlite3
sys.path.insert(0,'/tests')
from protocol import login
from check_m6_profiles import api
c=login();c.command('@setbattleflag companion_enable 1')
rows,_,_=api(c,'list');assert any(r['id']=={pid} for r in rows)
api(c,'retire {pid} confirm');assert any(r['id']=={pid} for r in api(c,'list')[0])
rows,_,_=api(c,'summon {pid}');assert next(r for r in rows if r['id']=={pid})['actor']>0
api(c,'bench {pid}');c.close()
db=sqlite3.connect('file:/stage/ragoff-stage.sqlite3?mode=ro',uri=True)
assert db.execute('SELECT count(*) FROM ragoff_companion_gear WHERE unique_id=? AND state=0',('{uid}',)).fetchone()[0]==1
assert db.execute('SELECT count(*) FROM inventory WHERE unique_id=?',('{uid}',)).fetchone()[0]==0
print('M7_MAP_M8_CHAR_CUSTODY_ROLLBACK_PASS')
'''
subprocess.run(['docker','exec',name,'python3','-c',code],check=True);stop()
shutil.copy2(stage/'map-server.m8-tested',stage/'map-server')
(stage/'artifacts').rename(stage/'artifacts-rollback-success');(stage/'artifacts-final-before-cash').rename(stage/'artifacts')
receipt=dict(m7_map_m8_char_login_summon=True,escrow_preserved=True,release_blocked=True,no_duplicate_owner_item=True,rollback_requires_m8_char_guard=True)
(root/'audit/evidence/m8-rollback-test.json').write_text(json.dumps(receipt,indent=2));print(json.dumps(receipt))
