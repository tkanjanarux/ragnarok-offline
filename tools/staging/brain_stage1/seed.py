import sys,sqlite3,json,pathlib
p=pathlib.Path(sys.argv[1])
s=json.loads(pathlib.Path(sys.argv[2]).read_text())
import os
if os.getenv('BRAIN_FIVE')=='1':
 priest=next(row for row in s['ragoff_companion'] if row['id']==1)
 s['ragoff_companion'].append(dict(priest,id=5,name='AI-Camp-Priest-5',hp=-1,sp=-1,gems=0))
 s['ragoff_companion_policy'].append(dict(profile_id=5,role='support',skill_order='heal,kyrie,resurrection'))
 for item,amount in ((11623,10),(11624,10),(717,10)):
  s['ragoff_companion_supply'].append(dict(profile_id=5,owner_char=1,nameid=item,amount=amount))
d=sqlite3.connect(p/'ragoff-stage.sqlite3')
assert (p/'STAGING_ONLY').exists()
cid,aid=150001,2000001
d.execute("update char set "+','.join(f'{k}=?' for k in s['char'])+",base_exp=0,job_exp=0 where char_id=?",[*s['char'].values(),cid])
for table in reversed(list(s)):
 if table.startswith("ragoff_companion"):d.execute("delete from "+table)
for t,rows in s.items():
 if t=='char':continue
 if not t.startswith('ragoff_companion'):d.execute('delete from '+t+' where char_id=?',(cid,))
 for row in rows:
  for k in ('char_id','owner_char','owner_account'):
   if k in row:row[k]=aid if k=='owner_account' else cid
  if t=='inventory':row.pop('id')
  d.execute('insert into '+t+'('+','.join(row)+') values('+','.join('?'*len(row))+')',list(row.values()))
d.commit()
with (p/'conf/import/battle_conf.txt').open('a') as f:f.write('\nbase_exp_rate: 300\njob_exp_rate: 300\n')
