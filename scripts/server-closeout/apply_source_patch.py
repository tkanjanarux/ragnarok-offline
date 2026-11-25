"""Verify exact reviewed base files, then optionally apply only the scoped patch.
Does not build, migrate, stop, start, or deploy any service.
"""
import argparse,hashlib,json,pathlib,subprocess,os
p=argparse.ArgumentParser();p.add_argument('source_root',type=pathlib.Path);p.add_argument('--apply',action='store_true');a=p.parse_args()
r=pathlib.Path(__file__).resolve().parent;manifest=json.loads((r/'server-source-manifest.json').read_text());root=a.source_root.resolve()
for name,hashes in manifest.items():
 path=root/name
 if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest()!=hashes['base']:
  raise SystemExit('Base differs; review and rebase required: '+name)
subprocess.run(['git','apply','--check',str(r/'server-fixes.patch')],cwd=root,check=True)
if a.apply:
 backup=root/'ui-closeout-source-backup-20261125';backup.mkdir(mode=0o700)
 for name in manifest:
  out=backup/name;out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes((root/name).read_bytes())
 subprocess.run(['git','apply',str(r/'server-fixes.patch')],cwd=root,check=True)
 for name,hashes in manifest.items():
  assert hashlib.sha256((root/name).read_bytes()).hexdigest()==hashes['patched'],name
 print('Applied six reviewed source files. Source backup:',backup)
else: print('Base hashes and patch check passed. No files changed.')
