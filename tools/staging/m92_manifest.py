#!/usr/bin/env python3
import pathlib,hashlib,json,subprocess,datetime
r=pathlib.Path(__file__).resolve().parents[2]
h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
files={}
for folder in ('src','3rdparty','tools/staging','sqlite-files/companion'):
 for p in (r/folder).rglob('*'):
  if p.is_file() and p.suffix in ('.c','.cpp','.h','.hpp','.inc','.py','.sh','.sql','.json') and '__pycache__' not in p.parts:files[str(p.relative_to(r))]=h(p)
files['Makefile.dgx']=h(r/'Makefile.dgx')
result={'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'branch':subprocess.check_output(['git','branch','--show-current'],cwd=r,text=True).strip(),'base_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=r,text=True).strip(),'uncommitted':True,'upstream_population_commit':'20dafe55416937c9b89401d20ac135d18576a3ed','source_sha256':dict(sorted(files.items())),'binary_sha256':{mode:{b:h(r/build/'bin'/b) for b in ('login-server','char-server','map-server')} for mode,build in (('optimized','build-m1'),('asan_ubsan','build-sanitize'))},'rollback_map_sha256':h(r/'runtime/m9-job-source-checkpoint/map-server') if (r/'runtime/m9-job-source-checkpoint/map-server').exists() else 'b4693c7c79ddca6dafa1f51297039688cff2c7089a306b959cf6da4dc9a8d2c1'}
(r/'audit/m92-source-manifest.json').write_text(json.dumps(result,indent=2));print('Manifest:',len(files),'source files, branch',result['branch'])
