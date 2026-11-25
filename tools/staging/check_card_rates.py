"""Audit the loaded item types and drop rates for every Renewal monster in the fixture."""
import hashlib,json,re,time
from pathlib import Path
from protocol import login
from check_m4_skills import wait
stage=Path('/stage')
assert (stage/'STAGING_ONLY').exists()
fixed='item_drop_card_min: 100\nitem_drop_card_max: 100' in (stage/'conf/import/battle_conf.txt').read_text()
ids=set()
for name in ('db/re/mob_db.yml','db/import/mob_db.yml'):
    ids.update(int(n) for n in re.findall(r'^  - Id: (\d+)',(stage/name).read_text(),re.M))
ids=sorted(ids)
c=login()
# Keep the script loop short per invocation. Read rates after the server has
# parsed the imports, applied battle config and resolved item types.
script=stage/'npc/custom/qa_card_rates.txt'
script.write_text('''-	script	QA Card Rates	-1,{
OnInit: bindatcmd "auditdrops",strnpcinfo(3)+"::OnAudit",99,99; end;
OnAudit:
 freeloop(1);
 for(.@m=atoi(.@atcmd_parameters$[0]); .@m<=atoi(.@atcmd_parameters$[1]); ++.@m){
  if(!getmobdrops(.@m))continue;
  for(.@i=0;.@i<$@MobDrop_count;++.@i)
   debugmes "QA_DROP "+.@m+" "+.@i+" "+$@MobDrop_item[.@i]+" "+getiteminfo($@MobDrop_item[.@i],ITEMINFO_TYPE)+" "+$@MobDrop_rate[.@i];
 }
 debugmes "QA_DROPS_DONE "+.@m;
 end;
}
''')
c.command('@loadnpc npc/custom/qa_card_rates.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
log=stage/'artifacts/map-server.log'
off=log.stat().st_size
for low in sorted({n//1000*1000 for n in ids}):
    c.command(f'@auditdrops {low} {low+999}')
    marker=f'QA_DROPS_DONE {low+1000}'.encode()
    for _ in range(150):
        if marker in log.read_bytes()[off:]:break
        time.sleep(.1)
    else:raise AssertionError(marker)
data=[tuple(map(int,r)) for r in re.findall(rb'QA_DROP (\d+) (\d+) (\d+) (\d+) (\d+)',log.read_bytes()[off:])]
cards=[r for r in data if r[3]==6]
others=[r for r in data if r[3]!=6]
assert len(cards)>700 and len(others)>7500,(len(cards),len(others))
if fixed:assert all(r[-1]==100 for r in cards),[r for r in cards if r[-1]!=100][:10]
for mob,item in [(1002,4001),(1096,4054),(1039,4147),(1502,4005)]:
    c.command(f'@mobinfo {mob}')
    c.command(f'@companion ui {mob} list')
    lines=[]
    while True:
        _,b=c.until({0x8e})
        line=b[4:].rstrip(b'\0').decode(errors='replace')
        if f'[RCO1] {mob} end' in line:break
        lines.append(line)
    print('mobinfo',mob,lines,flush=True)
    # New packet versions encode item links numerically. The command emits
    # items in the actual loaded database order, with up to three per line.
    percents=[float(x) for line in lines for x in re.findall(r'([0-9.]+)%',line)]
    regular=sorted((r for r in data if r[0]==mob),key=lambda r:r[1])
    if mob==1502:
        idx=len(regular)+1  # Santa Poring Card, second MVP bonus reward
    else:
        idx=next(i for i,r in enumerate(regular) if r[2]==item)
    assert len(percents)>idx and (not fixed or percents[idx]==1.0),(mob,idx,percents)
    print('CARD',mob,item,percents[idx],flush=True)
digest=hashlib.sha256(json.dumps(sorted(others)).encode()).hexdigest()
print('DROP_AUDIT',len(cards),len(others),digest,flush=True)
c.close()
