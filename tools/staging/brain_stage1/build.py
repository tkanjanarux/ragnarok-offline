"""Build staging-only instrumentation from a pinned source and a native build log."""
import argparse
import hashlib
import concurrent.futures
from pathlib import Path
import re
import shlex
import subprocess

p=argparse.ArgumentParser()
for arg in ('root','work','production','buildlog'):
    p.add_argument(arg,type=lambda s:Path(s).resolve())
a=p.parse_args()
if hashlib.sha256(a.production.read_bytes()).hexdigest()!='aecc8bd79489ac9c151c6e7abf0bbacfa47ab13d37d0937add5aa3464f6e0a34':
    raise ValueError('The supplied AI source differs from the recorded Production reference')
lines=a.buildlog.read_text().splitlines()
compile=shlex.split(next(l for l in lines if ' -c ' in l))
link=shlex.split(next(l for l in lines if l.startswith('g++  -o')))
def log(kind,fmt,params):
    return 'ShowInfo("B_'+kind+' %lld '+fmt+r'\n",(long long)gettick(),'+params+');'
def before(at,line):
    return at,line+'\n'+at
changes={
'population_engine/minimal':[
    before('void update_team(map_session_data* owner,Hunt& h)',Path(__file__).with_name('world.inc').read_text()),
    before('h.next_scan=now+350;', 'observe_team(owner,h,now);')],
'pc':[before('// Give EXP for Base Level',log('EXP','%d %lld %lld %d %d %d','sd->id,(long long)base_exp,(long long)job_exp,src?src->id:0,src?src->x:0,src?src->y:0')),
    before('pc_setparam(sd, SP_PCDIECOUNTER, sd->die_counter+1);',log('DEATH','%d %d %d %d %d','sd->id,src?src->id:0,sd->m,sd->x,sd->y'))],
'status':[before('status->hp-= hp;',log('HIT','%d %d %d %d %d %u','src?src->id:0,target->id,skill_id,hp,sp,status->hp')),
    before('status->hp += hp;\n\tstatus->sp += sp;',log('HEAL','%d %d %d','bl->id,hp,sp'))],
'skill':[before('if(group && group->alive_count)population_ground_landed','if(group && group->alive_count)'+log('FIELD','%d %d %d %d %d %d %d %d','group->group_id,group->src_id,skill_id,skill_lv,x,y,group->limit,group->interval')),
    ('int32 skill_delunitgroup_(std::shared_ptr<s_skill_unit_group> group, const char* file, int32 line, const char* func)\n{','int32 skill_delunitgroup_(std::shared_ptr<s_skill_unit_group> group, const char* file, int32 line, const char* func)\n{\nif(group)'+log('END','%d','group->group_id'))],
'unit':[before('ud->state.walk_easy = flag&1;\n\tud->to_x = x;', 'if(bl->type==BL_PC)'+log('WALK','%d %d %d','bl->id,x,y')),
    before('ud->target_to = tbl->id;', 'if(bl->type==BL_PC)'+log('CHASE','%d %d','bl->id,tbl->id')),
    before('ud->target = target_id;', 'if(ud->target!=target_id)'+log('TARGET','%d %d','ud->bl->id,target_id')),
    before('clif_skillcastcancel( *bl );','if(ret==0)'+log('CANCEL','%d %d','bl->id,ud->skill_id'))],
'mob':[('int32 mob_dead(mob_data *md, block_list *src, int32 type)\n{','int32 mob_dead(mob_data *md, block_list *src, int32 type)\n{\n'+log('KILL','%d %d %d','md->id,md->mob_id,src?src->id:0'))]}
changes['skill'].append(before('//success, unit created.', 'for(int i=0;i<group->unit_count;i++){const auto& cell=group->unit[i];if(cell.alive)'+log('CELL','%d %d %d %d %lld','group->group_id,cell.x,cell.y,cell.range,(long long)cell.limit')+'}'))
for fn in ('id','pos'):
    key='if( casttime > 0 ) {\n\t\tud->skilltimer = add_timer( tick+casttime, skill_castend_'+fn
    changes['unit'].append(before(key,log('CAST','%d %d %d %d %d %d %d','src->id,skill_id,skill_lv,ud->skilltarget,ud->skillx,ud->skilly,casttime')))
def build(n):
    src=a.root/'src/map'/(n+'.cpp')
    s=(a.production if n.endswith('/minimal') else src).read_text()
    for old,new in changes[n]:
        if s.count(old)!=(2 if old.startswith('status->hp += hp;') else 1):raise ValueError((n,old,s.count(old)))
        s=s.replace(old,new)
    if n=='mob':
        pattern=r'(?m)^(\s*)md->target_id\s*=\s*(?![=])((?:md->attacked_id = md->norm_attacked_id = )?(?:0|target_id|(?:bl|tbl|src)->id|md->attacked_id));'
        s=re.sub(pattern,lambda m:m[1]+'do { auto prior=md->target_id; '+m[0].strip()+' if(prior!=md->target_id)'+log('AGGRO','%d %d %d','md->id,prior,md->target_id')+' } while(false);',s)
    dst=a.work/src.name
    dst.write_text(s)
    obj=str(dst.with_suffix('.o'))
    subprocess.run(compile[:compile.index('-c')]+['-iquote',str(src.parent),'-c',str(dst),'-o',obj],cwd=a.root,check=True)
    return 'build-m1/src/map/'+n+'.cpp.o',obj
with concurrent.futures.ThreadPoolExecutor(6) as pool:
    for old,new in pool.map(build,changes):
        link[link.index(old)]=new
link[2]=str(a.work/'observer')
subprocess.run(link,cwd=a.root,check=True)
