static bool camp_cover(Shell& s,map_session_data* owner){
    auto* sd=s.sd;auto* wiz=map_id2sd(95000002);
    if(!wiz || wiz->m!=sd->m || pc_isdead(wiz))return false;
    auto lv=companion_loadout::cast_level(sd,AL_HEAL,5);
    if(!lv)return false;
    int radius=skill_get_range2(sd,AL_HEAL,lv,true);
    auto covered=[&](int x,int y,map_session_data* a){
        return distance_xy(x,y,a->x,a->y)<=radius-1 && path_search_long(nullptr,sd->m,x,y,a->x,a->y,CELL_CHKWALL);
    };
    if(covered(sd->x,sd->y,wiz) && covered(sd->x,sd->y,owner))return true;
    if(sd->ud.skilltimer!=INVALID_TIMER || sd->ud.walktimer!=INVALID_TIMER)return true;
    int bx=sd->x,by=sd->y,cost=INT_MAX;
    for(int x=owner->x-6;x<=owner->x+6;x++)for(int y=owner->y-6;y<=owner->y+6;y++){
        if(!covered(x,y,wiz)||!covered(x,y,owner)||!map_getcell(sd->m,x,y,CELL_CHKPASS))continue;
        walkpath_data p{};
        if(!path_search(&p,sd->m,sd->x,sd->y,x,y,0,CELL_CHKNOPASS))continue;
        int score=p.path_len*4+distance_xy(x,y,wiz->x,wiz->y);
        if(score<cost){cost=score;bx=x;by=y;}
    }
    if(cost!=INT_MAX && unit_walktoxy(sd,bx,by,0))
        ShowInfo("B_COVERMOVE %lld %d %d %d %d\n",(long long)gettick(),sd->id,bx,by,cost);
    return true;
}
static bool peel_allowed(map_session_data* owner,const mob_data* m){
    return owner && m && m->target_id && m->target_id!=95000001 && team_victim(m,owner) &&
        !m->master_id && !m->guardian_data && m->get_bosstype()==BOSSTYPE_NONE &&
        unclaimed(owner,m) && distance_bl(owner,m)<=10;
}
static int collect_peel(block_list* bl,va_list args){
    auto* owner=va_arg(args,map_session_data*);auto** best=va_arg(args,mob_data**);
    auto* m=static_cast<mob_data*>(bl);
    if(peel_allowed(owner,m) && (!*best || m->target_id==95000002))*best=m;
    return 0;
}
static bool defensive_peel(Shell& s,map_session_data* owner){
    if(s.profile!=2 || !s.skills || std::find(s.policy.skills.begin(),s.policy.skills.end(),"provoke")==s.policy.skills.end())return false;
    mob_data* m=nullptr;map_foreachinrange(collect_peel,s.sd,8,BL_MOB,owner,&m);
    if(!m)return false;
    trial_peel=m->id;
    int previous=m->target_id;
    bool ok=cast_skill(s,m,SM_PROVOKE,5);
    if(ok)ShowInfo("B_PEEL %lld %d %d %d\n",(long long)gettick(),m->id,previous,m->target_id);
    trial_peel=0;return ok;
}
