// SPDX-License-Identifier: GPL-3.0
// Included in script.cpp. Pet packs use the existing inventory-save barrier,
// then one SQLite transaction (egg row, inventory, food, voucher and journal).
#include "../common/catalogue_pet.hpp"
#include "population_engine/gear_runtime.hpp"
#include "population_engine/supply_runtime.hpp"
#include <unordered_map>
extern int32 char_fd;
int16 pet_get_card3_intimacy(int32 intimacy);
static_assert(catalogue_pet::pet_marker == CARD0_PET);
namespace {
struct CataloguePetPending { catalogue_pet::Claim claim; uint32 token; int timer,fd; uint32 login; int16 map; };
std::unordered_map<uint32,CataloguePetPending> catalogue_pet_pending;
uint32 catalogue_pet_sequence=0x40000000;
static TIMER_FUNC(catalogue_pet_timeout) {
    auto it=catalogue_pet_pending.find(id);
    if(it!=catalogue_pet_pending.end() && it->second.timer==tid){
        auto* sd=map_id2sd(id);
        if(sd && sd->status.char_id==it->second.claim.character && sd->login_id1==it->second.login)
            clif_displaymessage(sd->fd,"Pet pack request timed out before delivery. Voucher kept; refresh before retrying.");
        catalogue_pet_pending.erase(it);
    }
    return 0;
}
}
void catalogue_pet_barrier(uint32 account,uint32 character,uint32 token,int ready) {
    auto it=catalogue_pet_pending.find(account);
    if(it==catalogue_pet_pending.end() || it->second.token!=token || it->second.claim.character!=character)return;
    auto p=it->second;delete_timer(p.timer,catalogue_pet_timeout);catalogue_pet_pending.erase(it);
    auto* sd=map_id2sd(account);
    if(!sd || sd->status.char_id!=character || sd->fd!=p.fd || sd->login_id1!=p.login || !session_isActive(sd->fd))return;
    // Low bits identify the existing inventory barrier. Bit16 is set only by
    // a Char server with this journal guard and its migration installed.
    if((ready & 0x13)!=0x13 || pc_isdead(sd) || sd->state.trading || sd->m!=p.map || sd->state.warping || sd->state.changemap ||
       !catalogue_pet::same(sd->inventory.u.items_inventory,p.claim.before.data())){
        clif_displaymessage(sd->fd,"Pet pack cancelled because inventory or character state changed. Voucher kept.");return;
    }
    // Recheck weight in case a status buff expired while waiting for the save.
    auto egg_data=item_db.find(p.claim.egg_id),food_data=item_db.find(p.claim.food_id);
    if(!egg_data || !food_data || uint64(sd->weight)+egg_data->weight+uint64(food_data->weight)*p.claim.food_amount>sd->max_weight){
        clif_displaymessage(sd->fd,"Pet pack needs more free weight. Voucher kept.");return;
    }
    catalogue_pet::Snapshot after{};item egg{};
    if(!catalogue_pet::commit(mmysql_handle,p.claim,after,egg)){
        clif_displaymessage(sd->fd,"Pet pack could not be delivered. Nothing was consumed.");return;
    }
    item food{};food.nameid=p.claim.food_id;food.identify=1;
    bool ok=pc_additem(sd,&egg,1,LOG_TYPE_SCRIPT)==ADDITEM_SUCCESS &&
            pc_additem(sd,&food,p.claim.food_amount,LOG_TYPE_SCRIPT)==ADDITEM_SUCCESS &&
            pc_delitem(sd,p.claim.voucher_slot,1,0,0,LOG_TYPE_SCRIPT)==0;
    if(!ok || !catalogue_pet::same(sd->inventory.u.items_inventory,after.data())){
        clif_displaymessage(sd->fd,"Pet pack delivery is saved. Reconnect to refresh inventory safely.");set_eof(sd->fd);return;
    }
    intif_storage_save(sd,&sd->inventory);
    clif_displaymessage(sd->fd,"Pet egg and food delivered. One voucher consumed.");
}
BUILDIN_FUNC(catalogue_pet_claim) {
    map_session_data* sd;
    if(!script_rid2sd(sd))return SCRIPT_CMD_FAILURE;
    auto reject=[&](){script_pushint(st,0);return SCRIPT_CMD_SUCCESS;};
    if(CheckForCharServer() || catalogue_pet::available(mmysql_handle)!=1 || pc_isdead(sd) || sd->state.trading ||
       sd->state.warping || sd->state.changemap || catalogue_pet_pending.count(sd->status.account_id) ||
       companion_runtime::busy(sd->status.account_id) || companion_supplies::busy(sd->status.account_id))return reject();
    int64 voucher=script_getnum64(st,2),egg_id=script_getnum64(st,3),food_id=script_getnum64(st,4),amount=script_getnum64(st,5);
    if(voucher<=0 || voucher>UINT32_MAX || egg_id<=0 || egg_id>UINT32_MAX || food_id<=0 || food_id>UINT32_MAX || amount<1 || amount>100)return reject();
    auto pet=pet_db_search(static_cast<t_itemid>(egg_id),PET_EGG);
    auto egg_data=item_db.find(static_cast<t_itemid>(egg_id)),food_data=item_db.find(static_cast<t_itemid>(food_id));
    if(!pet || pet->FoodID!=food_id || !egg_data || !food_data || egg_data->type!=IT_PETEGG ||
       !itemdb_isstackable2(food_data.get()) || food_data->flag.guid || food_data->flag.autoequip)return reject();
    auto mob=mob_db.find(pet->class_);if(!mob)return reject();
    if(uint64(sd->weight)+egg_data->weight+uint64(food_data->weight)*amount>sd->max_weight)return reject();
    catalogue_pet::Claim q{};
    q.account=sd->status.account_id;q.character=sd->status.char_id;q.capacity=sd->status.inventory_slots;
    q.voucher_slot=-1;q.food_slot=-1;q.egg_slot=-1;
    std::copy_n(sd->inventory.u.items_inventory,MAX_INVENTORY,q.before.begin());
    for(int n=0;n<q.capacity;++n){
        const auto& v=q.before[n];
        if(v.nameid==voucher && catalogue_pet::plain(v) && q.voucher_slot<0)q.voucher_slot=n;
        if(v.nameid==food_id && !v.bound && !v.expire_time && !v.unique_id){
            bool cards=false;for(auto c:v.card)if(c)cards=true;if(cards)continue;
            if(!catalogue_pet::plain(v) || v.amount+amount>MAX_AMOUNT ||
               (food_data->stack.inventory && v.amount+amount>food_data->stack.amount))return reject();
            if(q.food_slot<0)q.food_slot=n;
        }
    }
    if(q.voucher_slot<0)return reject();
    for(int n=0;n<q.capacity;++n)if(!q.before[n].nameid){
        if(q.egg_slot<0)q.egg_slot=n;else if(q.food_slot<0)q.food_slot=n;
    }
    if(q.egg_slot<0 || q.food_slot<0 || (food_data->stack.inventory && amount>food_data->stack.amount))return reject();
    q.food_amount=amount;q.food_id=food_id;q.egg_id=egg_id;q.monster=pet->class_;q.level=mob->lv;q.intimacy=pet->intimate;
    // Mob DB pads jname to NAME_LENGTH. Match native intif_create_pet C-string semantics.
    char pet_name[NAME_LENGTH];safestrncpy(pet_name,mob->jname.c_str(),NAME_LENGTH);
    q.name=pet_name;q.egg_card0=CARD0_PET;q.egg_card3=pet_get_card3_intimacy(pet->intimate);
    if(!intif_storage_save(sd,&sd->inventory))return reject();
    uint32 token=++catalogue_pet_sequence;
    if(token<0x40000000 || token>=0x80000000)token=catalogue_pet_sequence=0x40000001;
    int timer=add_timer(gettick()+10000,catalogue_pet_timeout,q.account,0);
    catalogue_pet_pending.emplace(q.account,CataloguePetPending{q,token,timer,sd->fd,sd->login_id1,sd->m});
    WFIFOHEAD(char_fd,14);WFIFOW(char_fd,0)=0x30af;WFIFOL(char_fd,2)=q.account;WFIFOL(char_fd,6)=q.character;WFIFOL(char_fd,10)=token;WFIFOSET(char_fd,14);
    script_pushint(st,1);return SCRIPT_CMD_SUCCESS;
}
