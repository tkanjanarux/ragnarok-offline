"""Upgrade the existing M9.3 iPhone staging container, keeping its player database."""
import datetime
import hashlib
import json
import pathlib
import shutil
import socket
import sqlite3
import subprocess
import time

root = pathlib.Path(__file__).resolve().parents[2]
stage = root / 'runtime/iphone'
evidence = root / 'audit/evidence'
name = 'ragoff-companion-iphone'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def wait_online():
    for _ in range(150):
        log = stage / 'artifacts/map-server.log'
        if log.exists() and 'Map Server is now online.' in log.read_text(errors='replace'):
            break
        time.sleep(1)
    else:
        raise RuntimeError('Staging map did not start')
    for port in (16900, 16121, 15121):
        with socket.create_connection(('100.114.58.13', port), 5):
            pass

def preserving(before, after):
    for table in ('ragoff_companion','ragoff_companion_growth','ragoff_companion_policy',
                  'ragoff_companion_gear','ragoff_companion_supply','ragoff_companion_supply_journal',
                  'inventory','acc_reg_num','char','party'):
        query = f'SELECT * FROM {table} ORDER BY rowid'
        if before.execute(query).fetchall() != after.execute(query).fetchall():
            raise RuntimeError('Staging data changed: ' + table)

def main():
    state = json.loads(subprocess.check_output(['docker','inspect',name]))[0]
    assert state['State']['Running'] and state['HostConfig']['NetworkMode']==name
    assert {m['Destination']:m['Source'] for m in state['Mounts']} == {'/stage':str(stage),'/tests':str(root/'tools/staging')}
    assert state['HostConfig']['PortBindings']=={f'{p}/tcp':[{'HostIp':'100.114.58.13','HostPort':str(p)}] for p in (16900,16121,15121)}
    old = json.loads((evidence/'m93-deployment.json').read_text())
    for filename, sha in old['binary_sha256'].items(): assert digest(stage/filename)==sha
    assert digest(stage/'login-server')==old['login_unchanged_sha256']
    tests = json.loads((evidence/'m94-verification.json').read_text())
    candidate=root/'build-m1/bin/map-server'
    assert digest(candidate)==tests['optimized_sha256'] and tests['optimized_pass'] and tests['asan_pass']
    assert tests['asan_lsan_errors']==0 and tests['asan_exit_codes']==[0,0,0]
    stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    backup=stage/('backup-m94-'+stamp)
    backup.mkdir(mode=0o700)
    recruiter=pathlib.Path('npc/custom/companion_recruiter.txt')
    shutil.copy2(stage/recruiter,backup/recruiter.name)
    shutil.copy2(stage/'map-server',backup/'map-server')
    shutil.copy2(candidate,stage/'map-server.m94-next')
    subprocess.run(['docker','stop','-t','60',name],check=True)
    try:
        dbpath=stage/'ragoff-stage.sqlite3'
        with sqlite3.connect(f'file:{dbpath}?mode=ro',uri=True) as src,sqlite3.connect(backup/'ragoff-stage.sqlite3') as dst:
            src.backup(dst)
        (backup/'ragoff-stage.sqlite3').chmod(0o600)
        with sqlite3.connect(dbpath) as db:
            db.executescript((root/'sqlite-files/companion/006_presets.sql').read_text())
        with sqlite3.connect(f'file:{backup}/ragoff-stage.sqlite3?mode=ro',uri=True) as before,sqlite3.connect(f'file:{dbpath}?mode=ro',uri=True) as after:
            preserving(before,after)
            assert after.execute('PRAGMA integrity_check').fetchone()==('ok',)
        (stage/'artifacts').rename(backup/'artifacts')
        (stage/'artifacts').mkdir()
        shutil.copy2(root/recruiter,stage/recruiter)
        (stage/'map-server.m94-next').replace(stage/'map-server')
        subprocess.run(['docker','start',name],check=True)
        wait_online()
    except BaseException:
        subprocess.run(['docker','stop','-t','60',name],check=True)
        shutil.copy2(backup/recruiter.name,stage/recruiter)
        shutil.copy2(backup/'map-server',stage/'map-server')
        subprocess.run(['docker','start',name],check=True)
        wait_online()
        raise
    receipt={'backup':str(backup),'map_sha256':digest(stage/'map-server'),'migration':'006_presets.sql',
             'previous_map_sha256':old['binary_sha256']['map-server'],'preservation':True,'ports':[16900,16121,15121]}
    (evidence/'m94-deployment.json').write_text(json.dumps(receipt,indent=2))
    print(json.dumps(receipt,indent=2))
if __name__=='__main__':
    main()
