"""Read the three stored profiles and Details frames with the iPhone protocol."""
import json
import pathlib
import sqlite3
from protocol import login
from check_m6_profiles import api

stage=pathlib.Path('/stage')
assert (stage/'STAGING_ONLY').is_file() and not (stage/'M9_TEST').exists()
with sqlite3.connect('file:/stage/ragoff-stage.sqlite3?mode=ro',uri=True) as db:
    owner=db.execute('SELECT class,base_level,job_level FROM char WHERE char_id=?',
                     (json.loads((stage/'fixture.json').read_text())['char_id'],)).fetchone()
client=login()
legacy=api(client,'list')[0]
profiles=[]
for token,member in enumerate(legacy,start=1):
    pid=member['id']
    client.command(f'@companion ui {token} inspect {pid} ui2')
    rows=[]
    skills=[]
    while True:
        code,b=client.packet()
        if code!=0x8e:continue
        fields=b[4:].rstrip(b'\0').decode().split()
        if fields[:2]!=['[RCO1]',str(token)]:continue
        if fields[2]=='row' and int(fields[3])==pid:rows.append(fields)
        if fields[2]=='skill':skills.append(int(fields[3]))
        if fields[2]=='end':break
    assert len(rows)==1 and len(rows[0])==18 and skills
    row=rows[0]
    if owner[0] in (0,1,2,3,4,5,6):
        assert int(row[4])=={7:1,8:4,9:2}[member['job']]
    if int(row[4])==4:assert 54 not in skills
    profiles.append({'id':pid,'class':int(row[4]),'preset':row[17],'skills':skills})
client.close()
assert profiles
result={'live_inspect':'PASS','owner_class':owner[0],'owner_base':owner[1],'owner_job':owner[2],
        'profiles':profiles,'native_iphone':'UNVERIFIED'}
(stage/'artifacts/m94-staging-smoke.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
