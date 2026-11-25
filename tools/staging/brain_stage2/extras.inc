int observe_stranger(block_list* bl,va_list args){
    auto* owner=va_arg(args,map_session_data*);
    if(bl->id!=owner->id && shells.find(bl->id)==shells.end())
        ShowInfo("B_PEER %lld %d %d %d\n",(long long)gettick(),bl->id,bl->x,bl->y);
    return 0;
}
