#!/usr/bin/env python3
"""Test real native pet transaction and SQLite adapter from a verified prepared source."""
from pathlib import Path
import argparse,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('prepared_source',type=Path);args=p.parse_args()
r=Path(__file__).resolve().parents[2];s=args.prepared_source.resolve()
with tempfile.TemporaryDirectory(prefix='cash-pet-test-') as folder:
 binary=Path(folder)/'test'
 command=['c++','-std=c++17','-O1','-ffunction-sections','-fdata-sections']
 for inc in ['src','src/common','3rdparty/mysql/include','3rdparty/libconfig']:command+=['-I'+str(s/inc)]
 command+=[str(r/'scripts/cash-shop/pet-journal-test.cpp')]
 command += [str(s/'src/common'/name) for name in ['catalogue_pet.cpp','strlib.cpp','malloc.cpp','showmsg.cpp']]
 command+=['-Wl,--gc-sections','-l:libsqlite3.so.0','-lcrypto','-o',str(binary)]
 subprocess.run(command,check=True);subprocess.run([str(binary),str(r/'server/cash-shop/native/pet/migration.sql')],check=True)
