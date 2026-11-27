#!/usr/bin/env python3
"""Run the prepared server's actual job/class predicates to export shop hints.
No temporary state/map restrictions or GM/Spirit exceptions are claimed by hints.
Source remains GPL, extracted from the repository's pinned rAthena profiles.
"""
import argparse,json,re,subprocess,tempfile,hashlib
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('prepared',type=Path);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[2];native=a.prepared
files={s:(native/s).read_text() for s in ['src/common/mmo.hpp','src/map/map.hpp','src/map/itemdb.hpp','src/map/pc.cpp','src/map/itemdb.cpp','src/map/script_constants.hpp']}
def block(source,needle,enum=False):
 s=source[source.index(needle):];start=s.index('{');depth=1;end=start+1
 while depth:
  depth+=(s[end]=='{')-(s[end]=='}');end+=1
 return s[:end]+(';' if enum else '')+'\n'
code='''#include <cstdint>
#include <climits>
#include <iostream>
using uint64=uint64_t;using uint16=uint16_t;using int32=int32_t;
#define RENEWAL
#define ARRAYLENGTH(x) (sizeof(x)/sizeof((x)[0]))
#define nullpo_retr(r,p) if(!(p)) return r
'''
code+=block(files['src/common/mmo.hpp'],'enum e_job {',True)
code+='\n'.join(line for line in files['src/map/map.hpp'].splitlines() if line.startswith(('#define JOBL_','#define MAPID_')))+'\n'
code+=block(files['src/map/map.hpp'],'enum e_mapid :',True)
code+=block(files['src/map/itemdb.hpp'],'enum e_item_job :',True)
code+='struct map_session_data { uint64 class_; };\nstruct item_data { uint64 class_base[3]={}; uint16 class_upper=0; };\n'
for f,n in [('src/map/pc.cpp','uint64 pc_jobid2mapid(uint16'),('src/map/pc.cpp','static bool pc_job_can_use_item('),('src/map/pc.cpp','static bool pc_isItemClass ('),('src/map/itemdb.cpp','static void itemdb_jobid2mapid(uint64 bclass[3], e_mapid jobmask, bool active)\n{')]:code+=block(files[f],n)
constants=dict(re.findall(r'export_constant2\("EAJ_([A-Z_]+)",\s*(MAPID_[A-Z_]+)\)',files['src/map/script_constants.hpp']))
spec=json.loads((root/'server/cash-shop/candidate-equipment.json').read_text())
code+='int main(){\n'
for s in spec:
 code+=' { item_data item;\n'
 for job,active in s['jobs'].items():
  value='MAPID_ALL' if job=='All' else constants[job.upper()]
  code+=f'itemdb_jobid2mapid(item.class_base,{value},{str(active).lower()});\n'
 classes=s['classes'] or {'All':True}
 for key,active in classes.items():code+=f'item.class_upper {"|=" if active else "&= ~"} ITEMJ_{key.upper()};\n'
 code+=f' std::cout<<"{s["item_id"]}:"; for(int j=0;j<5000;j++){{map_session_data sd{{pc_jobid2mapid(j)}};if(sd.class_!=UINT64_MAX && pc_job_can_use_item(&sd,&item) && pc_isItemClass(&sd,&item)) std::cout<<j<<",";}}std::cout<<"\\n"; }}\n'
code+='}\n'
with tempfile.TemporaryDirectory() as directory:
 t=Path(directory);(t/'test.cpp').write_text(code)
 subprocess.run(['c++','-std=c++17',str(t/'test.cpp'),'-o',str(t/'test')],check=True)
 result=subprocess.check_output([str(t/'test')],text=True)
allowed={int(line.split(':')[0]):[int(n) for n in line.split(':')[1].split(',') if n] for line in result.splitlines()}
assert 11 not in allowed[2367] and 4012 in allowed[2367] and 3 in allowed[2296] and 1 not in allowed[2296]
a.output.write_text(json.dumps(dict(allowed_job_ids=allowed,source_sha256={k:hashlib.sha256((native/k).read_bytes()).hexdigest() for k in files},scope='Native base job/class eligibility only; level checked separately; server validates temporary restrictions/exceptions'),indent=2)+'\n')
print('Exported native job/class eligibility for',len(allowed),'items')
