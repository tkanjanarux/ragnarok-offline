// Disposable one-party farm fixture. Included only by the trial builder.
#pragma once
#include <cstdio>
#include <deque>
#include <algorithm>
#include <utility>
namespace trial {
inline bool armed=false, stopped=false, regrouped=false;
inline long long started=0, last_command=0;
inline std::deque<std::pair<long long,int>> hits[6];
inline long long pending[6]={};
inline int index(int id){return id==2000001?0:(id>=95000000 && id<=95000004?id-95000000+1:-1);}
inline void stop(const char* why,int id,long long now){
    if(!armed || stopped)return;
    stopped=true;
    ShowInfo("B_STOP %lld %s %d\n",now,why,id);
}
inline int floor_hp(int i,int maxhp,long long now){
    auto& q=hits[i];
    while(!q.empty() && q.front().first<now-8000)q.pop_front();
    int floor=(maxhp*15+99)/100;
    for(auto [t,d]:q)floor=std::max(floor,d);
    return floor;
}
inline void hit(int id,int hp,int maximum,int damage,long long now){
    int i=index(id);
    if(!armed || i<0 || damage<=0)return;
    hits[i].emplace_back(now,damage);
    if(hp-damage<=floor_hp(i,maximum,now))stop("critical_hit",id,now);
}
}
