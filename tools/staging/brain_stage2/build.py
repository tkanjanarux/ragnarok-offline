"""Build the stage-one observer with bystander positions and an atomic frame boundary."""
from pathlib import Path
import subprocess,sys
base=Path(__file__).resolve().parent.parent/'brain_stage1'
root,work,prod,flags=map(Path,sys.argv[1:])
code=(base/'world.inc').read_text()
code=code.replace('BL_MOB,now);','BL_MOB,now,owner);').replace('auto tick=va_arg(args,long long);','\n'.join([
    'auto tick=va_arg(args,long long);','auto* own=va_arg(args,map_session_data*);',
    r'ShowInfo("B_ELIG %lld %d %d %d %lld %u %u\n",tick,m->id,safe_pull(m),unclaimed(own,m),(long long)m->db->base_exp,(unsigned)m->status.rhw.atk,(unsigned)m->status.rhw.atk2);']))
code=code.replace('ShowInfo("B_M ',r'auto* ice=m->sc.getSCE(SC_FREEZE);auto* thaw=ice?get_timer(ice->timer):nullptr;ShowInfo("B_MOVE %lld %d %d %d %lld\n",tick,m->id,status_bl_has_mode(m,MD_AGGRESSIVE),m->db->range2,thaw?(long long)thaw->tick:0LL);'+'\n    ShowInfo("B_M ')
code=code.replace('map_foreachinmap(observe_mob',r'ShowInfo("B_PULLSTATE %lld %d %d %d\n",now,h.target,h.release_pack,h.inbound);'+'\n    map_foreachinmap(observe_mob')
extra=Path(__file__).with_name('extras.inc').read_text()
code=extra+code[:code.rindex('}')]+'''    for(const auto& kv:shells){
        const auto& s=kv.second;
        if(s.character!=owner->status.char_id || !s.sd)continue;
        std::vector<companion_supply::Stock> stock;
        if(companion_supply::list(mmysql_handle,s.character,s.profile,stock))
            for(const auto& r:stock)ShowInfo("B_SUPPLY %lld %d %u %u\\n",now,s.sd->id,r.itemid,r.amount);
        for(auto entry:{std::make_pair(AL_HEAL,"heal"),std::make_pair(PR_KYRIE,"kyrie"),std::make_pair(WZ_STORMGUST,"storm")}){
            auto lv=pc_checkskill(s.sd,entry.first);
            bool enabled=s.skills && std::find(s.policy.skills.begin(),s.policy.skills.end(),entry.second)!=s.policy.skills.end();
            ShowInfo("B_SK %lld %d %d %d %d %d\\n",now,s.sd->id,(int)entry.first,(int)lv,enabled,lv?skill_get_sp(entry.first,lv):0);
        }
    }
    map_foreachinmap(observe_stranger,owner->m,BL_PC,owner);
    ShowInfo("B_DONE %lld\\n",now);
}
'''
import os
five=os.environ.get('BRAIN_FIVE')=='1'
if five:
    import five_native
    code=five_native.instrument(code)
(work/'world.inc').write_text(code)
builder=(base/'build.py').read_text()
extra_hooks=r"""
changes['population_engine/minimal'].extend([
 ('if(sd->ud.walktimer==INVALID_TIMER)walk_toward_cell(sd,h,pull->x,pull->y,h.pack.empty()?8:2);',
  'if(sd->ud.walktimer==INVALID_TIMER && walk_toward_cell(sd,h,pull->x,pull->y,h.pack.empty()?8:2))'+log('PULL','%d %d','sd->id,pull->id')),
 ('if(sd->ud.walktimer==INVALID_TIMER)walk_pull(sd,h,pull->x,pull->y,h.pack.empty()?6:3);',
  'if(sd->ud.walktimer==INVALID_TIMER) { walk_pull(sd,h,pull->x,pull->y,h.pack.empty()?6:3); if(sd->ud.walktimer!=INVALID_TIMER)'+log('PULL','%d %d','sd->id,pull->id')+'}'),
 ('cast_skill(shell,pull,SM_PROVOKE,5))return true;', 'cast_skill(shell,pull,SM_PROVOKE,5)){'+log('PULL','%d %d','sd->id,pull->id')+'return true;}'),
 ('else if(sd->ud.attacktimer==INVALID_TIMER)unit_attack(sd,pull->id,0);', 'else if(sd->ud.attacktimer==INVALID_TIMER){ unit_attack(sd,pull->id,0); if(sd->ud.attacktimer!=INVALID_TIMER)'+log('PULL','%d %d','sd->id,pull->id')+'}')])
changes['battle']=[('status_change_end(target, SC_KYRIE);','{ '+log('BREAK','%d %d %d','target->id,sce->val2,sce->val3')+' status_change_end(target, SC_KYRIE); }')]
changes['unit'].append(before('if(ret < 0)\n\t\tShowError("delete timer error : skill_id', 'if(ret==0 && (type&2))'+log('INTERRUPT','%d %d','bl->id,skill_id')))
"""
(work/'build.py').write_text(builder.replace('def build(n):',extra_hooks+(five_native.hooks if five else '')+'\ndef build(n):'))
subprocess.run([sys.executable,str(work/'build.py'),*sys.argv[1:]],check=True)
