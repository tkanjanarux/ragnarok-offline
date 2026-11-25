// One owner per network-isolated container. The native AI retains emergency Heal.
static bool trial_execute(Shell& shell,map_session_data* owner,Hunt& h){
    auto* sd=shell.sd;
    auto now=gettick();
    if(!trial::armed){
        if(!std::getenv("BRAIN_LIMITED"))return false;
        trial::armed=true;trial::started=now;
        ShowInfo("B_ARM %lld %d\n",(long long)now,owner->id);
    }
    if(FILE* manual=std::fopen("artifacts/trial.stop","r")){
        std::fclose(manual);trial::stop("manual",owner->id,now);
    }
    auto* healer=map_id2sd(95000004);
    auto* pull=map_id2sd(h.opener);
    auto map=std::string(map_mapid2mapname(owner->m));
    if(map!="yuno_fild07" && map!="yuno_fild09")trial::stop("map",owner->id,now);
    for(int i=0;i<6;++i){
        auto* ally=i?map_id2sd(95000000+i-1):owner;
        if(!ally || ally->m!=owner->m || !owner->status.party_id || ally->status.party_id!=owner->status.party_id){
            trial::stop("missing",owner->id,now);continue;
        }
        const auto& a=ally->battle_status;
        int floor=trial::floor_hp(i,a.max_hp,now);
        if(int(a.hp)<=floor)trial::stop("critical_hp",ally->id,now);
        bool reachable=healer && !pc_isdead(healer) && battle_check_range(healer,ally,9)
            && healer->battle_status.sp>=skill_get_sp(AL_HEAL,5);
        if(ally==pull && distance_xy(ally->x,ally->y,h.x,h.y)>4)trial::stop("leash",ally->id,now);
        if(ally==pull && !reachable)trial::stop("puller_out_of_heal",ally->id,now);
        if(a.hp*100ULL<a.max_hp*70ULL){
            if(!trial::pending[i])trial::pending[i]=now;
            int damage=0;
            for(auto [t,d]:trial::hits[i])if(t>=now-2000)damage+=d;
            // 2.5 s covers the prior measured completed far Heal, plus 2.5 s reserve.
            if(!reachable || damage*5.0/2>=int(a.hp)-floor || now-trial::pending[i]>=5000)
                trial::stop("help_late",ally->id,now);
        }else trial::pending[i]=0;
    }
    long long stamp=0;int op=0,x=0,y=0,target=0;
    if(FILE* f=std::fopen("artifacts/trial.command","r")){
        if(std::fscanf(f,"%lld %d %d %d %d",&stamp,&op,&x,&y,&target)!=5)stamp=0;
        std::fclose(f);
    }
    bool fresh=stamp>0 && now>=stamp && now-stamp<=1200;
    if(fresh)trial::last_command=stamp;
    if(now-(trial::last_command?trial::last_command:trial::started)>(trial::last_command?1600:6000))
        trial::stop("heartbeat",owner->id,now);
    if(h.retreat)trial::stop("native_retreat",owner->id,now);
    if(trial::stopped){
        if(!trial::regrouped){
            team_retreat(owner,h,"limited trial stopped");
            trial::regrouped=true;
            for(auto& [id,s]:shells)if(s.character==owner->status.char_id)
                ShowInfo("B_HALTED %lld %d %d %d\n",(long long)now,id,
                         s.sd->ud.walktimer!=INVALID_TIMER,s.sd->ud.attacktimer!=INVALID_TIMER);
            ShowInfo("B_REGROUP %lld %d\n",(long long)now,owner->id);
        }
        return false; // Existing retreat branch handles Heal and regroup.
    }
    if(!pull || !healer)return true;
    if(fresh && op==3 && sd==healer && sd->ud.skilltimer==INVALID_TIMER){
        auto* ally=map_id2sd(target);
        if(trial::index(target)>=0 && ally && !ally->sc.getSCE(SC_KYRIE)
           && !support_party(shell,owner,true) && cast_skill(shell,ally,PR_KYRIE,5)){
            ShowInfo("B_APPLY %lld shield %d %d\n",(long long)now,sd->id,target);return true;
        }
    }
    if(sd!=pull)return false;
    if(sd->ud.skilltimer!=INVALID_TIMER || support_party(shell,owner,true))return true;
    if(!fresh || op==0 || op==3){unit_stop_attack(sd);unit_stop_walking(sd,USW_FIXPOS);return true;}
    if(!battle_check_range(healer,sd,9) || !path_search_long(nullptr,sd->m,healer->x,healer->y,x,y,CELL_CHKWALL))return true;
    if(distance_xy(x,y,h.x,h.y)>4 || distance_xy(x,y,healer->x,healer->y)>6 || h.hold_train)return true;
    if(op==1 && distance_xy(sd->x,sd->y,x,y)==1 && sd->ud.walktimer==INVALID_TIMER &&
       map_getcell(sd->m,x,y,CELL_CHKPASS) && map_getcell(sd->m,sd->x,y,CELL_CHKPASS) && map_getcell(sd->m,x,sd->y,CELL_CHKPASS) && unit_walktoxy(sd,x,y,0)){
        ShowInfo("B_APPLY %lld step %d %d %d\n",(long long)now,sd->id,x,y);
    }else if(op==2){
        auto* mob=map_id2md(target);
        if(mob && mob->m==sd->m && safe_pull(mob) && unclaimed(owner,mob) &&
           distance_xy(mob->x,mob->y,h.x,h.y)<=4 && battle_check_range(sd,mob,1)){
            unit_attack(sd,target,0);ShowInfo("B_APPLY %lld tag %d %d\n",(long long)now,sd->id,target);
        }
    }
    return true;
}
