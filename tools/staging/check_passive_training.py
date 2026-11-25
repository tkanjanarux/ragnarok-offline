"""Read native learned ranks and watch actual skill-regen ticks in an isolated map."""
import json
import re
import time
from companion_ai_fixture import setup, api, stage, wait

c,rows=setup(7,8,9)
script=stage/'npc/custom/qa_passives.txt'
script.write_text("""-	script	QA Passives	-1,{
OnInit:
 bindatcmd "qarank",strnpcinfo(3)+"::OnRank",99,99;
 end;
OnRank:
 .@actor=atoi(.@atcmd_parameters$[0]); .@skill=atoi(.@atcmd_parameters$[1]);
 if (!attachrid(.@actor)) end;
 if (.@skill==0) {
  .@text$="QA_BOOK "+.@actor+" "+SkillPoint;
  for (.@i=2; .@i<=90; ++.@i) {
   if (.@i==82) continue;
   .@rank=getskilllv(.@i);
   if (.@rank) .@text$+=" "+.@i+"="+.@rank;
  }
  debugmes .@text$;
 } else debugmes "QA_RANK "+.@actor+" "+.@skill+" "+getskilllv(.@skill);
 end;
}
""")
c.command('@loadnpc npc/custom/qa_passives.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
c.command('@set BaseLevel 90')
c.command('@jobchange 3')
seq=9000
def table(pid):
    global seq
    seq+=1
    c.command(f'@companion ui {seq} inspect {pid} ui2 skills6 gear2 syrup1 hunt1')
    skills={}
    while True:
        _,msg=c.until({0x8e})
        p=msg[4:].rstrip(b'\0').split()
        if p[:2]!=[b'[RCO1]',str(seq).encode()]:continue
        if p[2]==b'end':return skills
        if p[2]==b'skill':skills[int(p[3])]=int(p[4])

def native(actor,sk):
    log=stage/'artifacts/map-server.log'
    offset=log.stat().st_size
    c.command(f'@qarank {actor} {sk}')
    for _ in range(60):
        with log.open('rb') as f:
            f.seek(offset)
            m=re.search(fr'QA_RANK {actor} {sk} (\d+)'.encode(),f.read())
        if m:return int(m[1])
        time.sleep(.04)
    raise AssertionError(('missing native rank',actor,sk))

first_ids={7:set(range(2,9)),8:{22,23,28,29,33,34},9:{9,11,14,16,19,20}}
requires={3:{2:1},7:{5:5},8:{6:5},23:{22:3},29:{28:3},33:{22:3},34:{22:5},
          56:{55:1},59:{56:3},60:{3:1},61:{3:1},62:{5:10,7:3,3:5,60:10,61:5},
          54:{72:1,9:4},73:{33:2},75:{73:4,74:3},84:{11:1,20:1},86:{14:1,20:1},90:{16:1}}
def audit_book(job,actor,jl,promoted):
    log=stage/'artifacts/map-server.log'
    offset=log.stat().st_size
    c.command(f'@qarank {actor} 0')
    for _ in range(50):
        with log.open('rb') as f:
            f.seek(offset)
            m=re.search(fr'QA_BOOK {actor} (\d+)((?: \d+=\d+)*)'.encode(),f.read())
        if m:break
        time.sleep(.04)
    assert m,actor
    book={int(k):int(v) for k,v in re.findall(rb'(\d+)=(\d+)',m[2])}
    for sk,needed in requires.items():
        if sk in book:
            assert all(book.get(k,0)>=v for k,v in needed.items()),(job,jl,sk,book)
    charged=sum(v for k,v in book.items() if (k not in first_ids[job])==promoted)
    assert int(m[1])==max(0,jl-1-charged),(job,jl,book,charged,m[1])
    # Normal promotion and job cap must have no outstanding legacy debt.
    if jl in (40,50):assert charged<=jl-1,(job,jl,book)
    return book

def observe(jl):
    c.command(f'@set JobLevel {jl}')
    time.sleep(.6)
    return {job:table(row['id']) for job,row in rows.items()}

first={7:[2,3,4],8:[22,23],9:[9]}
second={7:[55],8:[9],9:[]}
report={}
for promoted in (False,True):
    if promoted:c.command('@jobchange 11')
    last={}
    for jl in (1,5,10,15,20,28,40,50):
        allskills=observe(jl)
        stagekey='second' if promoted else 'first'
        summary={}
        for job,skills in allskills.items():
            book=audit_book(job,rows[job]['actor'],jl,promoted)
            assert all(book.get(k,0)==v for k,v in skills.items()),(job,jl,book,skills)
            ids=first[job]+(second[job] if promoted else [])
            assert all(skills[k]>=last.get((job,k),0) for k in ids)
            summary[job]={k:skills[k] for k in ids}
            if promoted:
                assert all(skills[k]==frozen[job][k] for k in first[job])
            else:
                assert all(k not in skills for k in second[job])
            if jl in (1,50):
                for k in ids:assert native(rows[job]['actor'],k)==skills[k]
            last.update({(job,k):skills[k] for k in ids})
        report[f'{stagekey}-{jl}']=summary
        print(stagekey,jl,summary,flush=True)
    if not promoted:frozen=allskills
assert all(v>0 for values in summary.values() for v in values.values())
for level in (15,1,50):
    skills=observe(level)
    for job,member in rows.items():
        snapshot=report[f'second-{level}'][job]
        assert all(skills[job][k]==v for k,v in snapshot.items())
        audit_book(job,member['actor'],level,True)
print('PASS native prerequisites, independent class budgets and level rollback',flush=True)
# Native skill regen runs separately from base HP/SP regen, suppressed by setup().
c.command('@setbattleflag natural_heal_skill_interval 1000')
for job,key,skill in [(7,'hp',4),(8,'sp',9),(9,'sp',9)]:
    row=rows[job]; kmax='max_'+key
    current=next(v for v in api(c,'list')[0] if v['job']==job)
    rank=summary[job][skill]
    delta=(5 if key=='hp' else 3)*rank+rank*current[kmax]//500
    c.command(f"#set {row['name']} {key.upper()} 100")
    for _ in range(30):
        observed=next(v[key] for v in api(c,'list')[0] if v['job']==job)
        if observed>100 and (observed-100)%delta==0:break
        time.sleep(.2)
    else:raise AssertionError((job,key,rank,delta,observed))
    print('PASS native recovery',job,key,delta,observed,flush=True)
(stage/'artifacts/passive-ranks.json').write_text(json.dumps(report))
c.close()
print('PASS passive training and recovery',flush=True)
