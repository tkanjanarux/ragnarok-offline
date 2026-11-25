"""Offline SQLite migration. Caller must stop all writers before applying.
Creates an exclusive backup first; refuses unexpected schema and duplicate IDs.
Never run against a live database. Rollback: stop writers, restore this backup.
"""
import argparse, hashlib, json, pathlib, re, sqlite3, os

def migrate(db, backup):
    db, backup = pathlib.Path(db), pathlib.Path(backup)
    if not db.is_file() or backup.exists():
        raise ValueError('Database missing or backup already exists')
    c = sqlite3.connect(str(db), isolation_level=None)
    if c.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
        raise ValueError('Integrity check failed')
    # SQLite backup API includes committed WAL contents.
    os.close(os.open(backup, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600))
    b = sqlite3.connect(str(backup)); c.backup(b); b.close()
    c.execute('PRAGMA foreign_keys=OFF')
    changes=[]
    try:
        c.execute('BEGIN IMMEDIATE')
        for table,key,kind,pk in [('mail','id','BIGINT','"id"'),('guild','guild_id','INTEGER','"guild_id", "char_id"')]:
            ddl=c.execute('SELECT sql FROM sqlite_master WHERE type="table" AND name=?',(table,)).fetchone()[0]
            info=c.execute(f'PRAGMA table_info("{table}")').fetchall()
            if 'AUTOINCREMENT' in ddl and [(r[1],r[2]) for r in info if r[5]]==[(key,'INTEGER')]:
                continue
            if c.execute(f'SELECT 1 FROM "{table}" GROUP BY "{key}" HAVING COUNT(*)>1 LIMIT 1').fetchone():
                raise ValueError(f'{table}: duplicate identity; manual reconciliation required')
            if c.execute(f'SELECT 1 FROM "{table}" WHERE "{key}" IS NULL OR "{key}" <= 0 OR "{key}" >= 2147483647 LIMIT 1').fetchone():
                raise ValueError(f'{table}: invalid protocol ID')
            new,n=re.subn(r'"'+key+r'" '+kind+r' NOT NULL\s*,', '"'+key+'" INTEGER PRIMARY KEY AUTOINCREMENT,', ddl, count=1)
            if n!=1: raise ValueError(f'{table}: unexpected ID column')
            new,n=re.subn(r',\s*PRIMARY KEY \('+re.escape(pk)+r'\)', '', new, count=1)
            if n!=1: raise ValueError(f'{table}: unexpected primary key')
            new=new.replace('CREATE TABLE "'+table+'"', 'CREATE TABLE "__ui_new_'+table+'"',1)
            if new==ddl or '__ui_new_' not in new: raise ValueError('Unexpected CREATE statement')
            extra=c.execute('SELECT sql FROM sqlite_master WHERE tbl_name=? AND type IN ("index","trigger") AND sql IS NOT NULL',(table,)).fetchall()
            cols=','.join('"'+r[1].replace('"','""')+'"' for r in info)
            c.execute(new)
            c.execute(f'INSERT INTO "__ui_new_{table}" ({cols}) SELECT {cols} FROM "{table}"')
            assert not c.execute(f'SELECT {cols} FROM "{table}" EXCEPT SELECT {cols} FROM "__ui_new_{table}"').fetchone()
            c.execute(f'DROP TABLE "{table}"')
            c.execute(f'ALTER TABLE "__ui_new_{table}" RENAME TO "{table}"')
            for (sql,) in extra: c.execute(sql)
            changes.append(table)
        if c.execute('PRAGMA foreign_key_check').fetchone(): raise ValueError('Foreign key check failed')
        if c.execute('PRAGMA integrity_check').fetchone()[0]!='ok': raise ValueError('Integrity check failed')
        c.execute('COMMIT')
    except BaseException:
        if c.in_transaction: c.execute('ROLLBACK')
        raise
    finally: c.close()
    return {'changed':changes,'backup':str(backup),'backup_sha256':hashlib.sha256(backup.read_bytes()).hexdigest()}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('database');p.add_argument('backup');p.add_argument('--writers-stopped',action='store_true');a=p.parse_args()
    if not a.writers_stopped: p.error('Stop all database writers first; then pass --writers-stopped')
    print(json.dumps(migrate(a.database,a.backup),indent=2))
