"""Compile-only additions for the isolated five-companion experiment."""
def instrument(code):
    code=code.replace('const Shell* priest=nullptr;', 'std::vector<const Shell*> priests;')
    code=code.replace('priest=&s;', 'priests.push_back(&s);')
    code=code.replace('if(priest){', '''ShowInfo("B_PARTY %lld %d %d %d %d\\n",now,a->id,a->status.party_id,owner->status.party_id,a->status.class_);
        for(const auto* priest:priests){''')
    code=code.replace('ShowInfo("B_COVER', '''ShowInfo("B_AID %lld %d %d %d %d %d %d %d\\n",now,p->id,a->id,reach,enabled && lv && !pc_isdead(p),lv && p->battle_status.sp>=skill_get_sp(AL_HEAL,lv),p->ud.skilltimer==INVALID_TIMER,now>=std::max(p->ud.canact_tick,priest->skill_retry));
            if(priest->profile==1)ShowInfo("B_COVER''')
    return code

# The four-member control never enters the profile-five branches.
hooks=r"""
changes['population_engine/minimal'].extend([
 ('max_active_per_owner = 4;', 'max_active_per_owner = 5;'),
 before('        auto* tank=map_id2sd(team->second.opener);', '''
        if(shell.profile==5 && farming){
            // Native emergency and normal Heal have already run. Stay in camp.
            for(int career:{JOB_WIZARD,JOB_NOVICE,JOB_HUNTER}){
                for(auto* ally:allies){
                    if((career==JOB_NOVICE ? ally!=owner : companion_progression::career(ally->status.class_)!=career)
                       || pc_isdead(ally) || ally->sc.getSCE(SC_KYRIE))continue;
                    if(std::find(shell.policy.skills.begin(),shell.policy.skills.end(),"kyrie")!=shell.policy.skills.end()
                       && sd->battle_status.sp>=skill_get_sp(PR_KYRIE,5)+3*skill_get_sp(AL_HEAL,5)
                       && cast_skill(shell,ally,PR_KYRIE,5))return true;
                }
            }
            return false;
        }'''),
 ('} else if (assist_owner(shell, owner)) {','''} else if(shell.profile==5 && hunt!=hunts.end() && hunt->second.mode==TeamMode::mob){
        if(distance_bl(sd,owner)>3 && sd->ud.walktimer==INVALID_TIMER)unit_walktobl(sd,owner,2,0);
    } else if (assist_owner(shell, owner)) {''')])
key='skill->impl->castendNoDamageId( src, bl, skill_lv, tick, flag );'
changes['skill'].append((key,'''{
    auto observed=skill_id==AL_HEAL || skill_id==PR_KYRIE;
    auto hp_before=observed?status_get_hp(bl):0;
    if(observed)ShowInfo("B_SPELL %lld %d %d %d\\n",(long long)gettick(),src->id,bl->id,skill_id);
    '''+key+'''
    if(observed){
        auto* shield=status_get_sc(bl)->getSCE(SC_KYRIE);
        ShowInfo("B_DELIVER %lld %d %d %d %lld %d\\n",(long long)gettick(),src->id,bl->id,skill_id,(long long)status_get_hp(bl)-hp_before,shield?shield->val2:0);
    }
}'''))
"""
