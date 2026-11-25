// Staging observer. No movement, cast, timer registration, AI state or RNG writes.
int observe_mob(block_list* bl, va_list args) {
    auto* m=static_cast<mob_data*>(bl);
    auto tick=va_arg(args,long long);
    ShowInfo("B_M %lld %d %d %d %d %d %u %u %d %d %d %d %d %d\n",tick,m->id,m->mob_id,m->x,m->y,m->target_id,m->status.hp,m->status.max_hp,m->status.speed,m->status.def_ele,m->status.ele_lv,m->status.rhw.range,m->sc.getSCE(SC_FREEZE)!=nullptr,m->status.amotion);
    return 0;
}
void observe_team(map_session_data* owner,const Hunt& h,long long now) {
    ShowInfo("B_FRAME %lld %d %d %d %d %d %d %d %d %d\n",now,owner->id,owner->m,h.x,h.y,h.radius,h.cap,h.priest_pull,h.inbound,h.release_pack);
    map_foreachinmap(observe_mob,owner->m,BL_MOB,now);
    const Shell* priest=nullptr;
    for(const auto& kv:shells) {
        const auto& s=kv.second;
        if(s.character==owner->status.char_id && s.sd && companion_progression::career(s.sd->status.class_)==JOB_PRIEST)priest=&s;
    }
    auto actor=[&](map_session_data* a,const Shell* s){
        auto& b=a->battle_status;
        ShowInfo("B_A %lld %d %d %d %d %d %u %u %u %u %d %d %d %d %d %d %d %lld %lld %lld %lld %d %lld %lld\n",now,a->id,s?(int)s->profile:0,a->m,a->x,a->y,b.hp,b.max_hp,b.sp,b.max_sp,a->ud.to_x,a->ud.to_y,a->ud.walktimer!=INVALID_TIMER,a->ud.target,a->ud.skill_id,a->ud.skilltarget,a->ud.skilltimer!=INVALID_TIMER,(long long)a->ud.canact_tick,(long long)(s?s->skill_retry:0),(long long)(s?s->potion_retry:0),(long long)b.speed,a->die_counter,(long long)a->status.base_exp,(long long)a->status.job_exp);
        for(const auto& cd:a->scd){auto* t=get_timer(cd.second);if(t)ShowInfo("B_CD %lld %d %u %lld\n",now,a->id,cd.first,(long long)t->tick);}
        for(const auto& [buff,entry]:a->sc){
            const auto* sc=&entry;
            if(sc){auto* t=get_timer(sc->timer);ShowInfo("B_BUFF %lld %d %d %d %d %lld\n",now,a->id,(int)buff,sc->val2,sc->val3,t?(long long)t->tick:0LL);}
        }
        if(priest){
            auto* p=priest->sd;
            auto lv=companion_loadout::cast_level(p,AL_HEAL,5);
            bool enabled=priest->skills && std::find(priest->policy.skills.begin(),priest->policy.skills.end(),"heal")!=priest->policy.skills.end();
            bool reach=lv && p->m==a->m && battle_check_range(p,a,skill_get_range2(p,AL_HEAL,lv,true));
            ShowInfo("B_COVER %lld %d %d %d %d %d %d %d\n",now,a->id,reach,enabled && lv && !pc_isdead(p),lv && p->battle_status.sp>=skill_get_sp(AL_HEAL,lv),p->ud.skilltimer==INVALID_TIMER,now>=std::max(p->ud.canact_tick,priest->skill_retry),p->ud.walktimer!=INVALID_TIMER);
        }
    };
    actor(owner,nullptr);
    for(const auto& kv:shells){const auto& s=kv.second;if(s.character==owner->status.char_id && s.sd)actor(s.sd,&s);}
    for(auto id:h.pack)ShowInfo("B_PACK %lld %d\n",now,id);
}
