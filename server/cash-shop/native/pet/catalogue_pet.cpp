// SPDX-License-Identifier: GPL-3.0
#include "catalogue_pet.hpp"
#include "showmsg.hpp"
#include <algorithm>
#include <cstring>
#include <cstdlib>
#include <vector>
namespace catalogue_pet {
static int scalar(Sql* db) {
    char* text=nullptr;int result=-1;
    if(Sql_NextRow(db)==SQL_SUCCESS){Sql_GetData(db,0,&text,nullptr);if(text)result=std::atoi(text);}
    Sql_FreeResult(db);return result;
}
int available(Sql* db) {
    if(Sql_QueryStr(db,"SELECT count(*) FROM sqlite_master WHERE type='table' AND name='ragoff_catalogue_pet_journal'")!=SQL_SUCCESS)return -1;
    return scalar(db);
}
bool plain(const item& v) {
    if(!v.nameid || v.amount<1 || v.identify!=1 || v.equip || v.equipSwitch || v.refine || v.attribute ||
       v.expire_time || v.favorite || v.bound || v.unique_id || v.enchantgrade)return false;
    for(auto c:v.card)if(c)return false;
    for(auto o:v.option)if(o.id||o.value||o.param)return false;
    return true;
}
static std::vector<std::string> canonical(const item* values) {
    std::vector<std::string> result;
    for(int n=0;n<MAX_INVENTORY;++n)if(values[n].nameid && values[n].amount>0){
        item v=values[n];v.id=0;
        // pc_additem assigns an inventory UID when the committed egg reaches
        // memory. Its authoritative identity is the same persisted pet_id in
        // card1/card2; an undelivered egg may legitimately still have UID zero.
        if(v.card[0]==pet_marker)v.unique_id=0;
        result.emplace_back(reinterpret_cast<const char*>(&v),sizeof(v));
    }
    std::sort(result.begin(),result.end());return result;
}
bool same(const item* a,const item* b){return canonical(a)==canonical(b);}
static std::string encode(const Snapshot& values) {
    static constexpr char hex[]="0123456789abcdef";
    const auto* data=reinterpret_cast<const unsigned char*>(values.data());
    std::string out;out.reserve(sizeof(values)*2);
    for(size_t n=0;n<sizeof(values);++n){out+=hex[data[n]>>4];out+=hex[data[n]&15];}
    return out;
}
static bool decode(const char* text,size_t size,Snapshot& values) {
    if(size!=sizeof(values)*2)return false;
    auto* data=reinterpret_cast<unsigned char*>(values.data());
    auto digit=[](char c){return c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:-1;};
    for(size_t n=0;n<sizeof(values);++n){int a=digit(text[n*2]),b=digit(text[n*2+1]);if(a<0||b<0)return false;data[n]=a*16+b;}
    return true;
}
static const char* condition="identify=1 AND unique_id=0 AND equip=0 AND equip_switch=0 AND refine=0 AND attribute=0 AND expire_time=0 AND bound=0 AND favorite=0 AND enchantgrade=0 AND card0=0 AND card1=0 AND card2=0 AND card3=0 AND option_id0=0 AND option_val0=0 AND option_parm0=0 AND option_id1=0 AND option_val1=0 AND option_parm1=0 AND option_id2=0 AND option_val2=0 AND option_parm2=0 AND option_id3=0 AND option_val3=0 AND option_parm3=0 AND option_id4=0 AND option_val4=0 AND option_parm4=0";
static bool rollback(Sql* db,int line){Sql_QueryStr(db,"ROLLBACK");ShowWarning("Cash pet transaction rejected at source line %d; no delivery committed.\n",line);return false;}
bool commit(Sql* db,const Claim& q,Snapshot& after,item& egg) {
    if(available(db)!=1 || q.capacity<1 || q.capacity>MAX_INVENTORY || q.voucher_slot<0 || q.voucher_slot>=q.capacity ||
       q.food_slot<0 || q.food_slot>=q.capacity || q.egg_slot<0 || q.egg_slot>=q.capacity ||
       q.voucher_slot==q.food_slot || q.voucher_slot==q.egg_slot || q.food_slot==q.egg_slot ||
       q.food_amount<1 || q.food_amount>100 || !plain(q.before[q.voucher_slot]) || q.before[q.egg_slot].nameid ||
       (q.before[q.food_slot].nameid && (!plain(q.before[q.food_slot]) || q.before[q.food_slot].nameid!=q.food_id)) ||
       q.before[q.food_slot].amount+q.food_amount>MAX_AMOUNT || q.name.empty() || q.name.size()>=NAME_LENGTH)return false;
    if(Sql_QueryStr(db,"BEGIN IMMEDIATE")!=SQL_SUCCESS)return false;
    if(Sql_Query(db,"SELECT count(*) FROM char WHERE char_id=%u AND account_id=%u AND inventory_slots=%d",q.character,q.account,q.capacity)!=SQL_SUCCESS || scalar(db)!=1)return rollback(db,__LINE__);
    if(Sql_Query(db,"SELECT count(*) FROM ragoff_catalogue_pet_journal WHERE owner_char=%u",q.character)!=SQL_SUCCESS || scalar(db)!=0)return rollback(db,__LINE__);
    const item& voucher=q.before[q.voucher_slot];
    if(Sql_Query(db,"SELECT id FROM inventory WHERE char_id=%u AND nameid=%u AND amount=%d AND %s ORDER BY id LIMIT 1",q.character,voucher.nameid,voucher.amount,condition)!=SQL_SUCCESS)return rollback(db,__LINE__);
    int voucher_id=scalar(db);if(voucher_id<1)return rollback(db,__LINE__);
    int food_id=0;
    if(q.before[q.food_slot].nameid){
        if(Sql_Query(db,"SELECT id FROM inventory WHERE char_id=%u AND nameid=%u AND amount=%d AND %s ORDER BY id LIMIT 1",q.character,q.food_id,q.before[q.food_slot].amount,condition)!=SQL_SUCCESS)return rollback(db,__LINE__);
        food_id=scalar(db);if(food_id<1)return rollback(db,__LINE__);
    }
    char escaped[NAME_LENGTH*2+1];Sql_EscapeStringLen(db,escaped,q.name.c_str(),q.name.size());
    if(Sql_Query(db,"INSERT INTO pet(class,name,account_id,char_id,level,egg_id,equip,intimate,hungry,rename_flag,incubate,autofeed) VALUES(%u,'%s',%u,%u,%u,%u,0,%u,100,0,1,0)",q.monster,escaped,q.account,q.character,q.level,q.egg_id,q.intimacy)!=SQL_SUCCESS)return rollback(db,__LINE__);
    const uint64 pet_id=Sql_LastInsertId(db);if(!pet_id || pet_id>INT32_MAX)return rollback(db,__LINE__);
    egg={};egg.nameid=q.egg_id;egg.identify=1;egg.amount=1;
    egg.card[0]=q.egg_card0;egg.card[1]=pet_id&0xffff;egg.card[2]=(pet_id>>16)&0xffff;egg.card[3]=q.egg_card3;
    if(Sql_Query(db,"INSERT INTO inventory(char_id,nameid,amount,identify,card0,card1,card2,card3) VALUES(%u,%u,1,1,%u,%u,%u,%u)",q.character,q.egg_id,egg.card[0],egg.card[1],egg.card[2],egg.card[3])!=SQL_SUCCESS)return rollback(db,__LINE__);
    if(food_id){if(Sql_Query(db,"UPDATE inventory SET amount=amount+%d WHERE id=%d",q.food_amount,food_id)!=SQL_SUCCESS)return rollback(db,__LINE__);}
    else if(Sql_Query(db,"INSERT INTO inventory(char_id,nameid,amount,identify) VALUES(%u,%u,%d,1)",q.character,q.food_id,q.food_amount)!=SQL_SUCCESS)return rollback(db,__LINE__);
    int rc=voucher.amount==1?Sql_Query(db,"DELETE FROM inventory WHERE id=%d",voucher_id):Sql_Query(db,"UPDATE inventory SET amount=amount-1 WHERE id=%d",voucher_id);
    if(rc!=SQL_SUCCESS || Sql_NumRowsAffected(db)!=1)return rollback(db,__LINE__);
    after=q.before;
    if(--after[q.voucher_slot].amount==0)after[q.voucher_slot]={};
    after[q.egg_slot]=egg;
    auto& food=after[q.food_slot];food.nameid=q.food_id;food.identify=1;food.amount+=q.food_amount;
    const auto before_hex=encode(q.before),after_hex=encode(after);
    if(Sql_Query(db,"INSERT INTO ragoff_catalogue_pet_journal(owner_char,format,item_size,slots,before_hex,after_hex,pet_id) VALUES(%u,1,%u,%u,'%s','%s',%u)",q.character,unsigned(sizeof(item)),unsigned(MAX_INVENTORY),before_hex.c_str(),after_hex.c_str(),unsigned(pet_id))!=SQL_SUCCESS)return rollback(db,__LINE__);
    if(Sql_QueryStr(db,"COMMIT")!=SQL_SUCCESS)return rollback(db,__LINE__);
    return true;
}
bool guard(Sql* db,uint32 character,item* values,bool loading) {
    int enabled=available(db);if(enabled==0)return true;if(enabled!=1)return false;
    if(Sql_Query(db,"SELECT format,item_size,slots,before_hex,after_hex FROM ragoff_catalogue_pet_journal WHERE owner_char=%u",character)!=SQL_SUCCESS)return false;
    const int row=Sql_NextRow(db);
    if(row!=SQL_SUCCESS){Sql_FreeResult(db);return row==SQL_NO_DATA;}
    int dimensions[3];for(int n=0;n<3;++n){char* text=nullptr;Sql_GetData(db,n,&text,nullptr);dimensions[n]=text?std::atoi(text):0;}
    Snapshot before{},after{};char *a=nullptr,*b=nullptr;size_t alen=0,blen=0;
    Sql_GetData(db,3,&a,&alen);Sql_GetData(db,4,&b,&blen);
    bool valid=dimensions[0]==1 && dimensions[1]==sizeof(item) && dimensions[2]==MAX_INVENTORY && a && b && decode(a,alen,before) && decode(b,blen,after);
    Sql_FreeResult(db);if(!valid)return false;
    if(same(values,after.data()))return Sql_Query(db,"DELETE FROM ragoff_catalogue_pet_journal WHERE owner_char=%u",character)==SQL_SUCCESS;
    if(!loading && same(values,before.data())){std::copy(after.begin(),after.end(),values);return true;}
    return false; // Ambiguous or mixed snapshots cannot overwrite the committed inventory.
}
}
