// Single-owner network-isolated fixture. Negative opt-in is the control arm.
static bool admission_enabled(){return std::getenv("BRAIN_LIMITED")!=nullptr;}
static int trial_trip=0, trial_peel=0;
static bool on_trip=false, was_packed=false;
static t_tick ready_since=0, trip_started=0;
static int danger_near(block_list* bl,va_list args){
    auto* mob=static_cast<mob_data*>(bl);
    auto* corpse=va_arg(args,map_session_data*);
    if(status_isdead(*mob))return 0;
    return distance_bl(mob,corpse)<=std::max(4,(int)status_get_range(mob)+2);
}
static bool resurrection_safe(Shell& s,map_session_data* ally,map_session_data* owner){
    if(!admission_enabled())return true;
    // Sole reviver. Refuse if cover is dead or separated, or a mob can attack the site.
    auto* guard=map_id2sd(95000001);
    bool clear=s.profile==5 && guard && !pc_isdead(guard) && guard->m==ally->m &&
        guard->status.party_id==owner->status.party_id && battle_check_range(guard,ally,3) &&
        battle_check_range(s.sd,ally,8) && !map_foreachinrange(danger_near,ally,12,BL_MOB,ally);
    ShowInfo("B_REVIVE %lld %d %d %d\n",(long long)gettick(),s.sd->id,ally->id,clear);
    return clear;
}
