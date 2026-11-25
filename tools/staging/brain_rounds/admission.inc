    // The native route executor owns one outing until it starts delivering.
    const auto previous=h.round;
    const char* round_probe=std::getenv("DELIVERY_CASE");
    static bool injected_withdraw=false;
    const bool fault=!injected_withdraw && round_probe && !strcmp(round_probe,"withdraw") &&
        h.pack.size()>=2 && camp_gap>8;
    if(fault){injected_withdraw=true;ShowInfo("B_FAULT %lld withdraw\n",(long long)now);}
    const bool camp_incoming=std::any_of(scan.candidates.begin(),scan.candidates.end(),[&](mob_data* m){
        if(!status_bl_has_mode(m,MD_AGGRESSIVE) || m->ud.walktimer==INVALID_TIMER ||
           distance_xy(m->x,m->y,h.x,h.y)>7)return false;
        for(auto cell:h.rear_cells){
            int current=distance_xy(m->x,m->y,cell.first,cell.second);
            int next=distance_xy(m->ud.to_x,m->ud.to_y,cell.first,cell.second);
            if(next<current && next<=status_get_range(m)+1 &&
               path_search_long(nullptr,m->m,m->x,m->y,cell.first,cell.second,CELL_CHKWALL))return true;
        }
        return false;
    });
    if(hp<h.retreat_hp || fault)h.round=Hunt::Withdraw;
    else if(h.round==Hunt::Ready && (!h.outstanding.empty() || camp_incoming))h.round=Hunt::Clear;
    else if(h.round==Hunt::Pull && !h.outstanding.empty() &&
            ((reason && !continue_home) || (h.release_pack && !h.inbound)))
        h.round=Hunt::Clear;
    if((h.round==Hunt::Clear || h.round==Hunt::Withdraw) &&
       h.outstanding.empty() && !camp_incoming && hp>=h.stop_hp && ready && reserve && !h.rescue_ally &&
       !h.hold_train && !h.hazard_near_train){
        ShowInfo("B_SECURE %lld %d %d %d\n",(long long)now,int(h.round),hp,camp_incoming);
        h.round=Hunt::Ready;h.release_pack=false;h.inbound=false;
    }
    if(h.round==Hunt::Ready && !reason && best)
        h.round=h.outstanding.empty()?Hunt::Pull:Hunt::Clear;
    if(h.round==Hunt::Clear || h.round==Hunt::Withdraw){
        best=nullptr;continue_home=false;h.inbound=false;
        reason=h.round==Hunt::Clear?"clear current pack":"withdraw under cover";
    }
    if(previous!=h.round)
        ShowInfo("B_ROUND %lld %d %d %zu %d %d %d\n",(long long)now,int(previous),int(h.round),
                 h.outstanding.size(),hp,ready,reserve);
    // A neutral camp add is Hunter's only. Never open one while clearing.
    h.camp_add=0;
    if(auto* m=map_id2md(h.hunter_target)){
        if(distance_xy(m->x,m->y,h.x,h.y)<=7 && m->target_id!=h.opener &&
           (team_victim(m,owner) || h.round==Hunt::Pull))h.camp_add=m->id;
        else if(!h.pack.count(m->id))h.hunter_target=0;
    }
    if(!h.camp_add)for(int id:h.pack){
        auto* m=map_id2md(id);
        if(m && distance_xy(m->x,m->y,h.x,h.y)<=7 && m->target_id!=h.opener && team_victim(m,owner)){
            h.camp_add=id;break;
        }
    }
