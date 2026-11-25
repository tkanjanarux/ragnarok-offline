// Called once per native scan, after native safety and resource checks.
if(admission_enabled()){
    ShowInfo("B_OFFER %lld %d %d %d %d\n",(long long)now,best?best->id:0,on_trip,reason!=nullptr,h.release_pack);
    if(on_trip){
        was_packed|=!h.pack.empty();
        if(h.pack.empty() && at_camp && (was_packed || (!best && !h.target && tank->sd->ud.walktimer==INVALID_TIMER))){
            ShowInfo("B_TRIPEND %lld %d\n",(long long)now,trial_trip);
            on_trip=false;ready_since=0;
        }
    }
    if(!on_trip && !reason && best && !h.release_pack){
        auto* camp=map_id2sd(95000004);
        bool ready=trial::armed && !trial::stopped && camp && wizard && !pc_isdead(camp);
        long long stamp=0;int permit=0, assessed=0;
        if(FILE* f=std::fopen("artifacts/trial.command","r")){
            if(std::fscanf(f,"%lld %d %d",&stamp,&permit,&assessed)!=3)permit=0;
            std::fclose(f);
        }
        ready=ready && permit==1 && assessed==best->id && stamp<=now && now-stamp<=1200 &&
            battle_check_range(camp,wizard->sd,8) && battle_check_range(camp,owner,8) &&
            battle_check_range(camp,tank->sd,8) && camp->battle_status.sp>=3*skill_get_sp(AL_HEAL,5) &&
            camp->ud.skilltimer==INVALID_TIMER && now>=camp->ud.canact_tick && h.pack.empty() && !threatened;
        for(auto& ally:shells)if(ally.second.character==owner->status.char_id)
            ready=ready && ally.second.sd->battle_status.hp*100ULL>=70ULL*ally.second.sd->battle_status.max_hp;
        ready=ready && owner->battle_status.hp*100ULL>=70ULL*owner->battle_status.max_hp;
        ShowInfo("B_ADMITCHECK %lld %d %d %d %d %lld\n",(long long)now,best->id,assessed,permit,ready,stamp);
        if(!ready)ready_since=0;
        if(ready && !ready_since)ready_since=now;
        if(!ready || now-ready_since<5000){reason="trial admission waiting";}
        else{++trial_trip;on_trip=true;was_packed=false;trip_started=now;
             ShowInfo("B_TRIP %lld %d %d %d\n",(long long)now,trial_trip,h.opener,best->id);
             ShowInfo("B_APPROVAL %lld %lld %d\n",(long long)now,stamp,best->id);}
    }else if(!on_trip)ready_since=0;
}
