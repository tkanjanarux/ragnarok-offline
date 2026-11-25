#!/usr/bin/env python3
"""Read-only synthetic identity audit of an explicitly isolated test database."""
import json,pathlib,sqlite3,sys
root=pathlib.Path(__file__).resolve().parents[2]
mode=sys.argv[1];assert mode in ('m5','m5asan','m6','m6asan','m7','m7asan','m8','m8asan','m8probe','m9','m9asan','m9off','m92','m92asan','m92off','m93','m93asan','m93regress','iphone')
stage=root/'runtime'/mode;assert (stage/'STAGING_ONLY').is_file()
db=sqlite3.connect(f'file:{stage}/ragoff-stage.sqlite3?mode=ro',uri=True)
scanned={}
for (name,) in db.execute("SELECT name FROM sqlite_master WHERE type='table'"):
 q='"'+name.replace('"','""')+'"'
 columns=[r[1] for r in db.execute('PRAGMA table_info('+q+')') if r[1] in ('account_id','char_id','leader_id','leader_char','owner_account','owner_char','partner_id','father','mother','child')]
 if not columns:continue
 counts={col:db.execute(f'SELECT count(*) FROM {q} WHERE "{col}" >= 95000000 AND "{col}" < 100000000').fetchone()[0] for col in columns}
 assert not any(counts.values()),(name,counts)
 scanned[name]=counts
for table in ('inventory','cart_inventory','storage','guild_storage','ragoff_companion_gear'):
 if db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",(table,)).fetchone():
  for (uid,) in db.execute('SELECT unique_id FROM '+table):
   assert (int(uid or 0)&0xf000000000000000)!=0xf000000000000000,(table,uid)
db.close()
result={'mode':mode,'tables_scanned':len(scanned),'synthetic_rows':0,'loan_uids_persisted':0,'tables':scanned,'read_only':True}
(root/f'audit/evidence/{mode}-persistence-scan.json').write_text(json.dumps(result,indent=2))
print(mode,len(scanned),'tables; zero synthetic rows')
